param (
    [string]$JiraDomain,
    [string]$JqlToQueryBy,
    [string[]]$IssueKeys,
    [string]$NewState,
    [hashtable]$Fields,
    [hashtable]$Updates,
    [string]$Comment,
    [string]$JiraUsername,
    [securestring]$JiraPassword
)

$global:InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

. $PSScriptRoot\transition-functions.ps1

$baseJiraUri = New-Object -TypeName System.Uri -ArgumentList "https://$JiraDomain/"

if ([string]::IsNullOrEmpty($JqlToQueryBy) -And $IssueKeys.length -gt 0) {
    $JqlToQueryBy = "key IN (""$($IssueKeys -join '", ')"")"
}

$processedIssue = Invoke-JiraTransitionTickets -BaseUri $baseJiraUri `
    -Username $JiraUsername `
    -Password $JiraPassword `
    -Jql $JqlToQueryBy `
    -Transition $NewState `
    -Fields $Fields `
    -Updates $Updates `
    -Comment $Comment
    
$identifiedIssueKeys = $processedIssues.Keys
$transitionedIssueKeys = $processedIssues | Where-Object { $_.Value -eq $true } | Select-Object { $_.Key }
$failedIssueKeys = $processedIssues | Where-Object { $_.Value -eq $false } | Select-Object { $_.Key }
$notFoundIssueKeys = $IssueKeys | Where-Object { $identifiedIssueKeys -notcontains $_ }
    
"identified-issues=$($identifiedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
"identified-issues-as-json=$($identifiedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

"transitioned-issues=$($transitionedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
"transitioned-issues-as-json=$($transitionedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

"failed-issues=$($failedIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
"failed-issues-as-json=$($failedIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

"notfound-issues=$($notFoundIssueKeys -join ', ')" >> $env:GITHUB_OUTPUT
"notfound-issues-as-json=$($notFoundIssueKeys | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT
