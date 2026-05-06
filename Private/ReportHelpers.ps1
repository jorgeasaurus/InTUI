function ConvertFrom-InTUIReportResponse {
    <#
    .SYNOPSIS
        Converts Intune report responses into keyed row objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Response,

        [Parameter(Mandatory)]
        [string[]]$DefaultFields
    )

    if ($null -eq $Response -or $Response -eq $true) {
        return @()
    }

    if ($Response -is [string]) {
        $Response = $Response | ConvertFrom-Json -ErrorAction Stop
    }

    $rowValue = $null
    foreach ($propertyName in 'rows', 'Values', 'value') {
        $property = $Response.PSObject.Properties |
            Where-Object { $_.Name -eq $propertyName } |
            Select-Object -First 1

        if ($property -and $null -ne $property.Value) {
            $rowValue = $property.Value
            break
        }
    }

    if ($null -eq $rowValue) {
        return @()
    }

    $reportRows = @($rowValue)

    if ($reportRows.Count -eq 0) {
        return @()
    }

    $fields = if ($Response.Schema) {
        @($Response.Schema | ForEach-Object {
                if ($_ -is [string]) {
                    $_
                }
                elseif ($_.Column) {
                    $_.Column
                }
                elseif ($_.Name) {
                    $_.Name
                }
                elseif ($_.PropertyName) {
                    $_.PropertyName
                }
            } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    else {
        @()
    }

    if ($fields.Count -eq 0) {
        $fields = $DefaultFields
    }

    $convertedRows = foreach ($row in $reportRows) {
        if ($row -is [System.Collections.IDictionary]) {
            [pscustomobject]$row
            continue
        }

        if ($row -isnot [array] -and $null -ne $row.PSObject.Properties['PolicyName']) {
            $row
            continue
        }

        $rowData = [ordered]@{}
        for ($i = 0; $i -lt $fields.Count -and $i -lt $row.Count; $i++) {
            $rowData[$fields[$i]] = $row[$i]
        }
        [pscustomobject]$rowData
    }

    return @($convertedRows)
}

function ConvertTo-InTUIReportPolicyStatus {
    <#
    .SYNOPSIS
        Converts Intune report policy status codes to display text.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Status
    )

    if ($null -eq $Status) {
        return 'N/A'
    }

    $statusText = [string]$Status
    switch ($statusText) {
        '1' { return 'NotApplicable' }
        '2' { return 'Succeeded' }
        '3' { return 'Failed' }
        '4' { return 'Conflict' }
        default {
            if ([string]::IsNullOrWhiteSpace($statusText)) {
                return 'N/A'
            }
            return $statusText
        }
    }
}
