function Get-AuthorizationHeaders {
    [OutputType([hashtable])]
    Param (
        [string]$Username,
        [securestring]$Password
    );

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
        [bool]$FailIfNotSuccessfulStatusCode = $true,
        [bool]$FailOnRequestFailure = $true
    );

    Write-Host "Invoking the Jira API at $($Uri.AbsoluteUri)"

    $arguments = @{
      SkipHttpErrorCheck = $true
      ContentType = "application/json"
      Uri = $Uri
      Headers = $AuthorizationHeaders
    } + $AdditionalArguments

    "Web Request arguments: $($arguments | ConvertTo-Json)" | Write-Debug

    $ProgressPreference = "SilentlyContinue"
    try {
      # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting
      $result = Invoke-WebRequest @arguments

      If ($FailIfNotSuccessfulStatusCode -And ($result.StatusCode -lt 200 -Or $result.StatusCode -gt 299)) {
          throw [System.Net.Http.HttpRequestException] "Failed getting Jira Issues with status code $($result.StatusCode) [$($result.StatusDescription)] and response $($result | ConvertTo-Json)"
      }

      return [PSCustomObject]@{
        StatusCode = $result.StatusCode
        StatusDescription = $result.StatusDescription
        Content = $result.Content | ConvertFrom-Json
      }
    } 
    catch {
      if($_.Exception -is [System.Net.Http.HttpRequestException] -And !$FailOnRequestFailure) {
          Write-Warning "Jira is inaccessible: $($_.Exception.Message)"
          return $null 
      }
      Else {
          throw $_.Exception
      }
    }
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-search/#api-rest-api-3-search-get
function Get-JiraIssuesByQuery {
    [OutputType([PSCustomObject[]])]
    Param (
        [hashtable]$AuthorizationHeaders,
        [Uri]$BaseUri,
        [string]$Jql,
        [bool]$FailIfJiraInaccessible = $true
    );

    If ([string]::IsNullOrEmpty($Jql)) {
      throw "Jql is null or missing" 
    }

    $queryParams = @{
        maxResults = 20 
        jql = [System.Web.HttpUtility]::UrlEncode($Jql)
    }
    $queryParamsExpanded = $queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    $uri = New-Object -TypeName System.Uri -ArgumentList $BaseUri, ("/rest/api/2/search?$($queryParamsExpanded -join '&')")

    $result = Invoke-JiraApi -Uri $uri -AuthorizationHeaders $AuthorizationHeaders -FailOnRequestFailure $FailIfJiraInaccessible

    If ($null -eq $result) {
        return @()
    }

    $issues = $result.Content.issues

    # Do not flattern array if single item
    return ,@($issues)
}

function Get-JiraIssue {
  [OutputType([PSCustomObject])]
  Param (
      [hashtable]$AuthorizationHeaders,
      [Uri]$BaseUri,
      [string]$IssueKey,
      [bool]$FailIfJiraInaccessible = $true
  );

  If ([string]::IsNullOrEmpty($IssueKey)) {
    throw "Issue Key is null or missing" 
  }

  $uri = New-Object -TypeName System.Uri -ArgumentList $BaseUri, "/rest/api/2/issue/$IssueKey"

  $result = Invoke-JiraApi `
    -Uri $uri `
    -AuthorizationHeaders $AuthorizationHeaders `
    -FailOnRequestFailure $FailIfJiraInaccessible `
    -FailIfNotSuccessfulStatusCode $false

  If ($null -eq $result -Or $result.StatusCode -eq 404) {
      return $null
  }

  If ($result.StatusCode -ne 200) {
      throw [System.Net.Http.HttpRequestException] "Failed getting Jira Issue with status code [$($result.StatusCode)] and response $($result | ConvertTo-Json)"
  }

  return $result.Content
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-transitions-get
function Get-JiraTransitionsByIssue {
    [OutputType([PSCustomObject[]])]
    Param (
        [hashtable]$AuthorizationHeaders,
        [Uri]$IssueUri,
        [string]$IncludeDetails = $true
    );

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

    If ($null -eq $result -Or $result.StatusCode -eq 404) {
        return @()
    }

    If ($result.StatusCode -ne 200) {
        throw [System.Net.Http.HttpRequestException] "Failed getting Jira Issue's transitions with status code [$($result.StatusCode)] and response $($result | ConvertTo-Json)"
    }

    # Do not flattern array if single item
    return ,@($result.Content.transitions)
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-transitions-post
function Push-JiraTicketTransition {
    [OutputType([boolean])]
    Param (
        [hashtable]$AuthorizationHeaders = @{},
        [Uri]$IssueUri,
        [string]$TransitionId,
        [hashtable]$Fields = @{},
        [hashtable]$Updates = @{},
        [bool]$FailIfJiraInaccessible = $false
    );

    $urlToRun = "https://$Env:GITHUB_SERVER_URL/$Env:GITHUB_REPOSITORY/actions/runs/$Env:GITHUB_RUN_ID"
    $historyMetadata = @{
        activityDescription = "GitHub Transition"
        description = "Status automatically updated via GitHub Actions. Link to the run: $urlToRun."
    }

    # "historyMetadata": {
    #   "activityDescription": "Complete order processing",
    #   "actor": {
    #     "avatarUrl": "http://mysystem/avatar/tony.jpg",
    #     "displayName": "Tony",
    #     "id": "tony",
    #     "type": "mysystem-user",
    #     "url": "http://mysystem/users/tony"
    #   },
    #   "cause": {
    #     "id": "myevent",
    #     "type": "mysystem-event"
    #   },
    #   "description": "From the order testing process",
    #   "extraData": {
    #     "Iteration": "10a",
    #     "Step": "4"
    #   },
    #   "generator": {
    #     "id": "mysystem-1",
    #     "type": "mysystem-application"
    #   },
    #   "type": "myplugin:type"
    # },
    # "properties": [
    #   {
    #     "key": "key1",
    #     "value": "Order number 10784"
    #   },
    #   {
    #     "key": "key2",
    #     "value": "Order number 10923"
    #   }
    # ],

    $body = @{
      transition = @{
          id = $TransitionId
      }
      fields = $Fields
      update = $Updates
      historyMetadata = $historyMetadata
    } | ConvertTo-Json -Compress

    $arguments = @{
      Body = $Body
      Method = "Post"
    }

    Write-Debug "Transition body: $($Body | ConvertTo-Json)"

    $query = $IssueUri.AbsoluteUri + "/transitions"
    $uri = [System.Uri] $query

    $result = Invoke-JiraApi `
      -Uri $uri `
      -AuthorizationHeaders $AuthorizationHeaders `
      -AdditionalArguments $arguments `
      -FailOnRequestFailure $FailIfJiraInaccessible `
      -FailIfNotSuccessfulStatusCode $false

    If ($null -eq $result) {
        return $false
    }

    If ($result.StatusCode -eq 204) {
        return $true
    }
      
    If ($result.StatusCode -eq 404) {
        return $false
    }

    If ($result.StatusCode -eq 400) {
      Write-Warning "Unable to transition due to $($result.StatusDescription). See errors: $($result.Content | ConvertTo-Json)"
      # TODO: Write to github notice
      return $false
    }
    
    throw [System.Net.Http.HttpRequestException] "Failed transitioning issue with status code [$($result.StatusCode)] and response $($result | ConvertTo-Json)"
}

Export-ModuleMember -Function Push-JiraTicketTransition, Get-JiraTransitionsByIssue, Get-JiraIssuesByQuery, Get-JiraIssue, Invoke-JiraApi, Get-AuthorizationHeaders