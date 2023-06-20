Function Get-FieldByNameOrId {
    [OutputType([PSCustomObject])]
    Param (
        [string]$FieldIdOrName,
        [PSCustomObject[]]$Fields
    )
    
    If ([string]::IsNullOrEmpty($FieldIdOrName)) {
        Throw "FieldIdOrName is null or missing" 
    }
    
    If ($null -eq $Issue) {
        Throw "Issue is null or missing" 
    }

    $field = $Fields | Where-Object { $_.id, $_.name -icontains $FieldIdOrName }
    If ($fieldId.Count -gt 1) { return $null }
    return $field
}

Function Invoke-HandleBadRequest {
    Param (
        [hashtable]$content,
        [PSCustomObject]$Issue
    )
    
    If ($content.errorMessages.Count -eq 0) {
        $content.errorMessages = "Error on Transition. See $( $env:GITHUB_ACTION_URL ) for help."
    }
  
    $fieldIdToName = @{}
    ForEach ($fieldId in $content.errors.Keys) {
      $fieldName = (Get-FieldByNameOrId -FieldIdOrName $fieldId -Fields $Issue.fields).name
      If ($null -ne $fieldName -And $fieldName -ine $fieldId -And $content.errors[$fieldId] -inotlike "*$( $fieldName )*") {
          $fieldIdToName.Add($fieldId, $fieldName)
      }
    }
  
    If ($fieldIdToName.Count -gt 0) {
        $content.Add("names", $fieldIdToName)
    }
    
    $baseUri = ([System.Uri]$Issue.self).GetLeftPart([System.UriPartial]::Authority)
       
    "Unable to transition issue [$baseUri/browse/$($Issue.Key)] due to $($response.StatusDescription). See errors: $( `
      $content | ConvertTo-Json -Depth 10)" | Write-Warning
}

Function Get-AuthorizationHeaders {
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

Function Invoke-JiraApi {
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

# https://developer.atlassian.com/cloud/jira/platform/rest/v2/api-group-issue-search/#api-rest-api-2-search-get
Function Get-JiraIssuesByQuery {
    [OutputType([PSCustomObject[]])]
    Param (
        [hashtable]$AuthorizationHeaders,
        [Uri]$BaseUri,
        [string]$Jql,
        [int]$MaxResults = 20,
        [switch]$IncludeDetails = $true
    )

    If ([string]::IsNullOrEmpty($Jql)) {
      throw "Jql is null or missing" 
    }

    $queryParams = @{
        maxResults = $MaxResults
        fields = [System.Web.HttpUtility]::UrlEncode("-comment,-timetracking,-worklog,-project,-watches")
        expand = $IncludeDetails ? [System.Web.HttpUtility]::UrlEncode("transitions,editmeta,names") : ""
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
        Write-Warning "Failed querying Jira Issues: $( `
          $response.Content | ConvertFrom-Json -AsHashTable | ConvertTo-Json -Depth 10)"
        return @()
    }

    If ($response.StatusCode -ne 200) {
        throw [JiraHttpRequesetException]::new("Failed querying {$Jql}", $uri, $response)
    }
    
    $content = $response.Content | ConvertFrom-Json -Depth 10
    $issues = $content.issues
    $names = $content.names

    If($null -eq $issues) {
      return @()
    }
    
    $resolvedIssues = @()
    ForEach ($issue in $issues) {
      
      $fields = $issue.fields.PSObject.Properties | ForEach-Object {
          $fieldId = $_.Name
          
          [PSCustomObject]@{
            id = $fieldId
            name = $names.$fieldId
            isEditable = $null -ne $issue.editmeta.fields.$fieldId 
            operations = $issue.editmeta.fields.$fieldId.operations ?? @()
            schemaType = $issue.editmeta.fields.$fieldId.schema.type
          }
      }
      
      $transitions = $issue.transitions | ForEach-Object {
          [PSCustomObject]@{
            id = $_.id
            name = $_.name
            toName = $_.to.name
          }
      }

      $resolvedIssues += [PSCustomObject]@{
        key = $issue.key
        self = $issue.self
        type = $issue.fields.issuetype.name
        status = $issue.fields.status.name 
        summary = $issue.fields.summary
        labels = $issue.fields.labels
        componentNames = ($issue.fields.components | Select-Object -ExpandProperty name)
        fields = $fields
        fieldValues = $issue.fields
        transitions = $transitions
      }
    }
    
    # Do not flattern array if single item
    return ,@($resolvedIssues)
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v2/api-group-issues/#api-rest-api-2-issue-issueidorkey-get
Function Get-JiraIssue {
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
    fields = $IncludeDetails ? [System.Web.HttpUtility]::UrlEncode("*all") : ""
    expand = $IncludeDetails ? [System.Web.HttpUtility]::UrlEncode("renderedFields,transitions,editmeta,names") : ""
  }
  
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

  return $response.Content | ConvertFrom-Json
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v2/api-group-issues/#api-rest-api-2-issue-issueidorkey-put
# Eventhough its API shows it can transition an issue, it doesn't work for some reason.
# Thus we use the Transition endpoint instead for that use case.
Function Edit-JiraIssue {
  [OutputType([bool])]
  Param (
    [hashtable]$AuthorizationHeaders = @{},
    [PSCustomObject]$Issue,
    [hashtable]$Fields = @{},
    [hashtable]$Updates = @{}
  )

  $issueKey = $Issue.key
  $issueUri = $Issue.self

  If ([string]::IsNullOrEmpty($issueUri)) {
    throw "[$issueKey] Issue Uri is null or missing"
  }

  $body = @{
    notifyUsers = $false
    fields = $Fields
    update = $Updates
    historyMetadata = (New-JiraHistoryMetadata -ActionType "Update Fields")
  }
  "[$issueKey] Edit Issue Request Body: $($Body | ConvertTo-Json  -Depth 10)" | Write-Debug

  $arguments = @{
    Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
    Method = "Put"
  }

  $response = Invoke-JiraApi `
      -Uri $issueUri `
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
      $content = ($response.Content | ConvertFrom-Json -AsHashTable)
      Invoke-HandleBadRequest -Issue $Issue -Content $content
      return $false
  }

  throw [JiraHttpRequesetException]::new("Failed editing Jira Issue [$issueKey]", $IssueUri, $response)
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v2/api-group-issues/#api-rest-api-2-issue-issueidorkey-transitions-get
Function Get-JiraIssueTransitionAvailableFields {
  [OutputType([PSCustomObject])]
  Param (
      [hashtable]$AuthorizationHeaders = @{},
      [PSCustomObject]$Issue,
      [string]$TransitionId
  )

  $issueKey = $Issue.key
  $issueUri = $Issue.self

  If ([string]::IsNullOrEmpty($issueUri)) {
      throw "[$issueKey] Issue Uri is null or missing"
  }

  If ([string]::IsNullOrEmpty($TransitionId)) {
      throw "Transation ID is null or missing"
  }

  $queryParams = @{
    transitionId = $TransitionId
    expand = [System.Web.HttpUtility]::UrlEncode("transitions.fields")
  }
  $queryParamsExpanded = $queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }

  $response = Invoke-JiraApi `
    -Uri ("$issueUri/transitions?{0}" -f ($queryParamsExpanded -join '&')) `
    -AuthorizationHeaders $AuthorizationHeaders `
    -SkipHttpErrorCheck

  If ($response.StatusCode -eq 404) {
      return $null
  }

  If ($response.StatusCode -ne 200) {
    throw [JiraHttpRequesetException]::new("Failed getting Jira Issue Transition [$issueKey/$TransitionId]", $uri, $response)
  }

  $transitions = ($response.Content | ConvertFrom-Json).transitions
  If($null -eq $transitions) {
      return @()
  } 
  
  If ($transitions.Length -ne 1) {
      throw "Expected 1 transition, but found $($transitions.Count) transitions from ID [$TransitionId]"
  }
  
  $fields = $transitions.fields.PSObject.Properties | ForEach-Object {
      [PSCustomObject]@{
        id = $_.Name
        name = $_.Value.name
        operations = $_.Value.operations ?? @()
        schemaType = $_.Value.schema.type
      }
  }
  
  return ,@($fields)
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v2/api-group-issues/#api-rest-api-2-issue-issueidorkey-transitions-get
# Can only transition if all required fields are set (this is setup within Jira)
# Can only update a field if it is on the transition screen. 
# Thus its better to update fields in a seperate call to the edit issue endpoint
Function Push-JiraIssueTransition {
    [OutputType([bool])]
    Param (
        [hashtable]$AuthorizationHeaders = @{},
        [PSCustomObject]$Issue,
        [string]$TransitionId,
        [hashtable]$Fields = @{},
        [hashtable]$Updates = @{},
        [string]$Comment = $null 
    )
    
    $issueKey = $Issue.key
    $issueUri = $Issue.self

    If ([string]::IsNullOrEmpty($issueUri)) {
        throw "[$issueKey] Issue Uri is null or missing"
    }
    
    $body = @{
      transition = @{
        id = $TransitionId
      }
      fields = $Fields
      update = $Updates + (New-Comment $Comment)
      historyMetadata = New-JiraHistoryMetadata -ActionType "Transition" -Purpose "Transitioner"
    }
    "[$issueKey] Transition Issue Request Body: $($Body | ConvertTo-Json  -Depth 10)" | Write-Debug

    $arguments = @{
      Body = ($Body | ConvertTo-Json  -Depth 20 -Compress)
      Method = "Post"
    }
    
    $response = Invoke-JiraApi `
      -Uri "$issueUri/transitions" `
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
        $content = ($response.Content | ConvertFrom-Json -AsHashTable)
        Invoke-HandleBadRequest -Issue $Issue -Content $content
        return $false
    }

    throw [JiraHttpRequesetException]::new("Failed transitioning Jira Issue [$issueKey] to transition ID [$TransitionId]", $issueUri, $response)
}

Function New-JiraHistoryMetadata {
  [OutputType([PSCustomObject])]
  Param (
      [string]$ActionType,
      [string]$Purpose
  )

  $runnerUrl = [string]::IsNullOrEmpty($env:GITHUB_SERVER_URL) ? "" : "- runner $env:GITHUB_RUNNER_URL"
  return @{
    activityDescription = "GitHub Action $ActionType"
    description = (@("GitHub Action", $Purpose, $runnerUrl) | Where-Object { [string]::IsNullOrEmpty($_) -eq $false }) -join " "
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
}

Function New-Comment {
  Param (
    [string]$Comment
  )

  If ([string]::IsNullOrEmpty($Comment)) {
      return @{}
  }

  return @{
    comment = @(
    @{
      add = @{
        body = $Comment
      }
    }
    )
  }
}

class JiraHttpRequesetException : System.Net.Http.HttpRequestException {
  [Uri] $Uri
  [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject] $Response

  JiraHttpRequesetException([string]$message, [Uri]$Uri, [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject]$response) : `
    base("$message - status code [$($response.StatusCode)] using Uri $($Uri)") {
      $this.Uri = $Uri
      $this.Response = $response
  }

  [string] MessageWithResponse() {
      return "{0}: {1}" -f $this.Message, $this.Response.Content
  }

  [string] ToString() {
      return $this.MessageWithResponse()
  }
}

Export-ModuleMember -Function Push-JiraIssueTransition, Get-JiraIssueTransitionAvailableFields, Get-JiraIssuesByQuery, Get-JiraIssue, Edit-JiraIssue, Get-AuthorizationHeaders, Get-FieldByNameOrId