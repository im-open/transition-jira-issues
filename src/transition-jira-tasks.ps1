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
    [bool]$FailIfNoTransitionedIssues = $false,
    [bool]$FailIfJiraInaccessible = $false
)

$global:InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "modules" "JiraApis.psm1")
Import-Module (Join-Path $PSScriptRoot "modules" "TransitionIssue.psm1")

$MAX_ISSUES_TO_TRANSITION = 20
$MESSAGE_TITLE = "Jira Ticket Transitions"

$env:GITHUB_RUNNER_URL = "{0}/{1}/actions/runs/{2}" -f $env:GITHUB_SERVER_URL, $env:GITHUB_REPOSITORY, $env:GITHUB_RUN_ID 
$env:GITHUB_JOB_URL = "{0}/jobs/{1}" -f $env:GITHUB_RUNNER_URL, $env:GITHUB_JOB

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
      -FailIfJiraInaccessible $true

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

            $safeProcessedIssues.TryAdd($issue.key, $result)
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

    $identifiedIssueKeys = $processedIssues.Keys
    $transitionedIssueKeys = $processedIssues | Where-Object { $_.Value -eq $true } | Select-Object { $_.Key }
    $failedIssueKeys = $processedIssues | Where-Object { $_.Value -eq $false } | Select-Object { $_.Key }
    $notFoundIssueKeys = $IssueKeys | Where-Object { $identifiedIssueKeys -notcontains $_ }

    # Outputs
    "identified-issues=$($identifiedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "identified-issues-as-json=$($identifiedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

    "transitioned-issues=$($transitionedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "transitioned-issues-as-json=$($transitionedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

    "failed-issues=$($failedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "failed-issues-as-json=$($failedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

    "notfound-issues=$($notFoundIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "notfound-issues-as-json=$($notFoundIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

    If ($identifiedIssueKeys.Length -eq 0 -And $FailIfNoTransitionedIssues) {
        Write-Output "::error title=$MESSAGE_TITLE::No issues were found that matched query [$JqlToQueryBy]"
        exit 1
    }

    If ($identifiedIssueKeys.Length -eq 0 -And !$FailIfNoTransitionedIssues) {
        Write-Output "::notice title=$MESSAGE_TITLE::No issues were found that matched query [$JqlToQueryBy]"
        return
    }

    If ($identifiedIssueKeys.Length -eq 0 -And !$FailIfNoTransitionedIssues) {
        Write-Output "::warning title=$MESSAGE_TITLE::The issues [$($failedIssueKeys -join ', ')] are not found in Jira with matching query [$JqlToQueryBy]"
    }

    If ($failedIssueKeys.Length -gt 0 -And $FailIfNoTransitionedIssues) {
        Write-Output "::error title=$MESSAGE_TITLE::Failed to transition issues [$($failedIssueKeys -join ', ')] with matching query [$JqlToQueryBy]. You might need to include the update of a missing field value. See logs for details. $env:GITHUB_JOB_URL"
        exit 1
    }

    If ($failedIssueKeys.Length -gt 0 -And !$FailIfNoTransitionedIssues) {
        Write-Output "::warning title=$MESSAGE_TITLE::Unable to transition issues [$($failedIssueKeys -join ', ')] with matching query [$JqlToQueryBy]. You might need to include the update of a missing field value. See logs for details. $env:GITHUB_JOB_URL"
    }
}
finally {
    Remove-Module -Name JiraApis
    Remove-Module -Name TransitionIssue
}
