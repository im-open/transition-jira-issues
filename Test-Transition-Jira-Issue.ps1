using module "./src/modules/JiraApis.psm1"
using module "./src/modules/TransitionIssue.psm1"

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

  $issues = Get-JiraIssuesByQuery `
    -BaseUri $baseUri `
    -Jql "key = $IssueKey" `
    -AuthorizationHeaders $authorizationHeaders `

  If ($issues.Length -eq 0) {
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

  If ($result -ne [TransitionResultType]::Success) {
    Write-Error "Failed to transition ticket to the state [$TransitionName] with a result of [$result]"
    exit 1
  }
    
  Write-Information "Successfully transitioned ticket to state [$TransitionName] with a result of [$result]"
}
finally {
  Remove-Module JiraApis
  Remove-Module TransitionIssue
  $global:InformationPreference = "SilentlyContinue"
  $global:DebugPreference = "SilentlyContinue"
}