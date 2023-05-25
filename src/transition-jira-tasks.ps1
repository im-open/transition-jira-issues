param (
    [string]$JiraDomain,
    [string]$JqlToQueryBy,
    [string[]]$IssueKeys,
    [string]$NewState,
    [hashtable]$Fields,
    [hashtable]$Updates,
    [string]$Comment,
    [boolean]$FailIfNoTransitionedIssues = $false,
    [boolean]$FailIfJiraInaccessible = $false,
    [string]$JiraUsername,
    [securestring]$JiraPassword
)

$global:InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

. $PSScriptRoot\transition-functions.ps1

$baseJiraUri = New-Object -TypeName System.Uri -ArgumentList "https://$JiraDomain/"

If ([string]::IsNullOrEmpty($JqlToQueryBy) -And $IssueKeys.Length -gt 0) {
    $JqlToQueryBy = "key IN (""$($IssueKeys -join '", ')"")"
}

$issues = Get-JiraIssuesByQueryByQuery -BaseUri $BaseUri -Jql $JqlToQueryBy -Username $Username -Password $Password
If ($issues.Length -gt 10) {
  Write-Error "Too many issues returned by the query. Please narrow down the query to return less than or equal to 10 issues."
  Exit 1
}

$processedIssue = Invoke-JiraTransitionTickets `
    -Issues $issues `
    -BaseUri $baseJiraUri `
    -Username $JiraUsername `
    -Password $JiraPassword `
    -TransitionName ($NewState.Trim()) `
    -Fields $Fields `
    -Updates $Updates `
    -Comment $Comment `
    -FailIfJiraInaccessible $FailIfJiraInaccessible
    
$identifiedIssueKeys = $processedIssues.Keys
$transitionedIssueKeys = $processedIssues | Where-Object { $_.Value -eq $true } | Select-Object { $_.Key }
$failedIssueKeys = $processedIssues | Where-Object { $_.Value -eq $false } | Select-Object { $_.Key }
$notFoundIssueKeys = $IssueKeys | Where-Object { $identifiedIssueKeys -notcontains $_ }

If ($queryResult.total -eq 0 -And $FailIfNoTransitionedIssues) {
  Write-Error "No issues were found that matched your query : $JqlToQueryBy"
  exit 1
}

If ($queryResult.total -eq 0 -And !$FailIfNoTransitionedIssues) {
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
