$JIRA_HELP_URL = "https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-transitions-post"

class JiraInaccessibleException : System.Net.Http.HttpRequestException {
  [Uri] $Uri
  
  JiraInaccessibleException([Uri]$Uri, [Exception]$inner) : base("Jira is inaccessible using Uri $Uri", $inner) {
    $this.Uri = $Uri
  }
}

function Get-AuthorizationHeaders {
    [OutputType([hashtable])]
    Param (
        [string]$Username,
        [securestring]$Password
    )

    If ([string]::IsNullOrEmpty($Username)) {
        throw "Username is null or missing" 
    }

    If ([string]::IsNullOrEmpty($Password)) {
        throw "Password is null or missing" 
    }

    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $Username, $Password
    $plainPassword = $cred.GetNetworkCredential().Password

    # Prepare the Basic Authorization header - PSCredential doesn't seem to work
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $Username, $plainPassword)))

    return @{Authorization = ("Basic {0}" -f $base64AuthInfo) }
}

function Invoke-JiraApi {
    [OutputType([PSCustomObject])]
    Param (
        [Uri]$Uri,
        [hashtable]$AdditionalArguments = @{},
        [hashtable]$AuthorizationHeaders = @{},
        [bool]$FailIfNotSuccessfulStatusCode = $true
    )

    Write-Debug "Invoking the Jira API at $($Uri.AbsoluteUri)"

    $arguments = @{
      SkipHttpErrorCheck = $true
      ContentType = "application/json"
      Uri = $Uri
      Headers = $AuthorizationHeaders
    } + $AdditionalArguments

    $ProgressPreference = "SilentlyContinue"
    try {
      # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting
      $result = Invoke-WebRequest @arguments
      
      If ($FailIfNotSuccessfulStatusCode -And ($result.StatusCode -lt 200 -Or $result.StatusCode -gt 299)) {
          throw [System.Net.Http.HttpRequestException] `
            "Failed getting Jira Issues with status code $($result.StatusCode) [$($result.StatusDescription)] and response $result"
      }

      return [PSCustomObject]@{
        StatusCode = $result.StatusCode
        StatusDescription = $result.StatusDescription
        Content = $result.StatusCode -eq 400 ? ($result | ConvertFrom-Json -AsHashTable) : ($result.Content | ConvertFrom-Json)
      }
    } 
    catch [System.Net.Http.HttpRequestException] {
        throw [JiraInaccessibleException]::new($Uri, $_.Exception)
    }
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-search/#api-rest-api-3-search-get
function Get-JiraIssuesByQuery {
    [OutputType([PSCustomObject[]])]
    Param (
        [hashtable]$AuthorizationHeaders,
        [Uri]$BaseUri,
        [string]$Jql,
        [int]$MaxResults = 20,
        [bool]$IncludeDetails = $true
    )

    If ([string]::IsNullOrEmpty($Jql)) {
      throw "Jql is null or missing" 
    }
    
    #TODO: do not return fields, reference metadata instead?
    #expand = $IncludeDetails ? [System.Web.HttpUtility]::UrlEncode("transitions,editmeta") : ""

    $queryParams = @{
        maxResults = $MaxResults
        fields = [System.Web.HttpUtility]::UrlEncode("*all,-comment,-description,-fixVersions,-issuelinks,-reporter,-resolution,-subtasks,-timetracking,-worklog,-project,-watches,-attachment")
        jql = [System.Web.HttpUtility]::UrlEncode($Jql)
    }
    $queryParamsExpanded = $queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    $uri = New-Object -TypeName System.Uri -ArgumentList $BaseUri, `
      ("/rest/api/2/search?$($queryParamsExpanded -join '&')")
    
    $result = Invoke-JiraApi `
      -Uri $uri `
      -AuthorizationHeaders $AuthorizationHeaders `
      -FailIfNotSuccessfulStatusCode $false

    If ($result.StatusCode -eq 404) {
        return @()
    }

    # Jira will return a 400 when a issue doesn't produce any results
    If ($result.StatusCode -eq 400) {
      Write-Warning "Failed getting Jira Issues: $($result.Content | ConvertTo-Json)"
      return @()
    }

    If ($result.StatusCode -ne 200) {
      throw [System.Net.Http.HttpRequestException] `
        "Failed querying {$Jql} getting Jira Issues with status code [$($result.StatusCode)] and response $result"
    }
    
    $issues = $result.Content.issues

    # Do not flattern array if single item
    return ,@($issues)
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v2/api-group-issues/#api-rest-api-2-issue-issueidorkey-get
function Get-JiraIssue {
  [OutputType([PSCustomObject])]
  Param (
      [hashtable]$AuthorizationHeaders,
      [Uri]$BaseUri,
      [string]$IssueKey,
      [bool]$IncludeDetails = $true
  )

  If ([string]::IsNullOrEmpty($IssueKey)) {
    throw "Issue Key is null or missing" 
  }

  $queryParams = @{
    expand = $IncludeDetails ? [System.Web.HttpUtility]::UrlEncode("renderedFields,transitions,editmeta") : ""
  }
  $queryParamsExpanded = $queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
  $uri = New-Object -TypeName System.Uri -ArgumentList $BaseUri, `
    ("/rest/api/2/issue/{0}?{1}" -f $IssueKey, ($queryParamsExpanded -join '&'))

  $result = Invoke-JiraApi `
    -Uri $uri `
    -AuthorizationHeaders $AuthorizationHeaders `
    -FailIfNotSuccessfulStatusCode $false

  If ($result.StatusCode -eq 404) {
      return $null
  }

  If ($result.StatusCode -ne 200) {
      throw [System.Net.Http.HttpRequestException] `
        "Failed getting Jira Issue with status code [$($result.StatusCode)] and response $result"
  }

  return $result.Content
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-transitions-get
function Get-JiraTransitionsByIssue {
    [OutputType([PSCustomObject[]])]
    Param (
        [hashtable]$AuthorizationHeaders,
        [Uri]$IssueUri,
        [bool]$IncludeDetails = $true
    )

    $queryParams = @{
      expand = $IncludeDetails ? "transitions.fields" : ""
    }
    $queryParamsExpanded = $queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }

    $query = $IssueUri.AbsoluteUri + "/transitions?$($queryParamsExpanded -join '&')"
    $uri = [System.Uri] $query
    
    $result = Invoke-JiraApi `
      -Uri $uri `
      -AuthorizationHeaders $AuthorizationHeaders `
      -FailOnRequestFailure $false `
      -FailIfNotSuccessfulStatusCode $false

    If ($result.StatusCode -eq 404) {
        return @()
    }

    If ($result.StatusCode -ne 200) {
        throw [System.Net.Http.HttpRequestException] `
          "Failed getting Jira Issue transitions with status code [$($result.StatusCode)] and response $result"
    }

    # Do not flattern array if single item
    return ,@($result.Content.transitions)
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-transitions-post
function Push-JiraTicketTransition {
    [OutputType([bool])]
    Param (
        [hashtable]$AuthorizationHeaders = @{},
        [Uri]$IssueUri,
        [string]$TransitionId,
        [hashtable]$Fields = @{},
        [hashtable]$Updates = @{}
    )
    
    $runnerUrl = [string]::IsNullOrEmpty($env:GITHUB_SERVER_URL) ? "" : "runner $env:GITHUB_RUNNER_URL"
    $historyMetadata = @{
      activityDescription = "GitHub Workflow Transition"
      description = "via GitHub Actions$runnerUrl"
      type = "myplugin:type"
      actor = @{
        id = "github-actions"
      }
      generator = @{
        id = "github-actions"
        type = "github-application"
      }
      cause = @{
        id = "github-actions"
        type = "github-event"
      }
    }

    $body = @{
      transition = @{
        id = $TransitionId
      }
      fields = $Fields
      update = $Updates
      historyMetadata = $historyMetadata
    } | ConvertTo-Json -Depth 5 -Compress

    $arguments = @{
      Body = $Body
      Method = "Post"
    }

    "Transition body: $($Body | ConvertFrom-Json | ConvertTo-Json -Depth 5)" | Write-Debug

    $query = $IssueUri.AbsoluteUri + "/transitions"
    $uri = [System.Uri] $query

    $result = Invoke-JiraApi `
      -Uri $uri `
      -AuthorizationHeaders $AuthorizationHeaders `
      -AdditionalArguments $arguments `
      -FailIfNotSuccessfulStatusCode $false

    If ($result.StatusCode -eq 204) {
        return $true
    }
      
    If ($result.StatusCode -eq 404) {
        return $false
    }

    If ($result.StatusCode -eq 400) {
      If ($result.Content.errorMessages.Length -eq 0) {
        $result.Content.errorMessages = "Transition Error. See $($env:GITHUB_ACTION_URL ?? $JIRA_HELP_URL) for help."
      }
      
      "Unable to transition issue [$IssueUri] due to $($result.StatusDescription). See errors: $($result.Content | ConvertTo-Json)" `
        | Write-Warning

      return $false
    }
    
    throw [System.Net.Http.HttpRequestException] `
      "Failed transitioning issue with status code [$($result.StatusCode)] and response $result"
}

Export-ModuleMember -Function Push-JiraTicketTransition, Get-JiraTransitionsByIssue, Get-JiraIssuesByQuery, Get-JiraIssue, Invoke-JiraApi, Get-AuthorizationHeaders