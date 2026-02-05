#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Launches InTUI - The Intune Terminal User Interface.

.DESCRIPTION
    InTUI is a Spectre Console based terminal UI for managing Microsoft Intune
    resources via Microsoft Graph API. It provides an interactive interface for
    managing Devices, Apps, Users, and Groups.

    Prerequisites:
    - PowerShell 7.2+
    - Microsoft.Graph.Authentication module
    - PwshSpectreConsole module

.PARAMETER TenantId
    Optional tenant ID or domain to connect to.

.PARAMETER Install
    Install required PowerShell modules.

.EXAMPLE
    ./Start-InTUI.ps1

.EXAMPLE
    ./Start-InTUI.ps1 -TenantId "contoso.onmicrosoft.com"

.EXAMPLE
    ./Start-InTUI.ps1 -Install
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
    [string]$Environment = 'Global',

    [Parameter()]
    [switch]$Install
)

$ErrorActionPreference = 'Stop'

$requiredModules = @('Microsoft.Graph.Authentication', 'PwshSpectreConsole')

if ($Install) {
    Write-Host "Installing required modules..." -ForegroundColor Cyan

    foreach ($mod in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Write-Host "  Installing $mod..." -ForegroundColor Yellow
            Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber
            Write-Host "  $mod installed." -ForegroundColor Green
        }
        else {
            Write-Host "  $mod already installed." -ForegroundColor Green
        }
    }

    Write-Host "`nAll dependencies installed. Run ./Start-InTUI.ps1 to launch." -ForegroundColor Green
    return
}

$missingModules = @($requiredModules | Where-Object { -not (Get-Module -ListAvailable -Name $_) })

if ($missingModules.Count -gt 0) {
    Write-Host "`nMissing required modules:" -ForegroundColor Red
    foreach ($mod in $missingModules) {
        Write-Host "  - $mod" -ForegroundColor Yellow
    }
    Write-Host "`nRun './Start-InTUI.ps1 -Install' to install dependencies.`n" -ForegroundColor Cyan
    return
}

$modulePath = Join-Path $PSScriptRoot 'InTUI.psd1'
Import-Module $modulePath -Force

$params = @{ Environment = $Environment }
if ($TenantId) { $params['TenantId'] = $TenantId }

Start-InTUI @params
