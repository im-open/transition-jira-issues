<#
  .SYNOPSIS
  Transition Jira Issue. 

  .DESCRIPTION
  Test transition Jira Issue prior to performing an action. 

  .PARAMETER issue
  Jira issue key. i.e. ABC-1234

  .PARAMETER transition
  Jira transition name 

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
  PS> .\Test-Transition-Jira-Issue.ps1 -issue ABC-1234 -transition "In Progress" -username Joe -password 1234
#>

param (
    [Alias("issue")]
    [string]$IssueKey,

    [Alias("transition")]
    [string]$TransitionName,

    [Alias("overwrite-fields")]
    [hashtable]$Fields,
    
    [Alias("process-operations")]
    [hashtable]$Updates,
    
    [string]$Comment,

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

if ($issues.Length -eq 0) {
  Write-Error "Issue [$IssueKey] not found"
  exit 1
}
  
$result = Invoke-JiraTransitionTicket `
  -Issue $issues[0] `
  -TransitionName $TransitionName `
  -Fields $Fields `
  -Updates $Updates `
  -Comment $Comment `
  -AuthorizationHeaders $authorizationHeaders `
  -FailIfJiraInaccessible $true

if (!$result) {
  Write-Error "Failed to transition ticket to the state $TransitionName"
  exit 1
}
  
Write-Information "Successfully transitioned ticket to state $TransitionName"