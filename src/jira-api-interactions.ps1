function Invoke-JiraQuery {
    [OutputType([boolean])]
    Param (
        [Uri]$Query,
        [string]$Username = "",
        [securestring]$Password
    );

    Write-Host "Querying the Jira API $($Query.AbsoluteUri)"
    
    $arguments = @{
      Uri = $Query
      SkipHttpErrorCheck = $true
      StatusCodeVariable = "statusCode"
    }
    
    if ($Username -ne "") {
        $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $Username, $Password
        $plainPassword = $cred.GetNetworkCredential().Password

        # Prepare the Basic Authorization header - PSCredential doesn't seem to work
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
    
    throw "Jira request failed with status code [$statusCode]"
}

function Invoke-JiraTicketTransition {
    Param (
        [Uri]$Uri,
        [string]$Body,
        [string]$Username = "",
        [securestring]$Password
    );

    Write-Host "Posting to the Jira API $($Uri.AbsoluteUri)"

    if ($Username -ne "") {
        $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $Username, $Password
        $plainPassword = $cred.GetNetworkCredential().Password
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $Username, $plainPassword)))
        $headers = @{Authorization = ("Basic {0}" -f $base64AuthInfo) }

        # Send a POST with the auth header
        Invoke-RestMethod -Uri $Uri -Headers $headers -UseBasicParsing -Body $Body -Method Post -ContentType "application/json"
    }
    else {
        # Send a POST
        Invoke-RestMethod -Uri $Uri -UseBasicParsing -Body $Body -Method Post -ContentType "application/json"
    }
}
