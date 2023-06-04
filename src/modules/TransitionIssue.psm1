using module "./JiraApis.psm1"

Enum TransitionResultType {
  Unknown
  Unavailable
  Success
  Failed
  Skipped
}

Function Get-ReducedFields {
    [OutputType([hashtable])]
    Param (
      [PSCustomObject]$Issue,
      [hashtable]$Fields = @{},
      [hashtable]$FieldIdLookup = @{}
    )

    $issueKey = $Issue.key
    $issueType = $Issue.fields.issuetype.name
    $reducedFields = @{}
    If ($Fields.Count -eq 0) {
        return $reducedFields
    }

    ForEach ($field in $Fields.GetEnumerator()) {
        $fieldId = $FieldIdLookup[$field.Key]
        If ($null -eq $fieldId) { continue }
        $reducedFields[$fieldId] = $field.Value

        if ($fieldId -ne $field.Key) {
          Write-Debug "[$issueKey] Field {$($field.Key)} translated to field ID {$fieldId}"
        }
    }
    
    If ($reducedFields.Count -eq 0) {
        "[$issueKey] No valid fields were identified for $issueType. No field changes will be applied." `
          | Write-Debug
        return $reducedFields
    }

    $unavailableFields = $Fields.Keys | Where-Object { !$FieldIdLookup.ContainsKey($_) }
    If ($unavailableFields.Count -gt 0) {
        "[$issueKey] Fields were omitted because they are not valid for the issue: $($unavailableFields -join ', ')" `
          | Write-Debug
    }
    
    return $reducedFields
}

Function Get-ReducedUpdates {
    [OutputType([hashtable])]
    Param (
        [PSCustomObject]$Issue,
        [hashtable]$Updates = @{},
        [hashtable]$FieldIdLookup = @{}
    )

    $issueKey = $Issue.key
    $issueType = $Issue.fields.issuetype.name
    $reducedUpdates = @{}
    If ($Updates.Count -eq 0) {
        return $reducedUpdates
    }
    
    $unavailableUpdates = @{}

    ForEach ($update in $Updates.GetEnumerator()) {
        $fieldId = $FieldIdLookup[$update.Key]
        If ($null -eq $fieldId) {
            $unavailableUpdates["$($update.Key)"] = @()
            Continue 
        }

        if ($fieldId -ne $update.Key) {
          Write-Debug "[$issueKey] Field {$($update.Key)} translated to field ID {$fieldId}"
        }

        $field = $Issue.editmeta.fields.$fieldId
        If ($null -eq $field) {
            $unavailableUpdates["$($update.Key)"] = @()
            Continue
        }
        $operationNames = $field.operations
        
        If ($operationNames -icontains "set" -And $field.schema.type -eq "string") {
            $operationNames += "append"
        }
        
        Write-Debug "[$issueKey] Valid operations for field [$fieldId]: $($operationNames -join ', ')"

        $operations = @()
        ForEach ($operation in $update.Value) {
            If ($operation.Keys.Count -ne 1) {
              Write-Warning "[$issueKey] Update operation is invalid. Can only contain one key: $($_.Keys -join ', ')"
              Continue
            }

            # Only one key is expected
            $operationName = $operation.Keys[0]
            If ($null -eq $operationName -Or $operationNames -cnotcontains $operationName) {
                $unavailableUpdates["$($update.Key)"] = $unavailableUpdates["$($update.Key)"] + $operationName
                Continue
            }
            
            # Allow those fields that only have a set and are a string value, to append
            If ($operationName -ieq "append") {
                $existingValue = $Issue.fields.$fieldId
                $appendValue = $operation[$operationName]
                If ([string]::IsNullOrEmpty($appendValue)) { Continue }
                
                $maybeLineBreak = [string]::IsNullOrEmpty($appendValue) ? "" : "`n"
                $operations += @{
                    "set" = $existingValue + $maybeLineBreak + $appendValue 
                }
                Continue
            }
            $operations += $operation 
        }
        
        if ($operations.Count -eq 0) { Continue }
        $reducedUpdates[$fieldId] = $operations
    }

    If ($reducedUpdates.Count -eq 0) {
        "[$issueKey] No valid update operations were identified for $issueType. No operations will be applied." `
          | Write-Debug
        return $reducedUpdates
    }
  
    If ($unavailableUpdates.Count -gt 0) {
        "[$issueKey] Update operations were omitted because they are not valid for the issue: $($unavailableUpdates | ConvertTo-Json)" `
          | Write-Debug
    }
    
    return $reducedUpdates
}

# https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/#api-rest-api-3-issue-issueidorkey-transitions-post
Function Invoke-JiraTransitionTicket {
    [OutputType([TransitionResultType])]
    Param (
        [hashtable]$AuthorizationHeaders,
        [PSCustomObject]$Issue,
        [string]$TransitionName,
        [hashtable]$Fields = @{},
        [hashtable]$Updates = @{},
        [string]$Comment = ""
    )

    If ([string]::IsNullOrEmpty($TransitionName)) {
        throw "[$issueKey] Transition name is null or missing" 
    }
    
    $issueKey = $Issue.key
    $issueStatus = $Issue.fields.status.name

    If ([string]::IsNullOrEmpty($issueKey)) {
        throw "[$issueKey] Issue Key is null or missing"
    }

    If ([string]::IsNullOrEmpty($issueStatus)) {
        throw "[$issueKey] Issue Status is null or missing"
    }

    $issueType = $Issue.fields.issuetype.name
    $issueSummary = $Issue.fields.summary
    $issueLabels = $Issue.fields.labels
    $issueComponents = $Issue.fields.components
    
    Write-Debug "[$issueKey] $issueType : $issueSummary -> processing with labels [$( `
      $issueLabels -join ', ')] and components [$(@($issueComponents | Select-Object -ExpandProperty name) -join ', ')]"

    $resultType = [TransitionResultType]::Unknown
    try {
        $fieldIdLookup = @{}
        ForEach ($field in $Issue.editmeta.fields.PSObject.Properties) {
            $id = $field.Value.fieldId
            $fieldIdLookup[$id] = $id
            $fieldIdLookup[$field.Value.name] = $id
        }

        $edited = Edit-JiraTicket `
          -AuthorizationHeaders $AuthorizationHeaders `
          -Issue $Issue `
          -Fields (Get-ReducedFields -Fields $Fields -Issue $Issue -FieldIdLookup $fieldIdLookup) `
          -Updates (Get-ReducedUpdates -Updates $Updates -Issue $Issue -FieldIdLookup $fieldIdLookup)

        If (!$edited) {
            "[$issueKey] Unable to edit fields for $issueType. Skipping transition!" `
              | Write-Warning

            return [TransitionResultType]::Failed
        }
      
        $transitionIdLookup = @{}
        ForEach ($transition in $Issue.transitions) {
            $transitionIdLookup[$transition.name] = $transition.id
            # Include status names with possible transitions
            $transitionIdLookup[$transition.to.name] = $transition.id
        }
        $transitionToNames = $Issue.transitions | Select-Object -ExpandProperty to | Select-Object -ExpandProperty name
        
        If ($issueStatus -ieq $TransitionName) {
            "[$issueKey] $issueType already in status [$issueStatus]. Skipping transition! Available transitions: $($transitionToNames -join ', ')" `
              | Write-Information
    
            return [TransitionResultType]::Skipped 
        }
    
        $transitionId = $transitionIdLookup[$TransitionName]
        If ($null -eq $transitionId) {
            "[$issueKey] Missing transition [$TransitionName] on $issueType! Currently in [$issueStatus] state. Available transitions: $($transitionToNames -join ', ')" `
              | Write-Information 
    
            return [TransitionResultType]::Unavailable
        }
        
        Write-Debug "[$issueKey] Transitioning $issueType from [$issueStatus] to [$TransitionName]..."
    
        $processed = Push-JiraTicketTransition `
          -AuthorizationHeaders $AuthorizationHeaders `
          -Issue $Issue `
          -TransitionId $transitionId `
          -Comment $Comment
  
        $resultType = $processed ? [TransitionResultType]::Success : [TransitionResultType]::Failed
    }
    catch [JiraInaccessibleException] {
        $resultType = [TransitionResultType]::Failed
        if ($safeFailIfJiraInaccessible) { throw }
        
        $resultType = [TransitionResultType]::Skipped
        Write-Warning "[$($issue.key)] Unable to continue transitioning. Skipping!"
        Write-Warning $_.Exception.MessageWithResponse()
        Write-Debug $_.ScriptStackTrace
    }
    
    return $resultType
}

Export-ModuleMember -Function Invoke-JiraTransitionTicket