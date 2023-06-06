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
  PS> .\Test-Transition-Jira-Issue.ps1 -issue ABC-1234 -transition "In Progress" -username Joe -password 1234
#>
param (
    [Parameter(Mandatory=$true)]
    [Alias("issue")]
    [string]$IssueKey,

    [Parameter(Mandatory=$true)]
    [Alias("transition")]
    [string]$TransitionName,

    [Alias("update-fields")]
    [hashtable]$Fields,
    
    [Alias("process-operations")]
    [hashtable]$Updates,
    
    [string]$Comment,

    [Parameter(Mandatory=$true)]
    [string]$Username,

    [Parameter(Mandatory=$true)]
    [string]$Login,

    [Parameter(Mandatory=$true)]
    [Alias("jira-base-uri")]
    [string]$JiraBaseUri
)

$global:InformationPreference = "Continue"
$global:DebugPreference = $DebugPreference

try {
  [System.Security.SecureString] $securePassword = ConvertTo-SecureString $Login -AsPlainText -Force
  $baseUri = New-Object -TypeName System.Uri -ArgumentList $JiraBaseUri
  $authorizationHeaders = Get-AuthorizationHeaders -Username $Username -Password $securePassword 

  $issues = Get-JiraIssuesByQuery `
    -AuthorizationHeaders $authorizationHeaders `
    -BaseUri $baseUri `
    -Jql "key = $IssueKey" `
    -IncludeDetails

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
}
