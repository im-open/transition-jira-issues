using module "./modules/JiraApis.psm1"
using module "./modules/TransitionIssue.psm1"

param (
    [string]$TransitionName,
    [string]$JqlToQueryBy,
    [string[]]$IssueKeys = @(),
    [hashtable]$Fields = @{},
    [hashtable]$Updates = @{},
    [string]$Comment,
    [string]$JiraDomain,
    [string]$JiraUsername,
    [securestring]$JiraPassword,
    [switch]$MissingTransitionAsSuccessful = $false,
    [switch]$CreateWarningNotices = $false,
    [switch]$FailOnTransitionFailure = $false,
    [switch]$FailIfIssueExcluded = $false,
    [switch]$FailIfJiraInaccessible = $false,
    [switch]$Debug = $false
)

$MAX_ISSUES_TO_TRANSITION = 20
$MESSAGE_TITLE = "Jira Issue Transitions"

$global:InformationPreference = "Continue"
$isDebug = $env:RUNNER_DEBUG -eq "1" -Or $Debug
$global:DebugPreference = $isDebug ? "Continue" : "SilentlyContinue"

$throttleLimit = $isDebug ? 1 : $MAX_ISSUES_TO_TRANSITION 

$env:GITHUB_RUNNER_URL = "{0}/{1}/actions/runs/{2}" -f $env:GITHUB_SERVER_URL, $env:GITHUB_REPOSITORY, $env:GITHUB_RUN_ID
$env:GITHUB_ACTION_URL = "{0}/{1}" -f $env:GITHUB_SERVER_URL, "im-open/transition-jira-issues"

Function Write-IssueListOutput {
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
    "has_$name=$(($issueKeys.Length -gt 0).ToString().ToLower())" >> $env:GITHUB_OUTPUT

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
        $JqlToQueryBy = "key IN ($($IssueKeys -join ", "))"
    }
    ElseIf ($IssueKeys.Length -gt 0) {
        $JqlToQueryBy = "($($JqlToQueryBy)) AND key IN ($($IssueKeys -join ", "))"
    }
    
    If ([string]::IsNullOrEmpty($JqlToQueryBy)) {
        Write-Error "Either the JQL and/or a list of issue keys must be provided"
        Exit 1
    }

    Write-Information "Searching for issue using query:`n$JqlToQueryBy"
    
    $issues = @()
    try {
        $issues = Get-JiraIssuesByQuery `
          -AuthorizationHeaders $authorizationHeaders `
          -BaseUri $baseUri `
          -Jql $JqlToQueryBy `
          -IncludeDetails `
          -MaxResults ($MAX_ISSUES_TO_TRANSITION + 1)
    }
    catch [JiraHttpRequesetException] {
        if ($FailIfJiraInaccessible) { throw }
        Write-Warning "Jira might be down. Skipping transitions..."
        Write-Warning $_.Exception.MessageWithResponse()
        Write-Debug $_.ScriptStackTrace
    }
    
    If ($issues.Length -gt $MAX_ISSUES_TO_TRANSITION) {
        "Too many issues returned by the query [$($issues.Length)]. Adjust the the query to return less than or equal to $MAX_ISSUES_TO_TRANSITION issues." `
          | Write-Error
        Exit 1
    }

    If ($issues.Length -eq 0 -And !$FailIfJiraInaccessible -And $CreateWarningNotices) {
        Write-Warning "No issues were found that match query {$JqlToQueryBy}. Jira might be down. Skipping check..."
    }

    If ($issues.Length -gt 0) {
        Write-Information "Processing $($issues.Length) issues from query with results [$(@($issues | Select-Object -ExpandProperty key) -join ', ')]..."
    }

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
            $resultType = Invoke-JiraTransitionIssue `
              -AuthorizationHeaders $using:AuthorizationHeaders `
              -Issue $issue `
              -TransitionName $safeTranstionName `
              -Fields $using:Fields `
              -Updates $using:Updates `
              -Comment $using:Comment
  
            $added = $safeProcessedIssues.TryAdd($issue.key, $resultType)
            Write-Debug "[$( $issue.key )] processed with result [$resultType] to processed issues? $added"
        }
        catch {
            return $_.Exception
        }
    } -ThrottleLimit $throttleLimit
    
    if ($exceptions.Count -gt 0) {
        $exceptions | Where-Object { $_ -ne $null } | ForEach-Object {
            Write-Error -Exception $_
            Write-Debug $_.ScriptStackTrace
        } 
        Exit 1
    }

    # Process Results
    # ------------  
    
    # Don't flattern the array @()
    $identifiedIssueKeys = @($issues | Select-Object -ExpandProperty key)
    
    $transitionedIssueKeys = @($processedIssues.ToArray() | Where-Object { $_.Value -eq [TransitionResultType]::Success } | ForEach-Object { $_.Key })
    $skippedIssueKeys = @($processedIssues.ToArray() | Where-Object { $_.Value -eq [TransitionResultType]::Skipped } | ForEach-Object { $_.Key })
    $unavailableTransitionIssueKeys = @($processedIssues.ToArray() | Where-Object { $_.Value -eq [TransitionResultType]::Unavailable } | ForEach-Object { $_.Key })
    $excludedIssueKeys = $IssueKeys.Length -gt 0 ? @($IssueKeys | Where-Object { $identifiedIssueKeys -inotcontains $_ }) : @()
    
    $successfulyProcessedIssueKeys = $transitionedIssueKeys + $skippedIssueKeys
    
    If ($MissingTransitionAsSuccessful -And $unavailableTransitionIssueKeys.Length -gt 0) {
        Write-Information "Issues missing transition will be treated as successful!"
        $successfulyProcessedIssueKeys += $unavailableTransitionIssueKeys
    }
    $failedIssueKeys = @($identifiedIssueKeys | Where-Object { $successfulyProcessedIssueKeys -inotcontains $_ })

    # Outputs
    # ------------  
    "isSuccessful=$(($failedIssueKeys.Length -eq 0 -And !($FailIfIssueExcluded -And $excludedIssueKeys.Length -gt 0)).ToString().ToLower())" >> $env:GITHUB_OUTPUT

    Write-IssueListOutput -name "identifiedIssues" -issueKeys $identifiedIssueKeys -message "All issues attempted to transition"
    Write-IssueListOutput -name "processedIssues" -issueKeys $successfulyProcessedIssueKeys -message "All successfully processed transitions" -debug
    Write-IssueListOutput -name "transitionedIssues" -issueKeys $transitionedIssueKeys -message "Issues transitioned"
    Write-IssueListOutput -name "failedIssues" -issueKeys $failedIssueKeys -message "Issues unable to be transitioned"
    Write-IssueListOutput -name "unavailableTransitionIssues" -issueKeys $unavailableTransitionIssueKeys -message "Issues missing transition step" -conditional
    Write-IssueListOutput -name "skippedIssues" -issueKeys $skippedIssueKeys -message "Skipped issues with transition already performed" -conditional
    Write-IssueListOutput -name "excludedIssues" -issueKeys $excludedIssueKeys -message "Issues excluded from query" -conditional
    
    # Notices on Runner
    # ------------

    If ($failedIssueKeys.Length -gt 0 -And $FailOnTransitionFailure) {
        Write-Output "::error title=$MESSAGE_TITLE::Failed to transition $( `
          $failedIssueKeys -join ', ') to [$TransitionName]. You might need to include a missing field value or use the 'missing-transition-as-successful' action input to ignore missing transitions. See job logs for details and action $env:GITHUB_ACTION_URL for additional help."
        Exit 1
    }

    If ($failedIssueKeys.Length -gt 0 -And !$FailOnTransitionFailure -And $CreateWarningNotices) {
        Write-Output "::warning title=$MESSAGE_TITLE::Unable to transition $($failedIssueKeys -join ', ') to [$TransitionName]."
    }
    
    If ($unavailableTransitionIssueKeys.Length -gt 0 -And $FailOnTransitionFailure -And !$MissingTransitionAsSuccessful) {
        Write-Output "::error title=$MESSAGE_TITLE::$($unavailableTransitionIssueKeys -join ', ') missing transition [$TransitionName]. You may enable 'missing-transition-as-successful' to treat these as a successful transition."
        Exit 1
    }

    If ($excludedIssueKeys.Length -gt 0 -And $FailIfIssueExcluded) {
        Write-Output "::error title=$MESSAGE_TITLE::$($excludedIssueKeys -join ', ') excluded from origin query {$JqlToQueryBy}"
        Exit 1
    }

    If ($excludedIssueKeys.Length -gt 0 -And !$FailIfIssueExcluded -And $CreateWarningNotices) {
        Write-Output "::warning title=$MESSAGE_TITLE::$($excludedIssueKeys -join ', ') excluded from origin query {$JqlToQueryBy}"
    }

    If ($excludedIssueKeys.Length -eq 0 -And $successfulyProcessedIssueKeys.Length -eq 0 -And $CreateWarningNotices) {
        Write-Output "::warning title=$MESSAGE_TITLE::No issues were transitioned into [$TransitionName]."
    }

    Exit 0
}
catch {
    Write-Error -Exception $_.Exception

    If ($_.Exception -is [JiraHttpRequesetException]) {
      Write-Error "Unable to continue. Jira might be down."
      Write-Error "Response: $($_.Exception.Response)"
    }
    
    Write-Debug $_.ScriptStackTrace
    Exit 1
}
finally {
    Remove-Module -Name JiraApis
    Remove-Module -Name TransitionIssue
    $global:InformationPreference = "SilentlyContinue"
    $global:DebugPreference = "SilentlyContinue"
}
