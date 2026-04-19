#Requires -Version 7.0

<#
.SYNOPSIS
    Build script for InTUI module.
.DESCRIPTION
    Bootstraps build dependencies and runs build tasks:
    Analyze (PSScriptAnalyzer), Test (Pester), Build (stage module),
    CI (all three), Publish (push to PSGallery).
.PARAMETER Task
    Build task(s) to run: Analyze, Test, Build, CI, Publish.
    If omitted, only bootstraps dependencies.
.PARAMETER NuGetApiKey
    PSGallery API key for the Publish task.
.EXAMPLE
    ./build.ps1
.EXAMPLE
    ./build.ps1 -Task CI
.EXAMPLE
    ./build.ps1 -Task Publish -NuGetApiKey $key
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Analyze', 'Test', 'Build', 'CI', 'Publish', 'Clean')]
    [string[]]$Task,

    [Parameter()]
    [string]$NuGetApiKey
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$ModuleName = 'InTUI'
$ProjectRoot = $PSScriptRoot
$BuildDir = Join-Path $ProjectRoot 'build'
$StageDir = Join-Path $BuildDir $ModuleName
$TestResultsDir = Join-Path $BuildDir 'TestResults'

Write-Information "=== $ModuleName Build ==="

# --- Bootstrap ---
$requiredModules = @(
    @{ Name = 'Pester'; MinimumVersion = '5.4.0' }
    @{ Name = 'PSScriptAnalyzer'; MinimumVersion = '1.21.0' }
)

foreach ($mod in $requiredModules) {
    $installed = Get-Module -Name $mod.Name -ListAvailable |
        Where-Object { $_.Version -ge [version]$mod.MinimumVersion } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $installed) {
        Write-Information "Installing $($mod.Name) >= $($mod.MinimumVersion)..."
        Install-Module -Name $mod.Name -MinimumVersion $mod.MinimumVersion -Force -Scope CurrentUser -AllowClobber
        Write-Information "  Installed $($mod.Name)"
    }
    else {
        Write-Information "Found $($mod.Name) v$($installed.Version)"
    }
}

Write-Information "Bootstrap complete."

if (-not $Task) { return }

# --- Task: Clean ---
function Invoke-Clean {
    Write-Information "`n--- Clean ---"
    if (Test-Path $BuildDir) {
        Remove-Item -Path $BuildDir -Recurse -Force
        Write-Information "Removed $BuildDir"
    }
}

# --- Task: Analyze ---
function Invoke-Analyze {
    Write-Information "`n--- PSScriptAnalyzer ---"
    Import-Module PSScriptAnalyzer -Force

    $params = @{
        Path        = $ProjectRoot
        Recurse     = $true
        ExcludeRule = @(
            'PSUseShouldProcessForStateChangingFunctions',
            'PSAvoidUsingWriteHost',
            'PSUseSingularNouns',
            'PSReviewUnusedParameter',
            'PSUseApprovedVerbs',
            'PSAvoidUsingEmptyCatchBlock',
            'PSAvoidAssignmentToAutomaticVariable',
            'PSUseDeclaredVarsMoreThanAssignments',
            'PSAvoidUsingConvertToSecureStringWithPlainText',
            'PSPossibleIncorrectComparisonWithNull',
            'PSUseBOMForUnicodeEncodedFile'
        )
        Severity    = @('Error', 'Warning')
    }

    $results = Invoke-ScriptAnalyzer @params |
        Where-Object { $_.ScriptName -notmatch '\.Tests\.ps1$' -and $_.ScriptPath -notmatch 'build[/\\]' }

    if ($results) {
        $results | Format-Table -AutoSize
        throw "PSScriptAnalyzer found $($results.Count) issue(s)."
    }

    Write-Information "PSScriptAnalyzer: No issues found."
}

# --- Task: Test ---
function Invoke-Test {
    Write-Information "`n--- Pester Tests ---"
    Import-Module Pester -Force

    if (-not (Test-Path $TestResultsDir)) {
        New-Item -Path $TestResultsDir -ItemType Directory -Force | Out-Null
    }

    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $ProjectRoot 'Tests'
    $config.Run.Exit = $false
    $config.Output.Verbosity = 'Detailed'
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = Join-Path $TestResultsDir 'TestResults.xml'
    $config.TestResult.OutputFormat = 'NUnitXml'

    $result = Invoke-Pester -Configuration $config

    if ($result.FailedCount -gt 0) {
        throw "Pester: $($result.FailedCount) test(s) failed."
    }

    Write-Information "Pester: $($result.PassedCount) passed, $($result.FailedCount) failed."
}

# --- Task: Build ---
function Invoke-Build {
    Write-Information "`n--- Build Module ---"

    # Clean previous build
    if (Test-Path $StageDir) {
        Remove-Item -Path $StageDir -Recurse -Force
    }
    New-Item -Path $StageDir -ItemType Directory -Force | Out-Null

    # Copy module files
    $filesToCopy = @(
        'InTUI.psd1'
        'InTUI.psm1'
    )
    foreach ($file in $filesToCopy) {
        Copy-Item -Path (Join-Path $ProjectRoot $file) -Destination $StageDir
    }

    # Copy directories
    $dirsToCopy = @('Private', 'Public', 'Views')
    foreach ($dir in $dirsToCopy) {
        $src = Join-Path $ProjectRoot $dir
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination $StageDir -Recurse
        }
    }

    # Verify manifest
    $manifest = Test-ModuleManifest -Path (Join-Path $StageDir 'InTUI.psd1')
    Write-Information "Built $($manifest.Name) v$($manifest.Version)"
    Write-Information "Output: $StageDir"

    # List contents
    $fileCount = (Get-ChildItem -Path $StageDir -Recurse -File).Count
    Write-Information "Files staged: $fileCount"
}

# --- Task: Publish ---
function Invoke-Publish {
    Write-Information "`n--- Publish to PSGallery ---"

    if (-not (Test-Path $StageDir)) {
        throw "Build directory not found. Run Build task first."
    }

    $apiKey = if ($NuGetApiKey) { $NuGetApiKey } else { $env:PSGALLERY_API_KEY }
    if (-not $apiKey) {
        throw "No API key. Pass -NuGetApiKey or set PSGALLERY_API_KEY env var."
    }

    Publish-Module -Path $StageDir -NuGetApiKey $apiKey -Repository PSGallery -Force
    $manifest = Import-PowerShellDataFile -Path (Join-Path $StageDir 'InTUI.psd1')
    Write-Information "Published $ModuleName v$($manifest.ModuleVersion) to PSGallery."
}

# --- Run Tasks ---
foreach ($t in $Task) {
    switch ($t) {
        'Clean'   { Invoke-Clean }
        'Analyze' { Invoke-Analyze }
        'Test'    { Invoke-Test }
        'Build'   { Invoke-Build }
        'Publish' { Invoke-Build; Invoke-Publish }
        'CI'      { Invoke-Analyze; Invoke-Test; Invoke-Build }
    }
}
