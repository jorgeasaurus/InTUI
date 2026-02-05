function Export-InTUIData {
    <#
    .SYNOPSIS
        Non-interactive export of Intune data for scripting and automation.
    .DESCRIPTION
        Pipe-friendly command that exports Intune data in JSON or CSV format
        without launching the interactive TUI. Useful for scripting, diff/version
        control, and automation pipelines.
    .PARAMETER Type
        The data type to export: Devices, Apps, Users, Groups, ConfigProfiles, CompliancePolicies.
    .PARAMETER Format
        Output format: JSON, CSV, or PSObject (for pipeline use).
    .PARAMETER OutputPath
        Optional file path to write output. If omitted, writes to stdout.
    .PARAMETER Filter
        Optional OData filter expression.
    .PARAMETER Select
        Optional comma-separated list of properties to select.
    .EXAMPLE
        Export-InTUIData -Type Devices -Format JSON -OutputPath ./devices.json
    .EXAMPLE
        Export-InTUIData -Type Users -Format CSV | Out-File users.csv
    .EXAMPLE
        Export-InTUIData -Type ConfigProfiles -Format PSObject | Where-Object { $_.displayName -match 'VPN' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Devices', 'Apps', 'Users', 'Groups', 'ConfigProfiles', 'CompliancePolicies')]
        [string]$Type,

        [Parameter()]
        [ValidateSet('JSON', 'CSV', 'PSObject')]
        [string]$Format = 'JSON',

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Select
    )

    if (-not $script:Connected) {
        Write-Error "Not connected to Microsoft Graph. Run Connect-InTUI first."
        return
    }

    $uriMap = @{
        Devices            = @{ Uri = '/deviceManagement/managedDevices'; Beta = $true; DefaultSelect = 'id,deviceName,operatingSystem,osVersion,complianceState,userPrincipalName,lastSyncDateTime,serialNumber,manufacturer,model' }
        Apps               = @{ Uri = '/deviceAppManagement/mobileApps'; Beta = $true; DefaultSelect = 'id,displayName,publisher,createdDateTime,lastModifiedDateTime' }
        Users              = @{ Uri = '/users'; Beta = $false; DefaultSelect = 'id,displayName,userPrincipalName,mail,jobTitle,department,accountEnabled' }
        Groups             = @{ Uri = '/groups'; Beta = $false; DefaultSelect = 'id,displayName,description,groupTypes,mailEnabled,securityEnabled' }
        ConfigProfiles     = @{ Uri = '/deviceManagement/deviceConfigurations'; Beta = $true; DefaultSelect = 'id,displayName,description,lastModifiedDateTime,createdDateTime,version' }
        CompliancePolicies = @{ Uri = '/deviceManagement/deviceCompliancePolicies'; Beta = $true; DefaultSelect = 'id,displayName,description,lastModifiedDateTime,createdDateTime,version' }
    }

    $config = $uriMap[$Type]
    $selectFields = if ($Select) { $Select } else { $config.DefaultSelect }

    $params = @{
        Uri  = $config.Uri
        Beta = $config.Beta
    }

    if ($selectFields) { $params['Select'] = $selectFields }
    if ($Filter) { $params['Filter'] = $Filter }

    Write-InTUILog -Message "Non-interactive export" -Context @{ Type = $Type; Format = $Format; Filter = $Filter }

    $allResults = @()
    $response = Get-InTUIPagedResults @params -PageSize 999

    if ($null -eq $response -or $response.Results.Count -eq 0) {
        Write-Warning "No data found for type '$Type'."
        return
    }

    $allResults = $response.Results

    switch ($Format) {
        'PSObject' {
            if ($OutputPath) {
                $allResults | Export-Clixml -Path $OutputPath
            }
            else {
                return $allResults
            }
        }
        'JSON' {
            $json = $allResults | ConvertTo-Json -Depth 10
            if ($OutputPath) {
                $json | Set-Content -Path $OutputPath -Encoding UTF8
            }
            else {
                return $json
            }
        }
        'CSV' {
            if ($OutputPath) {
                $allResults | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            }
            else {
                return ($allResults | ConvertTo-Csv -NoTypeInformation)
            }
        }
    }

    if ($OutputPath) {
        Write-InTUILog -Message "Export completed" -Context @{ Type = $Type; Format = $Format; Path = $OutputPath; Count = $allResults.Count }
        Write-Host "Exported $($allResults.Count) $Type to $OutputPath"
    }
}
