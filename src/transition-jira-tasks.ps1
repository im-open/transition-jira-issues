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
    [boolean]$FailIfNoTransitionedIssues = $false,
    [boolean]$FailIfJiraInaccessible = $false
)

$global:InformationPreference = "Continue"
$global:DebugPreference = "Continue"
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "modules" "TransitionIssue.psm1")

try {
    $baseUri = New-Object -TypeName System.Uri -ArgumentList "https://$JiraDomain/"
    $authorizationHeaders = Get-AuthorizationHeaders -Username $JiraUsername -Password $JiraPassword 

    If ([string]::IsNullOrEmpty($JqlToQueryBy) -And $IssueKeys.Length -gt 0) {
        $JqlToQueryBy = "key IN ($($IssueKeys -join ","))"
    }

    $issues = Get-JiraIssuesByQuery `
      -BaseUri $baseUri `
      -Jql $JqlToQueryBy `
      -AuthorizationHeaders $authorizationHeaders `
      -FailIfJiraInaccessible $true

    If ($issues.Length -gt 10) {
      Write-Error "Too many issues returned by the query. Please narrow down the query to return less than or equal to 10 issues."
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

            # If ($result) {
            #   Write-Information "Successfully transitioned ticket [$($issue.key)] to the state [$safeTranstionName]"
            # }
            # Else {
            #   Write-Warning "Failed to transition ticket [$($issue.key)] to the state [$safeTranstionName]" 
            # }
              
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
    } -ThrottleLimit 5 

    # TODO: If Github debug, limit throttle to 2

    $identifiedIssueKeys = $processedIssues.Keys
    $transitionedIssueKeys = $processedIssues | Where-Object { $_.Value -eq $true } | Select-Object { $_.Key }
    $failedIssueKeys = $processedIssues | Where-Object { $_.Value -eq $false } | Select-Object { $_.Key }
    $notFoundIssueKeys = $IssueKeys | Where-Object { $identifiedIssueKeys -notcontains $_ }

    If ($identifiedIssueKeys.Length -eq 0 -And $FailIfNoTransitionedIssues) {
      Write-Error "No issues were found that matched your query : $JqlToQueryBy"
      exit 1
    }

    If ($identifiedIssueKeys.Length -eq 0 -And !$FailIfNoTransitionedIssues) {
      Write-Warning "No issues were found that matched your query : $JqlToQueryBy"
      return
    }

    # Outputs
    "identified-issues=$($identifiedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "identified-issues-as-json=$($identifiedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

    "transitioned-issues=$($transitionedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "transitioned-issues-as-json=$($transitionedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

    "failed-issues=$($failedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "failed-issues-as-json=$($failedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

    "notfound-issues=$($notFoundIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
    "notfound-issues-as-json=$($notFoundIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT
}
finally {
    Remove-Module -Name JiraApis
    Remove-Module -Name TransitionIssue
}
