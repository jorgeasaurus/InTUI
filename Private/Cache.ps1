# InTUI Caching Layer
# Provides local caching for Graph API responses to improve performance

function Initialize-InTUICache {
    <#
    .SYNOPSIS
        Initializes the cache directory structure.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:CachePath)) {
        try {
            New-Item -Path $script:CachePath -ItemType Directory -Force | Out-Null
            Write-InTUILog -Message "Cache directory created" -Context @{ Path = $script:CachePath }
        }
        catch {
            Write-InTUILog -Level 'WARN' -Message "Failed to create cache directory: $($_.Exception.Message)"
            $script:CacheEnabled = $false
        }
    }
}

function Get-InTUICacheKey {
    <#
    .SYNOPSIS
        Generates a cache key from URI and parameters.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [string]$Method = 'GET',

        [Parameter()]
        [switch]$Beta
    )

    $keySource = "$Method|$Uri|$Beta"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($keySource)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $hashString = [BitConverter]::ToString($hash) -replace '-', ''

    return $hashString.Substring(0, 32)
}

function Get-InTUICachedResponse {
    <#
    .SYNOPSIS
        Retrieves a cached response if valid.
    .DESCRIPTION
        Checks the cache for a valid response. Returns $null if cache miss or expired.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [string]$Method = 'GET',

        [Parameter()]
        [switch]$Beta
    )

    if (-not $script:CacheEnabled) {
        return $null
    }

    # Only cache GET requests
    if ($Method -ne 'GET') {
        return $null
    }

    $cacheKey = Get-InTUICacheKey -Uri $Uri -Method $Method -Beta:$Beta
    $cacheFile = Join-Path $script:CachePath "$cacheKey.json"

    if (-not (Test-Path $cacheFile)) {
        return $null
    }

    try {
        $cached = Get-Content $cacheFile -Raw | ConvertFrom-Json

        $cachedTime = [DateTime]::Parse($cached.Timestamp)
        $age = ([DateTime]::UtcNow - $cachedTime).TotalSeconds

        if ($age -gt $script:CacheTTL) {
            Write-InTUILog -Message "Cache expired" -Context @{ Uri = $Uri; Age = [math]::Round($age) }
            Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
            return $null
        }

        Write-InTUILog -Message "Cache hit" -Context @{ Uri = $Uri; Age = [math]::Round($age) }
        return $cached.Data
    }
    catch {
        Write-InTUILog -Level 'WARN' -Message "Failed to read cache: $($_.Exception.Message)"
        return $null
    }
}

function Set-InTUICachedResponse {
    <#
    .SYNOPSIS
        Stores a response in the cache.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        $Data,

        [Parameter()]
        [string]$Method = 'GET',

        [Parameter()]
        [switch]$Beta
    )

    if (-not $script:CacheEnabled) {
        return
    }

    # Only cache GET requests
    if ($Method -ne 'GET') {
        return
    }

    Initialize-InTUICache

    $cacheKey = Get-InTUICacheKey -Uri $Uri -Method $Method -Beta:$Beta
    $cacheFile = Join-Path $script:CachePath "$cacheKey.json"

    try {
        $cacheEntry = @{
            Uri       = $Uri
            Method    = $Method
            Beta      = [bool]$Beta
            Timestamp = [DateTime]::UtcNow.ToString('o')
            Data      = $Data
        }

        $cacheEntry | ConvertTo-Json -Depth 20 | Set-Content $cacheFile -Encoding UTF8
        Write-InTUILog -Message "Cache write" -Context @{ Uri = $Uri; Key = $cacheKey }
    }
    catch {
        Write-InTUILog -Level 'WARN' -Message "Failed to write cache: $($_.Exception.Message)"
    }
}

function Clear-InTUICache {
    <#
    .SYNOPSIS
        Clears cached responses.
    .PARAMETER ExpiredOnly
        Only remove expired entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$ExpiredOnly
    )

    if (-not (Test-Path $script:CachePath)) {
        Write-InTUILog -Message "Cache directory does not exist"
        return 0
    }

    $cacheFiles = Get-ChildItem -Path $script:CachePath -Filter '*.json' -ErrorAction SilentlyContinue
    $removedCount = 0

    foreach ($file in $cacheFiles) {
        $shouldRemove = $true

        if ($ExpiredOnly) {
            try {
                $cached = Get-Content $file.FullName -Raw | ConvertFrom-Json
                $cachedTime = [DateTime]::Parse($cached.Timestamp)
                $age = ([DateTime]::UtcNow - $cachedTime).TotalSeconds

                if ($age -le $script:CacheTTL) {
                    $shouldRemove = $false
                }
            }
            catch {
                # If we can't read it, remove it
                $shouldRemove = $true
            }
        }

        if ($shouldRemove) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            $removedCount++
        }
    }

    Write-InTUILog -Message "Cache cleared" -Context @{ RemovedCount = $removedCount; ExpiredOnly = [bool]$ExpiredOnly }
    return $removedCount
}

function Get-InTUICacheStats {
    <#
    .SYNOPSIS
        Returns cache statistics.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:CachePath)) {
        return @{
            Enabled    = $script:CacheEnabled
            TTL        = $script:CacheTTL
            EntryCount = 0
            TotalSize  = 0
            ValidCount = 0
            ExpiredCount = 0
        }
    }

    $cacheFiles = Get-ChildItem -Path $script:CachePath -Filter '*.json' -ErrorAction SilentlyContinue
    $totalSize = 0
    $validCount = 0
    $expiredCount = 0

    foreach ($file in $cacheFiles) {
        $totalSize += $file.Length

        try {
            $cached = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $cachedTime = [DateTime]::Parse($cached.Timestamp)
            $age = ([DateTime]::UtcNow - $cachedTime).TotalSeconds

            if ($age -le $script:CacheTTL) {
                $validCount++
            }
            else {
                $expiredCount++
            }
        }
        catch {
            $expiredCount++
        }
    }

    return @{
        Enabled      = $script:CacheEnabled
        TTL          = $script:CacheTTL
        EntryCount   = $cacheFiles.Count
        TotalSize    = $totalSize
        ValidCount   = $validCount
        ExpiredCount = $expiredCount
    }
}
