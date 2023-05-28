$JIRA_HELP_URL = "https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-transitions-post"

class JiraHttpRequesetException : System.Net.Http.HttpRequestException {
  [Uri] $Uri
  [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] $Response

  JiraHttpRequesetException([string]$message, [Uri]$Uri, [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject]$response) : `
    base("$message - status code [$($response.StatusCode)] using Uri $($Uri)") {
      $this.Uri = $Uri
      $this.Response = $response
  }

  [string] MesageWithResponse() {
      return "{0}: {1}" -f $this.Message, $this.Response.Content
  }

  [string] ToString() {
      return $this.MesageWithResponse()
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
        [switch]$SkipHttpErrorCheck = $false
    )

    Write-Debug "Invoking the Jira API at $($Uri.AbsoluteUri)"

    $arguments = @{
      SkipHttpErrorCheck = $SkipHttpErrorCheck
      ContentType = "application/json"
      Uri = $Uri
      Headers = $AuthorizationHeaders
    } + $AdditionalArguments

    $ProgressPreference = "SilentlyContinue"
    
    try {
        $response = Invoke-WebRequest @arguments
        Write-Debug "Jira API response status code: $( $response.StatusCode )"
        return $response
    }
    catch [System.Net.Http.HttpRequestException] {
        throw [JiraHttpRequesetException]::new($_.Exception.Message, $Uri, $_.Exception.Response)
    }
    finally {
        $ProgressPreference = "Continue"
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
    
    $response = Invoke-JiraApi `
      -Uri $uri `
      -AuthorizationHeaders $AuthorizationHeaders `
      -SkipHttpErrorCheck

    If ($response.StatusCode -eq 404) {
        return @()
    }

    # Jira will return a 400 when a issue doesn't produce any results
    If ($response.StatusCode -eq 400) {
      Write-Warning "Failed querying Jira Issues: $($response.Content | ConvertTo-Json -AsHashTable)"
      return @()
    }

    If ($response.StatusCode -ne 200) {
        throw [JiraHttpRequesetException]::new("Failed querying {$Jql}", $uri, $response)
    }
    
    $issues = $response.Content.issues

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
  
  # TODO: encrypte, verify other commands.  Perhaps use URI Builder
  $queryParamsExpanded = $queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
  $uri = New-Object -TypeName System.Uri -ArgumentList $BaseUri, `
    ("/rest/api/2/issue/{0}?{1}" -f $IssueKey, ($queryParamsExpanded -join '&'))

  $response = Invoke-JiraApi `
    -Uri $uri `
    -AuthorizationHeaders $AuthorizationHeaders `
    -SkipHttpErrorCheck

  If ($response.StatusCode -eq 404) {
      return $null
  }

  If ($response.StatusCode -ne 200) {
      throw [JiraHttpRequesetException]::new("Failed getting Jira Issue [$IssueKey]", $uri, $response)
  }

  return $response.Content
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
    
    $response = Invoke-JiraApi `
      -Uri $uri `
      -AuthorizationHeaders $AuthorizationHeaders `
      -SkipHttpErrorCheck

    If ($response.StatusCode -eq 404) {
        return @()
    }

    If ($response.StatusCode -ne 200) {
        throw [JiraHttpRequesetException]::new("Failed getting transitions for Jira Issue resulting in status code $($response.StatusCode) at uri $IssueUri", $IssueUri, $response)
    }

    # Do not flattern array if single item
    return ,@($response.Content.transitions)
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v2/api-group-issues/#api-rest-api-2-issue-issueidorkey-put
# Eventhought its API shows it can transition an issue, it doesn't work for some reason.
# Thus we use the Transition endpoint instead.
function Update-JiraTicket {
  [OutputType([bool])]
  Param (
    [hashtable]$AuthorizationHeaders = @{},
    [Uri]$IssueUri,
    [hashtable]$Fields = @{},
    [hashtable]$Updates = @{}
  )

  $runnerUrl = [string]::IsNullOrEmpty($env:GITHUB_SERVER_URL) ? "" : " with runner $env:GITHUB_RUNNER_URL"
  
  $historyMetadata = @{
    activityDescription = "GitHub Workflow Update Fields"
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
    notifyUsers = $false
    fields = $Fields
    update = $Updates
    historyMetadata = $historyMetadata
  } | ConvertTo-Json -Depth 5 -Compress

  $arguments = @{
    Body = $Body
    Method = "Put"
  }

  "Update Issue Request Body: $($Body | ConvertFrom-Json | ConvertTo-Json -Depth 5)" | Write-Debug

  $response = Invoke-JiraApi `
      -Uri $IssueUri `
      -AuthorizationHeaders $AuthorizationHeaders `
      -AdditionalArguments $arguments `
      -SkipHttpErrorCheck
  
  Write-Debug "Update Issue Response: $($response | ConvertTo-Json -Depth 5)"

  If ($response.StatusCode -eq 204) {
    return $true
  }

  If ($response.StatusCode -eq 404) {
    return $false
  }

  If ($response.StatusCode -eq 400) {
    If ($response.Content.errorMessages.Length -eq 0) {
      $response.Content.errorMessages = "Update Error. See $($env:GITHUB_ACTION_URL ?? $JIRA_HELP_URL) for help."
    }

    "Unable to update issue [$IssueUri] due to $($response.StatusDescription). See errors: $($response.Content | ConvertTo-Json -AsHashTable)" `
        | Write-Warning

    return $false
  }

  throw [JiraHttpRequesetException]::new("Failed updating Jira Issue", $IssueUri, $response)
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-transitions-post
# Can only transition if all required fields are set (this is setup within Jira)
# Can only update a field if it is on the transition screen. 
# Thus its better to update fields in a seperate call to the edit issue endpoint
function Push-JiraTicketTransition {
    [OutputType([bool])]
    Param (
        [hashtable]$AuthorizationHeaders = @{},
        [Uri]$IssueUri,
        [string]$TransitionId,
        [hashtable]$Fields = @{},
        [hashtable]$Updates = @{}
    )
    
    $runnerUrl = [string]::IsNullOrEmpty($env:GITHUB_SERVER_URL) ? "" : " with runner $env:GITHUB_RUNNER_URL"
    # TODO: move to New-JiraHistoryMetadata
    $historyMetadata = @{
      activityDescription = "GitHub Workflow Transition"
      description = "via GitHub Actions Transitioner$runnerUrl"
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

    "Transition Issue Request Body: $($Body | ConvertFrom-Json | ConvertTo-Json -Depth 5)" | Write-Debug

    $query = $IssueUri.AbsoluteUri + "/transitions"
    $uri = [System.Uri] $query

    $response = Invoke-JiraApi `
      -Uri $uri `
      -AuthorizationHeaders $AuthorizationHeaders `
      -AdditionalArguments $arguments `
      -SkipHttpErrorCheck

    If ($response.StatusCode -eq 204) {
        return $true
    }
      
    If ($response.StatusCode -eq 404) {
        return $false
    }

    If ($response.StatusCode -eq 400) {
      If ($response.Content.errorMessages.Length -eq 0) {
        $response.Content.errorMessages = "Transition Error. See $($env:GITHUB_ACTION_URL ?? $JIRA_HELP_URL) for help."
      }
      
      "Unable to transition issue [$IssueUri] due to $($response.StatusDescription). See errors: $($response.Content | ConvertTo-Json -AsHashTable)" `
        | Write-Warning
      
      # TODO: lookup if error is specific to a field name, if so, get that field name
      # pass n ithe entire issue instead of just the URI
      # if possible, also output what is being asked for so it can be sent to the notifications.  Output this so it can be included on teams notification.

      return $false
    }

    throw [JiraHttpRequesetException]::new("Failed transitioning Jira Issue to transition ID [$TransitionId]", $IssueUri, $response)
}

Export-ModuleMember -Function Push-JiraTicketTransition, Get-JiraTransitionsByIssue, Get-JiraIssuesByQuery, Get-JiraIssue, Update-JiraTicket, Get-AuthorizationHeaders