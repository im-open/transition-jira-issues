using module "./JiraApis.psm1"

Enum TransitionResultType {
  Unknown
  Unavailable
  Success
  Failed
  Skipped
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-transitions-post
function Invoke-JiraTransitionTicket {
    [OutputType([TransitionResultType])]
    Param (
        [hashtable]$AuthorizationHeaders,
        [PSCustomObject]$Issue,
        [string]$TransitionName,
        [hashtable]$Fields = @{},
        [hashtable]$Updates = @{},
        [string]$Comment = ""
    )

    If ([string]::IsNullOrEmpty($TransitionName)) {
      throw "Transition name is null or missing" 
    }

    $issueKey = $Issue.key
    $issueUri = $Issue.self
    $issueStatus = $Issue.fields.status.name

    If ([string]::IsNullOrEmpty($issueKey)) {
      throw "Issue Key is null or missing"
    }

    If ([string]::IsNullOrEmpty($issueUri)) {
      throw "Issue Uri is null or missing"
    }

    If ([string]::IsNullOrEmpty($issueStatus)) {
      throw "Issue Status is null or missing"
    }

    $issueType = $Issue.fields.issuetype.name
    $issueSummary = $Issue.fields.summary
    $issueLabels = $Issue.fields.labels
    $issueComponents = $Issue.fields.components
    $transitions = $Issue.transitions
    
    Write-Debug "[$issueKey] $issueType : $issueSummary -> processing with labels [$( `
      $issueLabels -join ', ')] and components [$(@($issueComponents | Select-Object -ExpandProperty name) -join ', ')]"

    $resultType = [TransitionResultType]::Unknown
    try {
        $transitions = Get-JiraTransitionsByIssue `
          -AuthorizationHeaders $AuthorizationHeaders `
          -IssueUri $issueUri
        
        $transitionIdLookup = @{}
        foreach ($transition in $transitions) {
            $transitionIdLookup[$transition.name] = $transition.id
            # Include status names with possible transitions
            $transitionIdLookup[$transition.to.name] = $transition.id
        }
    
        If ($issueStatus -ieq $TransitionName) {
          "[$issueKey] $issueType already in status [$issueStatus]. Skipping transition! Available transitions: $($transitionIdLookup.Keys -join ', ')" `
            | Write-Warning
    
          return [TransitionResultType]::Skipped 
        }
    
        $transitionId = $transitionIdLookup[$TransitionName]
        If ($null -eq $transitionId) {
            "[$issueKey] Missing transition [$TransitionName] on $issueType! Currently in [$issueStatus] state. Available transitions: $($transitionIdLookup.Keys -join ', ')" `
              | Write-Warning 
    
            return [TransitionResultType]::Unavailable
        }
        
        # TODO: Include field names and Ids or can the API interpret that for us?
        # TODO: Filter out updates as well
        $availableFields = @{}
        If ($Fields.Count -gt 0) {
            
            $issueFieldNames = $Issue.editmeta.fields.psobject.Properties.Name
    
            $availableFields = $Fields.GetEnumerator() | ForEach-Object -Begin { $accumulator = @{} } `
              -Process { If ($issueFieldNames -ccontains $_.Key) { $accumulator[$_.Key] = $_.Value } } `
              -End { $accumulator }
    
            $unavailableFields = $Fields.Keys | Where-Object { $availableFields.Keys -cnotcontains $_ } 
    
            If (!$availableFields -Or $availableFields.Length -eq 0) {
              "[$issueKey] No valid fields were identified for $issueType (they are case-sensitive). No field changes will be applied." `
                | Write-Warning
            }
    
            If ($unavailableFields.Count -gt 0) {
                "[$issueKey] Fields were omitted because they are not valid for the issue (they are case-sensitive): $($unavailableFields -join ', ')" `
                  | Write-Warning
            }
        }
    
        # TODO: filter updates if they are not valid for the issue type: 1) fields exists, 2) field is valid for issue type
        $updated = Update-JiraTicket `
          -AuthorizationHeaders $AuthorizationHeaders `
          -IssueUri $issueUri `
          -Fields $availableFields `
          -Updates $Updates
        
        If (!$updated) {
          "[$issueKey] Unable to update fields for $issueType. Skipping transition!" `
            | Write-Warning
    
          return [TransitionResultType]::Failed
        }
    
        Write-Information "[$issueKey] Transitioning $issueType from [$issueStatus] to [$TransitionName]..."
    
        $processed = Push-JiraTicketTransition `
          -AuthorizationHeaders $AuthorizationHeaders `
          -IssueUri $issueUri `
          -TransitionId $transitionId `
          -Comment $Comment
  
        $resultType = $processed ? [TransitionResultType]::Success : [TransitionResultType]::Failed
    }
    catch [JiraInaccessibleException] {
        $resultType = [TransitionResultType]::Failed
        if ($safeFailIfJiraInaccessible) { throw }
        $resultType = [TransitionResultType]::Skipped
        Write-Warning "[$($issue.key)] Unable to continue transitioning. Skipping!"
        Write-Warning $_.Exception.MessageWithResponse()
        Write-Debug $_.ScriptStackTrace
    }
    
    return $resultType
}

Export-ModuleMember -Function Invoke-JiraTransitionTicket