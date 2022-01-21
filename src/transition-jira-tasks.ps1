param (
    [string]$JiraDomain,
    [string]$JqlToQueryBy,
    [string]$NewState,
    [string]$JiraUsername,
    [securestring]$JiraPassword
)

$ErrorActionPreference = "Stop"

. $PSScriptRoot\transition-functions.ps1

$baseJiraUri = New-Object -TypeName System.Uri -ArgumentList "https://$JiraDomain/"

Invoke-JiraTransitionTickets -BaseUri $baseJiraUri `
    -Username $JiraUsername `
    -Password $JiraPassword `
    -Jql $JqlToQueryBy `
    -Transition $NewState