param (
    [string]$TransitionName,
    [string]$JqlToQueryBy,
    [string[]]$IssueKeys = @(),
    [hashtable]$Fields = @{},
    [hashtable]$Updates = @{},
    [string]$Comment,
    [string]$JiraDomain = "jira.extendhealth.com",
    [string]$JiraUsername,
    [securestring]$JiraPassword,
    [switch]$FailIfNoTransitionedIssues = $false,
    [switch]$FailIfNotFoundIssues = $false,
    [switch]$FailIfJiraInaccessible = $false
)

$global:InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "modules" "JiraApis.psm1")
Import-Module (Join-Path $PSScriptRoot "modules" "TransitionIssue.psm1")

$MAX_ISSUES_TO_TRANSITION = 20
$MESSAGE_TITLE = "Jira Ticket Transitions"

$env:GITHUB_RUNNER_URL = "{0}/{1}/actions/runs/{2}" -f $env:GITHUB_SERVER_URL, $env:GITHUB_REPOSITORY, $env:GITHUB_RUN_ID 
$env:GITHUB_JOB_URL = "{0}/jobs/{1}" -f $env:GITHUB_RUNNER_URL, $env:GITHUB_JOB
$env:GITHUB_ACTION_URL = "{0}/{1}" -f $env:GITHUB_SERVER_URL, $env:GITHUB_ACTION_REPOSITORY

$throttleLimit = $env:ACTIONS_STEP_DEBUG -ieq "true" ? 1 : 5

try {
    $baseUri = New-Object -TypeName System.Uri -ArgumentList "https://$JiraDomain/"
    $authorizationHeaders = Get-AuthorizationHeaders -Username $JiraUsername -Password $JiraPassword 
    Write-Output "::add-mask::$($authorizationHeaders.Authorization)"

    If ([string]::IsNullOrEmpty($JqlToQueryBy) -And $IssueKeys.Length -gt 0) {
        $JqlToQueryBy = "key IN ($($IssueKeys -join ","))"
    }

    If ([string]::IsNullOrEmpty($JqlToQueryBy)) {
        Write-Error "Either the JQL or a list of issue keys must be provided"
        Exit 1
    } 

    $issues = Get-JiraIssuesByQuery `
      -BaseUri $baseUri `
      -Jql $JqlToQueryBy `
      -AuthorizationHeaders $authorizationHeaders `
      -MaxResults $MAX_ISSUES_TO_TRANSITION `
      -FailIfJiraInaccessible $FailIfJiraInaccessible

    If ($issues.Length -gt $MAX_ISSUES_TO_TRANSITION) {
      "Too many issues returned by the query [$($.issues.Length)]. Adjust the the query to return less than or equal to $MAX_ISSUES_TO_TRANSITION issues." `
        | Write-Error
      Exit 1
    }

    # https://stackoverflow.com/questions/61273189/how-to-pass-a-custom-function-inside-a-foreach-object-parallel
    $processedIssues = [System.Collections.Concurrent.ConcurrentDictionary[string, boolean]]::new()
    $issues | ForEach-Object -Parallel {
        $issue = $_
        $safeProcessedIssues = $using:processedIssues
        $safeTranstionName = $using:TransitionName
        $safeFailIfJiraInaccessible = $using:FailIfJiraInaccessible

        Import-Module (Join-Path $using:PSScriptRoot "modules" "TransitionIssue.psm1")

        try {
            
            $result = Invoke-JiraTransitionTicket `
              -AuthorizationHeaders $using:AuthorizationHeaders `
              -Issue $issue `
              -TransitionName $safeTranstionName `
              -Fields $using:Fields `
              -Updates $using:Updates `
              -Comment $using:Comment `
              -FailIfJiraInaccessible $safeFailIfJiraInaccessible 

            $added = $safeProcessedIssues.TryAdd($issue.key, $result)
            Write-Debug "Added [$($issue.key)] to processed issues: $added"
      }
      catch {
          $safeProcessedIssues.TryAdd($issue.key, $false)
          If ($safeFailIfJiraInaccessible) {
              throw
          }
          Else {
            Write-Error $_.Exception.Message 
          }
      } 
    } -ThrottleLimit $throttleLimit 

    # Don't flattern the array
    $identifiedIssueKeys = @($processedIssues.Keys)
    $transitionedIssueKeys = $processedIssues.ToArray() | Where-Object { $_.Value -eq $true } | ForEach-Object { $_.Key }
    $failedIssueKeys = $identifiedIssueKeys | Where-Object { $transitionedIssueKeys -notcontains $_ }
    $notFoundIssueKeys = $IssueKeys | Where-Object { $identifiedIssueKeys -notcontains $_ }

    Write-Information "Identified issues: $($identifiedIssueKeys -join ', ')"
    Write-Information "Transitioned issues: $($transitionedIssueKeys -join ', ')"
    Write-Information "Failed issues: $($failedIssueKeys -join ', ')"
    Write-Information "Not found issues: $($notFoundIssueKeys -join ', ')"

    # Outputs
    "identifiedIssues=$($identifiedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "identifiedIssuesAsJson=$($identifiedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

    "transitionedIssues=$($transitionedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "transitionedIssuesAsJson=$($transitionedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

    "failedIssues=$($failedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "failedIssuesAsJson=$($failedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

    "notfoundIssues=$($notFoundIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "notfoundIssuesAsJson=$($notFoundIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

    If ($identifiedIssueKeys.Length -eq 0 -And $FailIfNoTransitionedIssues) {
        Write-Output "::error title=$MESSAGE_TITLE::No issues were found that match query {$JqlToQueryBy}"
        exit 1
    }

    If ($identifiedIssueKeys.Length -eq 0 -And !$FailIfNoTransitionedIssues) {
        Write-Output "::warning title=$MESSAGE_TITLE::No issues were found that match query {$JqlToQueryBy}"
        return
    }

    If ($failedIssueKeys.Length -gt 0 -And $FailIfNoTransitionedIssues) {
        Write-Output "::error title=$MESSAGE_TITLE::Failed to transition $($failedIssueKeys -join ', ') to [$TransitionName]. You might need to include the update of a missing field value. See logs for details: $env:GITHUB_JOB_URL"
        exit 1
    }

    If ($failedIssueKeys.Length -gt 0 -And !$FailIfNoTransitionedIssues) {
        Write-Output "::warning title=$MESSAGE_TITLE::Unable to transition $($failedIssueKeys -join ', ') to [$TransitionName]. You might need to include the update of a missing field value. See logs for details: $env:GITHUB_JOB_URL"
    }

    If ($notFoundIssueKeys.Length -gt 0 -And $FailIfNotFoundIssues) {
        Write-Output "::error title=$MESSAGE_TITLE::$($notFoundIssueKeys -join ', ') not found in Jira using query {$JqlToQueryBy}"
        exit 1
    }

    If ($notFoundIssueKeys.Length -gt 0 -And !$FailIfNotFoundIssues) {
        Write-Output "::warning title=$MESSAGE_TITLE::$($notFoundIssueKeys -join ', ') not found in Jira using query {$JqlToQueryBy}"
    }

    If ($transitionedIssueKeys.Length -gt 0) {
        Write-Output "::notice title=$MESSAGE_TITLE::$($transitionedIssueKeys -join ', ') successfully transitioned to [$TransitionName]"
    }
}
finally {
    Remove-Module -Name JiraApis
    Remove-Module -Name TransitionIssue
}
