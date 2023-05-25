Import-Module (Join-Path $PSScriptRoot "JiraApis.psm1")

function New-Comment {
    Param (
        [string]$Comment
    )

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
    [OutputType([bool])]
    Param (
        [hashtable]$AuthorizationHeaders,
        [PSCustomObject]$Issue,
        [string]$TransitionName,
        [hashtable]$Fields = @{},
        [hashtable]$Updates = @{},
        [string]$Comment = "",
        [bool]$FailIfJiraInaccessible = $false
    )

    If ([string]::IsNullOrEmpty($TransitionName)) {
      throw "Transition name is null or missing" 
    }

    $issueKey = $Issue.key
    $issueUri = $Issue.self
    $issueStatus = $Issue.fields.status.name
    
    $transitions = Get-JiraTransitionsByIssue `
      -IssueUri $issueUri `
      -AuthorizationHeaders $AuthorizationHeaders `
      -IncludeDetails $true

    # Include status names with possible transitions
    $transitionIdLookup = @{}
    foreach ($transition in $transitions) {
        $transitionIdLookup[$transition.name] = $transition.id
        $transitionIdLookup[$transition.to.name] = $transition.id
    }

    If ($issueStatus -ieq $TransitionName) {
      "[$issueKey] Issue already in status [$issueStatus] Skipping transition... Available transitions: $($transitionIdLookup.Keys -join ', ')" `
        | Write-Information

      return $true
    }

    $transitionId = $transitionIdLookup[$TransitionName]
    If ($null -eq $transitionId) {
        "[$issueKey] Unable to perform transition [$TransitionName] on issue! Available transitions: $($transitionIdLookup.Keys -join ', ')" `
          | Write-Warning 

        return $false
    }

    $availableFields = @{}
    if ($Fields.Count -gt 0) {
        $issueFieldNames = $Issue.fields.psobject.Properties.Name

        $availableFields = $Fields.GetEnumerator() | ForEach-Object -Begin { $accumulator = @{} } `
          -Process { if ($issueFieldNames -ccontains $_.Key) { $accumulator[$_.Key] = $_.Value } } `
          -End { $accumulator }

        $unavailableFields = $Fields.Keys | Where-Object { $availableFields.Keys -cnotcontains $_ } 

        If ($availableFields.Length -eq 0) {
          "[$issueKey] No valid fields were identified for the issue (they are case-sensitive). No field changes will be applied." `
            | Write-Warning

          return $false
        }

        If ($unavailableFields.Count -gt 0) {
            "[$issueKey] Fields were omitted because they are not valid for the issue (they are case-sensitive): $($unavailableFields -join ', ')" `
              | Write-Warning
        }
    }

    Write-Information "[$issueKey] Transitioning issue from [$issueStatus] to [$TransitionName]..."

    return Push-JiraTicketTransition `
      -IssueUri $issueUri `
      -TransitionId $transitionId `
      -Fields $availableFields `
      -Updates (New-Comment $Comment) + $Updates `
      -AuthorizationHeaders $AuthorizationHeaders `
      -FailIfJiraInaccessible $FailIfJiraInaccessible
}

Export-ModuleMember -Function Invoke-JiraTransitionTicket