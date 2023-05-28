using module "./src/modules/JiraApis.psm1"

<#
  .SYNOPSIS
  Gets Jira isssue details.

  .DESCRIPTION
  Gets Jira isssue details to help determine what fields values the action should accept.

  .PARAMETER issue
  Jira issue key. i.e. ABC-1234

  .PARAMETER extendhealth-username
  Your ExtendHealth Jira username.

  .PARAMETER extendhealth-login
  Your ExtendHealth Jira password.

  .PARAMETER jira-base-uri
  Jira domain. Defaults to https://jira.extendhealth.com

  .INPUTS
  None. You cannot pipe objects to Update-Month.ps1.

  .OUTPUTS
  Jira details as JSON 

  .EXAMPLE
  PS> .\Test-Get-Jira-Issue.ps1 -issue ABC-1234 -username Joe -password 1234
#>

param (
    [Alias("issue")]
    [string]$IssueKey,

    [Alias("extendhealth-username")]
    [string]$Username,

    [Alias("extendhealth-login")]
    [string]$Login,

    [Alias("jira-base-uri")]
    [string]$JiraBaseUri = "https://jira.extendhealth.com",

    [switch]$Debug = $false
)

$global:InformationPreference = "Continue"
$isDebug = $env:RUNNER_DEBUG -eq "1" -Or $Debug
$global:DebugPreference = $isDebug ? "Continue" : "SilentlyContinue"

try {
  [System.Security.SecureString] $securePassword = ConvertTo-SecureString $Login -AsPlainText -Force
  $baseUri = New-Object -TypeName System.Uri -ArgumentList $JiraBaseUri
  $authorizationHeaders = Get-AuthorizationHeaders -Username $Username -Password $securePassword 

  $issue = Get-JiraIssue `
    -AuthorizationHeaders $authorizationHeaders `
    -BaseUri $baseUri `
    -IssueKey $IssueKey

  If ($null -eq $issue) {
    Write-Error "Issue [$IssueKey] not found"
    exit 1
  }

  $issue | ConvertTo-Json -Depth 10 | Write-Output
  Set-Content -Path "./issues.json" -Value ($issue | ConvertTo-Json -Depth 5)
}
finally {
  Remove-Module JiraApis
  $global:InformationPreference = "SilentlyContinue"
  $global:DebugPreference = "SilentlyContinue"
}