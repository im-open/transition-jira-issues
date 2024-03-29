using module "./src/modules/JiraApis.psm1"

<#
  .SYNOPSIS
  Gets Jira isssue details.

  .DESCRIPTION
  Gets Jira isssue details to help determine what fields values the action should accept.

  .PARAMETER issue
  Jira issue key. i.e. ABC-1234

  .PARAMETER username
  Your Jira username.

  .PARAMETER login
  Your Jira password.

  .PARAMETER jira-base-uri
  Jira domain.

  .INPUTS
  None. You cannot pipe objects.

  .OUTPUTS
  Jira details as JSON 

  .EXAMPLE
  PS> .\Test-Get-Jira-Issue.ps1 -issue ABC-1234 -username Joe -password 1234
#>

param (
    [Parameter(Mandatory=$true)]
    [Alias("issue")]
    [string]$IssueKey,

    [Parameter(Mandatory=$true)]
    [string]$Username,

    [Parameter(Mandatory=$true)]
    [string]$Login,

    [Parameter(Mandatory=$true)]
    [Alias("jira-base-uri")]
    [string]$JiraBaseUri
)

$global:InformationPreference = "Continue"
$global:DebugPreference = $env:RUNNER_DEBUG -eq "1" ? "Continue" : $DebugPreference

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

  Set-Content -Path "./issues.json" -Value ($issue | ConvertTo-Json -Depth 10)
  Write-Information "Issue [$IssueKey] details written to ./issues.json"
}
finally {
  Remove-Module JiraApis
  $global:InformationPreference = "SilentlyContinue"
  $global:DebugPreference = "SilentlyContinue"
}
