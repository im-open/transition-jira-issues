using module "./modules/TransitionIssue.psm1"

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
    [switch]$MissingTransitionAsSuccessful = $false,
    [switch]$FailIfNoTransitionedIssues = $false,
    [switch]$FailIfNotFoundIssue = $false,
    [switch]$FailIfJiraInaccessible = $false
)

$MAX_ISSUES_TO_TRANSITION = 20
$MESSAGE_TITLE = "Jira Ticket Transitions"

$ErrorActionPreference = "Stop"
$global:InformationPreference = "Continue"
$isDebug = $env:RUNNER_DEBUG -eq "1"
$global:DebugPreference = $isDebug ? "Continue" : "SilentlyContinue"

$throttleLimit = $isDebug ? 1 : 5

$env:GITHUB_RUNNER_URL = "{0}/{1}/actions/runs/{2}" -f $env:GITHUB_SERVER_URL, $env:GITHUB_REPOSITORY, $env:GITHUB_RUN_ID 
$env:GITHUB_ACTION_URL = "{0}/{1}" -f $env:GITHUB_SERVER_URL, $env:GITHUB_ACTION_REPOSITORY

$modulesPath = Join-Path $PSScriptRoot "modules"

try {
    Import-Module (Join-Path $modulesPath "JiraApis.psm1")
    Import-Module (Join-Path $modulesPath "TransitionIssue.psm1")
  
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

    If ($issues.Length -eq 0 -And !$FailIfJiraInaccessible) {
      "::warning title=$MESSAGE_TITLE::No issues were found that match query {$JqlToQueryBy}. Jira might be down. Skipping check..." `
        | Write-Output
      Exit 0
    }

    If ($issues.Length -gt $MAX_ISSUES_TO_TRANSITION) {
      "Too many issues returned by the query [$($.issues.Length)]. Adjust the the query to return less than or equal to $MAX_ISSUES_TO_TRANSITION issues." `
        | Write-Error
      Exit 1
    }

    # https://stackoverflow.com/questions/61273189/how-to-pass-a-custom-function-inside-a-foreach-object-parallel
    $processedIssues = [System.Collections.Concurrent.ConcurrentDictionary[string, TransitionResultType]]::new()
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
            Write-Debug "Added [$($issue.key)] with result [$result] to processed issues: $added"
      }
      catch {
          $safeProcessedIssues.TryAdd($issue.key, [TransitionResultType]::Failed)
          If ($safeFailIfJiraInaccessible) {
              throw
          }
          Else {
            Write-Error $_.Exception.Message 
          }
      } 
    } -ThrottleLimit $throttleLimit 

    # Don't flattern the array @()
    $identifiedIssueKeys = @($processedIssues.Keys)
    
    $transitionedIssueKeys = @($processedIssues.ToArray() | Where-Object { $_.Value -eq [TransitionResultType]::Success } | ForEach-Object { $_.Key })
    $skippedIssueKeys = @($processedIssues.ToArray() | Where-Object { $_.Value -eq [TransitionResultType]::Skipped } | ForEach-Object { $_.Key })
    $unavailableTransitionIssueKeys = @($processedIssues.ToArray() | Where-Object { $_.Value -eq [TransitionResultType]::Unavailable } | ForEach-Object { $_.Key })
    
    $successfulyProcessedIssueKeys = $transitionedIssueKeys + $skippedIssueKeys
    
    If (!$MissingTransitionAsSuccessful) {
      $successfulyProcessedIssueKeys += $unavailableTransitionIssueKeys
    }

    $failedIssueKeys = @($identifiedIssueKeys | Where-Object { $successfulyProcessedIssueKeys -notcontains $_ })
    $notFoundIssueKeys = $IssueKeys.Length -gt 0 ? @($IssueKeys | Where-Object { $identifiedIssueKeys -notcontains $_ }) : @()

    Write-Debug "All successfully processed to transition: $($successfulyProcessedIssueKeys -join ', ')"
    Write-Information "All issues to transition: $($identifiedIssueKeys -join ', ')"
    Write-Information "Issues transitioned: $($transitionedIssueKeys -join ', ')"
    Write-Information "Skipped issues with transition already performed: $($skippedIssueKeys -join ', ')"
    Write-Information "Issues missing transition step and skipped: $($unavailableTransitionIssueKeys -join ', ')"
    Write-Information "Issues unable to be transitioned: $($failedIssueKeys -join ', ')"

    If ($IssueKeys.Length -gt 0) {
      Write-Information "Issues not found: $( $notFoundIssueKeys -join ', ' )"
    }

    # Outputs
    "identifiedIssues=$($identifiedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "processedIssues=$($successfulyProcessedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "transitionedIssues=$($transitionedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "unavailableTransitionIssue=$($unavailableTransitionIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "failedIssues=$($failedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "notfoundIssues=$($notFoundIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT

    If ($identifiedIssueKeys.Length -eq 0 -And $FailIfNoTransitionedIssues) {
        Write-Output "::error title=$MESSAGE_TITLE::No issues were found that match query {$JqlToQueryBy}"
        exit 1
    }

    If ($identifiedIssueKeys.Length -eq 0 -And !$FailIfNoTransitionedIssues) {
        Write-Output "::warning title=$MESSAGE_TITLE::No issues were found that match query {$JqlToQueryBy}"
        return
    }

    If ($failedIssueKeys.Length -gt 0 -And $FailIfNoTransitionedIssues) {
        Write-Output "::error title=$MESSAGE_TITLE::Failed to transition $($failedIssueKeys -join ', ') to [$TransitionName]. You might need to include a missing field value or use the '' action input. See job [$env:GITHUB_JOB_URL] logs for details."
        exit 1
    }

    If ($failedIssueKeys.Length -gt 0 -And !$FailIfNoTransitionedIssues) {
        Write-Output "::warning title=$MESSAGE_TITLE::Unable to transition $($failedIssueKeys -join ', ') to [$TransitionName]. You might need to include a missing field value. See job [$env:GITHUB_JOB_URL] logs for details."
    }

    If ($notFoundIssueKeys.Length -gt 0 -And $FailIfNotFoundIssue) {
        Write-Output "::error title=$MESSAGE_TITLE::$($notFoundIssueKeys -join ', ') not found in Jira using query {$JqlToQueryBy}"
        exit 1
    }

    If ($notFoundIssueKeys.Length -gt 0 -And !$FailIfNotFoundIssue) {
        Write-Output "::warning title=$MESSAGE_TITLE::$($notFoundIssueKeys -join ', ') not found in Jira using query {$JqlToQueryBy}"
    }

    If ($successfulyProcessedIssueKeys.Length -gt 0) {
        Write-Output "::notice title=$MESSAGE_TITLE::$(@($transitionedIssueKeys + $skippedIssueKeys) -join ', ') successfully transitioned to [$TransitionName]"
    }
}
finally {
    Remove-Module -Name JiraApis
    Remove-Module -Name TransitionIssue
}
