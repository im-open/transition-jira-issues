param (
    [string]$JiraDomain,
    [string]$JqlToQueryBy,
    [string]$NewState,
    [string]$JiraUsername,
    [securestring]$JiraPassword
)

$global:InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

. $PSScriptRoot\transition-functions.ps1

$baseJiraUri = New-Object -TypeName System.Uri -ArgumentList "https://$JiraDomain/"

$issues = Invoke-JiraTransitionTickets -BaseUri $baseJiraUri `
    -Username $JiraUsername `
    -Password $JiraPassword `
    -Jql $JqlToQueryBy `
    -Transition $NewState
    
$identifiedIssues = $issues.Keys
$transitionedIssues = $issues | Where-Object { $_.Value -eq $true } | Select-Object { $_.Key }
$failedIssues = $issues | Where-Object { $_.Value -eq $false } | Select-Object { $_.Key }
    
"identified-issues=$($identifiedIssues -join ', ')" >> $env:GITHUB_OUTPUT
"identified-issues-as-json=$($identifiedIssues | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

"transitioned-issues=$($transitionedIssues -join ', ')" >> $env:GITHUB_OUTPUT
"transitioned-issues-as-json=$($transitionedIssues | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

"failed-issues=$($failedIssues -join ', ')" >> $env:GITHUB_OUTPUT
"failed-issues-as-json=$($transitionedIssues | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT

"notfound-issues=$($issuesNotFound -join ', ')" >> $env:GITHUB_OUTPUT
"notfound-issues-as-json=$($issuesNotFound | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT
