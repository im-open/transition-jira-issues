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
        [hashtable]$FieldChanges = @{},
        [PSCustomObject[]]$AvailableFields = @()
    )
    $issueKey = $Issue.key
    $issueType = $Issue.type
    
    $reducedFields = @{}
    If ($FieldChanges.Count -eq 0) {
        return $reducedFields
    }

    $unavailableFields = @()
    ForEach ($field in $FieldChanges.GetEnumerator()) {
        $fieldId = (Get-FieldByNameOrId -FieldIdOrName $field.Key -Fields $AvailableFields).id
        If ($null -eq $fieldId) {
            $unavailableFields += $field.Key
            Continue
        }
        
        $reducedFields[$fieldId] = $field.Value

        if ($fieldId -ne $field.Key) {
            Write-Debug "[$issueKey] Field {$($field.Key)} translated to field ID {$fieldId}"
        }
    }
    
    If ($reducedFields.Count -eq 0) {
        "[$issueKey] No valid fields were identified for $issueType." `
          | Write-Debug
        return $reducedFields
    }

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
        [hashtable]$UpdateChanges = @{},
        [PSCustomObject[]]$AvailableFields = @()
    )
    $issueKey = $Issue.key
    $issueType = $Issue.type
    
    $reducedUpdates = @{}
    If ($UpdateChanges.Count -eq 0) {
        return $reducedUpdates
    }
    
    $unavailableUpdates = @{}
    ForEach ($update in $UpdateChanges.GetEnumerator()) {
        $field = (Get-FieldByNameOrId -FieldIdOrName $update.Key -Fields $AvailableFields)
        If ($null -eq $field)  {
            $unavailableUpdates["$($update.Key)"] = @()
            Continue
        }
        
        $fieldId = $field.id
        if ($fieldId -ne $update.Key) {
          Write-Debug "[$issueKey] Field {$($update.Key)} translated to field ID {$fieldId}"
        }

        $operationNames = $field.operations
        If ($operationNames -icontains "set" -And $field.schemaType -eq "string") {
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
                $existingValue = $Issue.fieldValues.$fieldId
                $appendValue = $operation[$operationName]
                If ([string]::IsNullOrEmpty($appendValue)) { Continue }
                
                $maybeLineBreak = [string]::IsNullOrEmpty($existingValue) ? "" : "`n"
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
        "[$issueKey] No valid update operations were identified for $issueType." `
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
Function Invoke-JiraTransitionIssue {
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
    $issueStatus = $Issue.status
    $issueType = $Issue.type

    If ([string]::IsNullOrEmpty($issueKey)) {
        throw "[$issueKey] Issue Key is null or missing"
    }

    If ([string]::IsNullOrEmpty($issueStatus)) {
        throw "[$issueKey] Issue Status is null or missing"
    }

    Write-Debug "[$issueKey] $issueType : $($Issue.summary) -> processing with labels [$( `
      $Issue.labels -join ', ')] and components [$($Issue.componentNames -join ', ')]"

    $resultType = [TransitionResultType]::Unknown
    try {
        $availableTransitionNames = $Issue.transitions | Select-Object -ExpandProperty toName
      
        $availableEditFields = $Issue.fields | Where-Object { $_.isEditable }
        $editFieldChanges = (Get-ReducedFields -FieldChanges $Fields -Issue $Issue -AvailableFields $availableEditFields)
        $editUpdateChanges = (Get-ReducedUpdates -UpdateChanges $Updates -Issue $Issue -AvailableFields $availableEditFields)

        If ($editFieldChanges.Count -gt 0 -Or $editUpdateChanges.Count -gt 0) {
          Write-Information "[$issueKey] Changes identified for $issueType. Performing updates prior to transition..."
            
          $edited = Edit-JiraIssue `
            -AuthorizationHeaders $AuthorizationHeaders `
            -Issue $Issue `
            -Fields $editFieldChanges `
            -Updates $editUpdateChanges 
  
          If (!$edited) {
              "[$issueKey] Unable to edit fields for $issueType. Skipping transition!" `
                | Write-Warning
  
              return [TransitionResultType]::Failed
          }
        }

        $transitionId = ($Issue.transitions | Where-Object { $_.name, $_.toName -icontains $TransitionName }).id
        If ($null -eq $transitionId) {
            "[$issueKey] Missing transition [$TransitionName] on $issueType! Currently in [$issueStatus] state. Available transitions: $($availableTransitionNames -join ', ')" `
              | Write-Information 
    
            return [TransitionResultType]::Unavailable
        }
        If ($transitionId.Count -gt 1) {
            "[$issueKey] Multiple transitions found for [$TransitionName] on $issueType! Available transitions: $($transitionId -join ', ')" `
              | Write-Warning
    
            return [TransitionResultType]::Unavailable
        }

        $currentTransitionId = ($Issue.transitions | Where-Object { $_.name, $_.toName -icontains $issueStatus }).id
        If ($currentTransitionId -eq $transitionId) {
          "[$issueKey] $issueType already in status [$issueStatus]. Skipping transition! Available transitions: $($Issue.availableTransitionNames -join ', ')" `
              | Write-Information

          return [TransitionResultType]::Skipped
        }
        
        Write-Debug "[$issueKey] Transitioning $issueType from [$issueStatus] to [$TransitionName]..."
        
        $transitionFieldChanges = @{}
        $transitionUpdateChanges = @{}
        
        # Some fields are only available for updating during a transition
        If ($editFieldChanges.Count -ne $Fields.Count -Or $editUpdateChanges.Count -ne $Updates.Count) {
            $availableTransitionFields = Get-JiraIssueTransitionAvailableFields `
              -AuthorizationHeaders $AuthorizationHeaders `
              -Issue $Issue `
              -TransitionId $transitionId
            
            "[$issueKey] Specific transition fields identified. Preparing fields to be used during transition: $(@($availableTransitionFields | Select-Object -ExpandProperty name ) -join ', ')" | Write-Debug
            
            $transitionFieldChanges = Get-ReducedFields -FieldChanges $Fields -Issue $Issue -AvailableFields ($availableTransitionFields | Where-Object { $editFieldChanges.Keys -inotcontains $_.id })
            $transitionUpdateChanges = Get-ReducedUpdates -UpdateChanges $Updates -Issue $Issue -AvailableFields ($availableTransitionFields | Where-Object { $editUpdateChanges.Keys -inotcontains $_.id })
        }

        $processed = Push-JiraIssueTransition `
          -AuthorizationHeaders $AuthorizationHeaders `
          -Issue $Issue `
          -TransitionId $transitionId `
          -Fields $transitionFieldChanges `
          -Updates $transitionUpdateChanges `
          -Comment $Comment
  
        $resultType = $processed ? [TransitionResultType]::Success : [TransitionResultType]::Failed
    }
    catch {
        If ($_.Exception.GetType().ToString() -eq "JiraHttpRequesetException") {
            $resultType = [TransitionResultType]::Failed
            if ($safeFailIfJiraInaccessible) { throw }
            
            $resultType = [TransitionResultType]::Skipped
            Write-Warning "[$($issue.key)] Unable to continue transitioning. Skipping!"
            Write-Warning $_.Exception.MessageWithResponse()
            Write-Debug $_.ScriptStackTrace
        }
        else {
          throw
        }
    }
    
    return $resultType
}

Export-ModuleMember -Function Invoke-JiraTransitionIssue