using module "./JiraApis.psm1"

function New-Comment {
    Param (
        [string]$Comment
    )
    
    If ([string]::IsNullOrEmpty($Comment)) {
        return @{} 
    }

    return @{
      comment = @(
        @{
          add = @{
            body = $Comment
          }
        }
      )
    }
}

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
    $issueType = $Issue.fields.issuetype.name
    $issueSummary = $Issue.fields.summary
    $issueStatus = $Issue.fields.status.name
    $issueLabels = $Issue.fields.labels
    $issueComponents = $Issue.fields.components
    
    Write-Debug "[$issueKey] $issueType : $issueSummary -> processing with labels [$($issueLabels -join ', ')] and components [$(@($issueComponents | Select-Object -ExpandProperty name) -join ', ')]"

    $resultType = [TransitionResultType]::Unknown
    try {
        # TODO: include transition IDs
        $transitions = Get-JiraTransitionsByIssue `
          -IssueUri $issueUri `
          -AuthorizationHeaders $AuthorizationHeaders
        
        # Include status names with possible transitions
        $transitionIdLookup = @{}
        foreach ($transition in $transitions) {
            $transitionIdLookup[$transition.name] = $transition.id
            $transitionIdLookup[$transition.to.name] = $transition.id
        }
    
        # TODO: If there are updates or fields, still continue with the transition, update the Issue as is.
        If ($issueStatus -ieq $TransitionName) {
          "[$issueKey] $issueType already in status [$issueStatus]. Skipping transition! Available transitions: $($transitionIdLookup.Keys -join ', ')" `
            | Write-Warning
    
          return [TransitionResultType]::Skipped 
        }
    
        $transitionId = $transitionIdLookup[$TransitionName]
        If ($null -eq $transitionId) {
            "[$issueKey] Missing transition [$TransitionName] on $issueType! Current in [$issueStatus] state. Available transitions: $($transitionIdLookup.Keys -join ', ')" `
              | Write-Warning 
    
            return [TransitionResultType]::Unavailable
        }
        
        # TODO: Transition fields & updates have to be on the screen, get from transitions API
    
        $availableFields = @{}
        If ($Fields.Count -gt 0) {
            
            $issueFieldNames = $Issue.fields.psobject.Properties.Name
    
            $availableFields = $Fields.GetEnumerator() | ForEach-Object -Begin { $accumulator = @{} } `
              -Process { 
                If ($issueFieldNames -ccontains $_.Key) { $accumulator[$_.Key] = $_.Value }
    
                # TODO: filter fields if they are not valid for the issue type
    #            If ($_.Value.issueType -eq $null -Or $_.Value.issueType -ieq $issueType -Or $_.Value.issueType -is [array] -And $_.Value.issueType -icontains $issueType ) { $accumulator[$_.Key] = $_.Value }
                
              } `
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
    
        Write-Information "[$issueKey] Transitioning $issueType from [$issueStatus] to [$TransitionName]..."
    
        $processed = Push-JiraTicketTransition `
          -IssueUri $issueUri `
          -TransitionId $transitionId `
          -Fields $availableFields `
          -Updates ((New-Comment $Comment) + $Updates) `
          -AuthorizationHeaders $AuthorizationHeaders
  
        $resultType = $processed ? [TransitionResultType]::Success : [TransitionResultType]::Failed
    }
    catch [JiraInaccessibleException] {
        $resultType = [TransitionResultType]::Failed
        if ($safeFailIfJiraInaccessible) { throw }
        $resultType = [TransitionResultType]::Skipped
        Write-Warning "[$($issue.key)] Unable to continue transition. Skipping! $($_.Exception)"
    }
    
    return $resultType
}

Export-ModuleMember -Function Invoke-JiraTransitionTicket