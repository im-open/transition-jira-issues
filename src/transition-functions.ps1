. $PSScriptRoot\jira-api-interactions.ps1

function Invoke-JiraGetTransitions {
    Param (
        [Uri]$TransitionsUri,
        [string]$Username,
        [securestring]$Password
    );

    $transitions = Invoke-JiraQuery -Query $TransitionsUri -Username $Username -Password $Password
    return $transitions.transitions
}

function Invoke-JiraTransitionTicket {
    Param (
        [Uri]$IssueUri,
        [string]$IssueKey,
        [string]$Username,
        [securestring]$Password,
        [string]$Transition
    );

    $query = $IssueUri.AbsoluteUri + "/transitions"
    $uri = [System.Uri] $query

    $transitions = Invoke-JiraGetTransitions -TransitionsUri $uri -Username $Username -Password $Password
    $match = $transitions | Where-Object { $_.name -eq $Transition } | Select-Object -First 1
    $urlToRun = "https://github.com/$Env:GITHUB_REPOSITORY/actions/runs/$Env:GITHUB_RUN_ID"
    $comment = "Status automatically updated via GitHub Actions. Link to the run: $urlToRun."
    
    if ($null -ne $match) {
        $transitionId = $match.id
        $body = "{ ""update"": { ""comment"": [ { ""add"" : { ""body"" : ""$comment"" } } ] }, ""transition"": { ""id"": ""$transitionId"" } }"

        Invoke-JiraTicketTransition -Uri $uri -Body $body -Username $Username -Password $Password
        Write-Output "Successfully transitioned ticket $IssueKey to the state $Transition"
    }
    else {
        Write-Output "The transition $Transition is not valid for the issue $IssueKey."
    }
}

function Invoke-JiraTransitionTickets {
    Param (
        [Uri]$BaseUri,
        [string]$Username,
        [securestring]$Password,
        [string]$Jql,
        [string]$Transition
    );

    $api = New-Object -TypeName System.Uri -ArgumentList $BaseUri, ("/rest/api/2/search?jql=" + $Jql)
    $json = Invoke-JiraQuery -Query $api -Username $Username -Password $Password

    If ($json.total -eq 0) {
        Write-Output "No issues were found that matched your query : $Jql"
    }
    Else {
        ForEach ($issue in $json.issues) {
            Invoke-JiraTransitionTicket -IssueUri $issue.self -IssueKey $issue.key -Transition $Transition -Username $Username -Password $Password
        }
    }
}