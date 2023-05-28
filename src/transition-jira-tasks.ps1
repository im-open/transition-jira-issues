using module "./modules/JiraApis.psm1"
using module "./modules/TransitionIssue.psm1"

param (
    [string]$TransitionName,
    [string]$JqlToQueryBy,
    [string[]]$IssueKeys = @(),
    [hashtable]$Fields = @{},
    [hashtable]$Updates = @{},
    [string]$Comment,
    [string]$JiraDomain = "jira.extendhealth.com",
    [string]$JiraUsername,
    [securestring]$JiraPassword,
    [switch]$MissingTransitionAsSuccessful = $false,
    [switch]$FailIfNoTransitionedIssues = $false,
    [switch]$FailIfNotFoundIssue = $false,
    [switch]$FailIfJiraInaccessible = $false,
    [switch]$Debug = $false
)

$MAX_ISSUES_TO_TRANSITION = 20
$MESSAGE_TITLE = "Jira Ticket Transitions"

$global:InformationPreference = "Continue"
$isDebug = $env:RUNNER_DEBUG -eq "1" -Or $Debug
$global:DebugPreference = $isDebug ? "Continue" : "SilentlyContinue"

$throttleLimit = $isDebug ? 1 : 5

$env:GITHUB_RUNNER_URL = "{0}/{1}/actions/runs/{2}" -f $env:GITHUB_SERVER_URL, $env:GITHUB_REPOSITORY, $env:GITHUB_RUN_ID 
$env:GITHUB_ACTION_URL = "{0}/{1}" -f $env:GITHUB_SERVER_URL, $env:GITHUB_ACTION_REPOSITORY

function Write-IssueListOutput {
  Param (
      [string]$name, 
      [string[]]$issueKeys, 
      [string]$message = $null,
      [switch]$conditional,
      [switch]$warn = $null, 
      [switch]$debug = $null
    )

    $issueKeysAsString = $issueKeys -join ', '
    "$name=$issueKeysAsString" >> $env:GITHUB_OUTPUT

    If ([string]::IsNullOrEmpty($message)) { return }
    If ($conditional -And $issueKeys.Length -eq 0) { return }
  
    $message = "{0}: {1}" -f $message, $issueKeysAsString
    If ($debug) {
      Write-Debug $message
    }
    ElseIf ($warn) {
      Write-Warning $message
    }
    Else {
      Write-Information $message
    }
}

try {
    $baseUri = New-Object -TypeName System.Uri -ArgumentList "https://$JiraDomain/"
    $authorizationHeaders = Get-AuthorizationHeaders -Username $JiraUsername -Password $JiraPassword 
    Write-Output "::add-mask::$($authorizationHeaders.Authorization)"

    If ([string]::IsNullOrEmpty($JqlToQueryBy) -And $IssueKeys.Length -gt 0) {
        $JqlToQueryBy = "key IN ($($IssueKeys -join ","))"
    }

    If ([string]::IsNullOrEmpty($JqlToQueryBy)) {
        Write-Error "Either the JQL or a list of issue keys must be provided"
        Exit 1
    } 
    
    $issues = @()
    try {
        $issues = Get-JiraIssuesByQuery `
          -AuthorizationHeaders $authorizationHeaders `
          -BaseUri $baseUri `
          -Jql $JqlToQueryBy `
          -MaxResults $MAX_ISSUES_TO_TRANSITION
    }
    catch [JiraHttpRequesetException] {
        if ($FailIfJiraInaccessible) { throw }
        Write-Warning "Jira might be down. Skipping transitions..."
        Write-Warning $_.Exception.MesageWithResponse()
        Write-Debug $_.ScriptStackTrace
    }

    If ($issues.Length -eq 0 -And !$FailIfJiraInaccessible) {
        "::warning title=$MESSAGE_TITLE::No issues were found that match query {$JqlToQueryBy}. Jira might be down. Skipping check..." `
          | Write-Output
        Exit 0
    }

    If ($issues.Length -gt $MAX_ISSUES_TO_TRANSITION) {
        "Too many issues returned by the query [$($.issues.Length)]. Adjust the the query to return less than or equal to $MAX_ISSUES_TO_TRANSITION issues." `
          | Write-Error
        Exit 1
    }

    # TODO: attempt to not use concurrent dictionary
    $processedIssues = [System.Collections.Concurrent.ConcurrentDictionary[string, TransitionResultType]]::new()
    $exceptions = $issues | ForEach-Object -Parallel {
        # Creates its own scope, so have to reimport any modules used.
        # Cannot import in classes or types, so have to specific string values for enums and standard exception classes
        Import-Module (Join-Path $using:PSScriptRoot "modules" "TransitionIssue.psm1")
        $global:DebugPreference = $using:isDebug ? "Continue" : "SilentlyContinue"
        
        $issue = $_
        $safeProcessedIssues = $using:processedIssues
        $safeTranstionName = $using:TransitionName
        $safeFailIfJiraInaccessible = $using:FailIfJiraInaccessible
       
        try {
            $resultType = Invoke-JiraTransitionTicket `
              -AuthorizationHeaders $using:AuthorizationHeaders `
              -Issue $issue `
              -TransitionName $safeTranstionName `
              -Fields $using:Fields `
              -Updates $using:Updates `
              -Comment $using:Comment
  
            $added = $safeProcessedIssues.TryAdd($issue.key, $resultType)
            Write-Debug "Added [$( $issue.key )] with result [$resultType] to processed issues? $added"
        }
        catch {
            return $_.Exception
        }
    } -ThrottleLimit $throttleLimit
    
    if ($exceptions.Length -gt 0) {
        $exceptions | Where-Object { $_ -ne $null } | ForEach-Object {
            Write-Error -Exception $_
        } 
        Exit 1
    }

    # Process Results
    # ------------  
    
    # Don't flattern the array @()
    $identifiedIssueKeys = @($processedIssues.Keys)
    
    $transitionedIssueKeys = @($processedIssues.ToArray() | Where-Object { $_.Value -eq [TransitionResultType]::Success } | ForEach-Object { $_.Key })
    $skippedIssueKeys = @($processedIssues.ToArray() | Where-Object { $_.Value -eq [TransitionResultType]::Skipped } | ForEach-Object { $_.Key })
    $unavailableTransitionIssueKeys = @($processedIssues.ToArray() | Where-Object { $_.Value -eq [TransitionResultType]::Unavailable } | ForEach-Object { $_.Key })
    
    $successfulyProcessedIssueKeys = $transitionedIssueKeys + $skippedIssueKeys
    
    If ($MissingTransitionAsSuccessful -And $unavailableTransitionIssueKeys.Length -gt 0) {
        Write-Warning "Issues missing transition will be treated as a successful transition!"
        $successfulyProcessedIssueKeys += $unavailableTransitionIssueKeys
    }

    $failedIssueKeys = @($identifiedIssueKeys | Where-Object { $successfulyProcessedIssueKeys -notcontains $_ })
    $notFoundIssueKeys = $IssueKeys.Length -gt 0 ? @($IssueKeys | Where-Object { $identifiedIssueKeys -notcontains $_ }) : @()

    # Outputs
    # ------------  
    Write-IssueListOutput -name "processedIssues" -issueKeys $successfulyProcessedIssueKeys -message "All successfully processed transitions" -debug
    Write-IssueListOutput -name "identifiedIssues" -issueKeys $identifiedIssueKeys -message "All issues to transition"
    Write-IssueListOutput -name "transitionedIssues" -issueKeys $transitionedIssueKeys -message "Issues transitioned"
    Write-IssueListOutput -name "failedIssues" -issueKeys $failedIssueKeys -message "Issues unable to be transitioned"
    Write-IssueListOutput -name "unavailableTransitionIssue" -issueKeys $unavailableTransitionIssueKeys -message "Issues missing transition step and skipped" -conditional
    Write-IssueListOutput -name "skippedIssues" -issueKeys $skippedIssueKeys -message "Skipped issues with transition already performed" -conditional
    Write-IssueListOutput -name "notfoundIssues" -issueKeys $notFoundIssueKeys -message "Issues not found" -conditional
    
    # Notices on Runner
    # ------------
    If ($identifiedIssueKeys.Length -eq 0 -And $FailIfNoTransitionedIssues) {
        Write-Output "::error title=$MESSAGE_TITLE::No issues were found that match query {$JqlToQueryBy}"
        Exit 1
    }

    If ($identifiedIssueKeys.Length -eq 0 -And !$FailIfNoTransitionedIssues) {
        Write-Output "::warning title=$MESSAGE_TITLE::No issues were found that match query {$JqlToQueryBy}"
        Exit 0 
    }

    If ($failedIssueKeys.Length -gt 0 -And $FailIfNoTransitionedIssues) {
        Write-Output "::error title=$MESSAGE_TITLE::Failed to transition $( `
          $failedIssueKeys -join ', ') to [$TransitionName]. You might need to include a missing field value or use the '' action input. See job [$env:GITHUB_JOB_URL] logs for details."
        Exit 1
    }

    If ($failedIssueKeys.Length -gt 0 -And !$FailIfNoTransitionedIssues) {
        Write-Output "::warning title=$MESSAGE_TITLE::Unable to transition $( `
          $failedIssueKeys -join ', ') to [$TransitionName]. You might need to include a missing field value. See job [$env:GITHUB_JOB_URL] logs for details."
    }

    If ($notFoundIssueKeys.Length -gt 0 -And $FailIfNotFoundIssue) {
        Write-Output "::error title=$MESSAGE_TITLE::$($notFoundIssueKeys -join ', ') not found in Jira using query {$JqlToQueryBy}"
        Exit 1
    }

    If ($notFoundIssueKeys.Length -gt 0 -And !$FailIfNotFoundIssue) {
        Write-Output "::warning title=$MESSAGE_TITLE::$($notFoundIssueKeys -join ', ') not found in Jira using query {$JqlToQueryBy}"
    }

    If ($successfulyProcessedIssueKeys.Length -gt 0) {
        Write-Output "::notice title=$MESSAGE_TITLE::$(@($transitionedIssueKeys + $skippedIssueKeys) -join ', ') transitioned to [$TransitionName]"
    }
    
    Exit 0
}
catch {
    Write-Error -Exception $_.Exception

    If ($_.Exception -is [JiraHttpRequesetException]) {
      Write-Error "Unable to continue. Jira might be down."
      Write-Error "Response: $($_.Exception.Response)"
    }
    
    Write-Error $_.ScriptStackTrace
    Exit 1
}
finally {
    Remove-Module -Name JiraApis
    Remove-Module -Name TransitionIssue
    $global:InformationPreference = "SilentlyContinue"
    $global:DebugPreference = "SilentlyContinue"
}
