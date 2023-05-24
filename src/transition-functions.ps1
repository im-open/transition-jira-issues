. $PSScriptRoot\jira-api-interactions.ps1

function New-Comment {
  [OutputType([hashtable])]
    Param (
        [string]$Comment
    );

    if ([string]::IsNullOrEmpty($Comment)) {
        return @{} 
    }

    return @(
      comment = @{
        add = @{
            body = $Comment
        }
      }
    )
}

function New-HistoryMetadata {
    $urlToRun = "https://github.com/$Env:GITHUB_REPOSITORY/actions/runs/$Env:GITHUB_RUN_ID"
    return @{
        activityDescription = "GitHub Transition"
        description = "Status automatically updated via GitHub Actions. Link to the run: $urlToRun."
        transitionName = $Transition
    }
}

function Invoke-JiraGetTransitions {
    Param (
        [Uri]$IssueUri,
        [string]$Username,
        [securestring]$Password
    );

    $query = $IssueUri.AbsoluteUri + "/transitions"
    $uri = [System.Uri] $query

    $transitions = Invoke-JiraQuery -Query $uri -Username $Username -Password $Password
    return $transitions.transitions
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-editmeta-get
function Invoke-JiraGetTicketFields {
  Param (
      [Uri]$IssueUri,
      [string]$Username,
      [securestring]$Password
  );

  $query = $IssueUri.AbsoluteUri + "/editmeta"
  $uri = [System.Uri] $query

  $metadata = Invoke-JiraQuery -Query $uri -Username $Username -Password $Password
  return $metadata.fields | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-transitions-post
function Invoke-JiraTransitionTicket {
    [OutputType([boolean])]
    Param (
        [Uri]$IssueUri,
        [string]$IssueKey,
        [string]$Username,
        [securestring]$Password,
        [string]$Transition,
        [hashtable]$Fields,
        [hashtable]$Updates,
        [string]$Comment
    );

    $transitions = Invoke-JiraGetTransitions -IssueUri $IssueUri -Username $Username -Password $Password
    $match = $transitions | Where-Object { $_.name -eq $Transition } | Select-Object -First 1
    
    if ($null -ne $match) {
        $transitionId = $match.id
        
        $body = @{
            transition = @{
                id = $transitionId
            }
            update = (New-Comment $Comment) + $Updates
            fields = $Fields
            historyMetadata = New-HistoryMetadata
        } 

        Write-Information "Transitioning the issue $IssueKey to $Transition using the following body: $($body | ConvertTo-Json)"
        return Invoke-JiraTicketTransition -Uri $uri -Body ($body | ConvertTo-Json -Compress) -Username $Username -Password $Password
    }
    else {
        Write-Information "The transition $Transition is not valid for the issue $IssueKey."
        return $false
    }
}

function Invoke-JiraTransitionTickets {
    [OutputType([hashtable[]])]
    Param (
        [Uri]$BaseUri,
        [string]$Username,
        [securestring]$Password,
        [string]$Jql,
        [string]$Transition,
        [PSCustomObject]$Fields,
        [PSCustomObject]$Updates,
        [string]$Comment
    );

    $api = New-Object -TypeName System.Uri -ArgumentList $BaseUri, ("/rest/api/2/search?jql=" + [System.Web.HttpUtility]::UrlEncode($Jql))
    $json = Invoke-JiraQuery -Query $api -Username $Username -Password $Password

    If ($json.total -eq 0) {
        Write-Information "No issues were found that matched your query : $Jql"
        return @()
    }
    
    $processedIssues = @{}
    $json.issues | ForEach-Object { $processedIssues.Add($_.key, $false) }
    
    $json.issues | ForEach-Object -Parallel {
        $fieldNames = Invoke-JiraGetTicketFields -IssueUri $issue.self -Username $Username -Password $Password | ForEach-Object { $_.ToLower() }
        $filteredFields = $Fields.GetEnumerator() | Where-Object { $fieldNames -contains $_.Key.ToLower() } 
        $omittedFields = $Fields.Keys | Where-Object { $filteredFields.Keys -notcontains $_ } 

        if ($omittedFields.Count -gt 0) {
            Write-Warning "The following fields were omitted because they are not valid for the issue $($issue.key): $($omittedFields -join ', ')"
        }

        $result = Invoke-JiraTransitionTicket `
          -Username $Username `
          -Password $Password `
          -IssueUri $issue.self `
          -IssueKey $issue.key`
          -Transition $Transition `
          -Fields $filteredFields `
          -Updates $Updates `
          -Comment $Comment
          
        $processedIssues[$issue.key] = $result
        
        if ($result) {
            Write-Information "Successfully transitioned ticket $($issue.key) to the state $Transition"
        }
    }
    
    return $processedIssues
}
