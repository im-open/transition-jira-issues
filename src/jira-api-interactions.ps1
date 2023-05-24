function Invoke-JiraQuery {
    Param (
        [Uri]$Query,
        [string]$Username = "",
        [securestring]$Password
    );

    Write-Host "Querying the Jira API $($Query.AbsoluteUri)"

    $queryResult = $null

    if ($Username -ne "") {
        $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $Username, $Password
        $plainPassword = $cred.GetNetworkCredential().Password

        # Prepare the Basic Authorization header - PSCredential doesn't seem to work
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $Username, $plainPassword)))
        $headers = @{Authorization = ("Basic {0}" -f $base64AuthInfo) }
    
        # Execute the query with the auth header
        Invoke-RestMethod -Uri $Query -Headers $headers
    }
    else {
        # Execute the query
        Invoke-RestMethod -Uri $Query
    }

    return $queryResult
}

function Invoke-JiraTicketTransition {
    Param (
        [Uri]$Uri,
        [string]$Body,
        [string]$Username = "",
        [securestring]$Password
    );

    Write-Host "Posting to the Jira API $($Uri.AbsoluteUri)"
    
    $arguments = @{
      Uri = $Query
      Body = $Body
      Method = "Post"
      ContentType = "application/json"
      UseBasicParsing = $true
      SkipHttpErrorCheck = $true
      StatusCodeVariable = "statusCode"
    }

    if ($Username -ne "") {
        $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $Username, $Password
        $plainPassword = $cred.GetNetworkCredential().Password
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $Username, $plainPassword)))
        $headers = @{Authorization = ("Basic {0}" -f $base64AuthInfo) }
        $arguments.Add("Headers", $headers)
    }
    
    # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting
    Invoke-RestMethod @arguments
    
    if ($statusCode -eq 200) {
      return true
    }
    
    if ($statusCode -eq 404) {
      return false
    }
    
    throw "Jira ticket transition failed with status code [$statusCode]"
}
