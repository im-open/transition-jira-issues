Import-Module (Join-Path $PSScriptRoot "JiraApis.psm1")

function New-Comment {
    Param (
        [string]$Comment
    );

    If ([string]::IsNullOrEmpty($Comment)) {
        return @{} 
    }

    return @(
      comment = @{
        add = @{
            body = $Comment
        }
      }
    )
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-transitions-post
function Invoke-JiraTransitionTicket {
    [OutputType([boolean])]
    Param (
        [hashtable]$AuthorizationHeaders,
        [PSCustomObject]$Issue,
        [string]$TransitionName,
        [hashtable]$Fields = @{},
        [hashtable]$Updates = @{},
        [string]$Comment = "",
        [boolean]$FailIfJiraInaccessible = $false
    );

    If ([string]::IsNullOrEmpty($TransitionName)) {
      throw "Transition Name is null or missing" 
    }

    $issueKey = $Issue.key
    $issueUri = $Issue.self
    $issueStatus = $Issue.fields.status.name
    
    $transitions = Get-JiraTransitionsByIssue -IssueUri $issueUri -AuthorizationHeaders $AuthorizationHeaders -IncludeDetails $true

    # Include status names with possible transitions
    $transitionIdLookup = @{}
    foreach ($transition in $transitions) {
        $transitionIdLookup[$transition.name] = $transition.id
        $transitionIdLookup[$transition.to.name] = $transition.id
    }

    If ($issueStatus -ieq $TransitionName) {
      Write-Information "Issue [$issueKey] is already in status [$issueStatus]. Skipping transition to [$TransitionName]..."
      Write-Information "Available transitions: $($transitionIdLookup.Keys -join ', ')"
      return $true
    }

    $transitionId = $transitionIdLookup[$TransitionName]
    If ($null -eq $transitionId) {
        # TODO: Write to github notice
        Write-Warning "Unable to perform transition [$TransitionName] on issue [$issueKey]. Available transitions: $($transitionIdLookup.Keys -join ', ')"
        return $false
    }

    $availableFields = @{}
    if ($Fields.Count -gt 0) {
        $issueFieldNames = $Issue.fields.psobject.Properties.Name | ForEach-Object { $_.toLower() } 

        $availableFields = $Fields.GetEnumerator() | ForEach-Object -Begin { $accumulator = @{} } `
          -Process { if ($issueFieldNames -contains $_.Key.ToLower()) { $accumulator[$_.Key] = $_.Value } } `
          -End { $accumulator }

        $unavailableFields = $Fields.Keys | Where-Object { $availableFields.Keys -notcontains $_.ToLower() } 

        If ($availableFields.Length -eq 0) {
          Write-Warning "No valid fields were identified for the issue [$issueKey]"
          return $false
        }

        If ($unavailableFields.Count -gt 0) {
            Write-Warning "The following fields were omitted because they are not valid for the issue [$issueKey]: $($unavailableFields -join ', ')"
        }
    }

    Write-Information "Transitioning issue [$issueKey] from [$issueStatus] to [$TransitionName]..."

    return Push-JiraTicketTransition `
      -IssueUri $issueUri `
      -TransitionId $transitionId `
      -Fields $availableFields `
      -Updates (New-Comment $Comment) + $Updates `
      -AuthorizationHeaders $AuthorizationHeaders `
      -FailIfJiraInaccessible $FailIfJiraInaccessible
}

Export-ModuleMember -Function Invoke-JiraTransitionTicket