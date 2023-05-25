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
  PS> .\Get-Jira-Issue.ps1 -issue ABC-1234 -username Joe -password 1234
#>

param (
    [Alias("issue")]
    [string]$IssueKey,

    [Alias("extendhealth-username")]
    [string]$Username,

    [Alias("extendhealth-login")]
    [string]$Login,

    [Alias("jira-base-uri")]
    [string]$JiraBaseUri = "https://jira.extendhealth.com"
)

$global:InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

. ./src/transition-functions.ps1

[System.Security.SecureString] $securePassword = ConvertTo-SecureString $Login -AsPlainText -Force
$baseUri = New-Object -TypeName System.Uri -ArgumentList $JiraBaseUri
$authorizationHeaders = Get-AuthorizationHeaders -Username $Username -Password $securePassword 

$issues = Get-JiraIssuesByQuery `
  -BaseUri $baseUri `
  -Jql "key = $IssueKey" `
  -AuthorizationHeaders $authorizationHeaders `
  -FailIfJiraInaccessible $true

# TODO: merge with issues fields to show the display name of the field
# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-custom-field-contexts/#api-rest-api-3-field-fieldid-context-get
# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-fields/#api-rest-api-3-field-get

# TODO: get fields required by transition

if ($issues.Length -eq 0) {
  Write-Error "Issue [$IssueKey] not found"
  exit 1
}

$issues | ConvertTo-Json -Depth 10 | Write-Output
Set-Content -Path "./issues.json" -Value ($issues | ConvertTo-Json -Depth 10)