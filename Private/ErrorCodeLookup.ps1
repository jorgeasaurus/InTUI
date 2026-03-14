# InTUI Error Code Lookup
# Maps common Intune error codes to descriptions, categories, and remediation steps

$script:IntuneErrorCodes = @{
    '0x87D13B9F' = @{
        Description = 'App not detected after installation'
        Category    = 'Detection'
        Remediation = 'Verify detection rules match the installed app (path, registry key, MSI product code). Re-deploy after correcting rules.'
    }
    '0x87D1041C' = @{
        Description = 'APK file deleted before installation could complete'
        Category    = 'Android'
        Remediation = 'Ensure sufficient storage on device. Check for aggressive cleanup apps. Retry deployment.'
    }
    '0x87D300C9' = @{
        Description = 'Download failed due to network error'
        Category    = 'Network'
        Remediation = 'Check device network connectivity. Verify proxy/firewall allows access to Intune CDN endpoints. Retry sync.'
    }
    '0x87D13B7E' = @{
        Description = 'Content download timed out'
        Category    = 'Network'
        Remediation = 'Check network bandwidth and stability. Large apps may need a faster connection. Consider splitting content.'
    }
    '0x87D101F4' = @{
        Description = 'Uninstall failed because the app is in use'
        Category    = 'Uninstall'
        Remediation = 'Close the application before retrying uninstall. Consider scheduling uninstall during maintenance window.'
    }
    '0x87D13B94' = @{
        Description = 'System reboot required to complete installation'
        Category    = 'Install'
        Remediation = 'Reboot the device and re-sync. Consider enabling automatic reboot behavior in the app assignment.'
    }
    '0x87D13B7F' = @{
        Description = 'Insufficient disk space for installation'
        Category    = 'Storage'
        Remediation = 'Free disk space on the target device. Minimum recommended: 2x the app package size.'
    }
    '0x87D1FDE8' = @{
        Description = 'App install was canceled by the user'
        Category    = 'User'
        Remediation = 'Educate the user or switch to required assignment to install without user interaction.'
    }
    '0x87D13B96' = @{
        Description = 'Return code not mapped as success in detection rules'
        Category    = 'Detection'
        Remediation = 'Add the installer return code to the list of accepted success codes in the Win32 app configuration.'
    }
    '0x80070643' = @{
        Description = 'MSI installation failure (generic Windows Installer error)'
        Category    = 'Install'
        Remediation = 'Check MSI installer logs on the device. Common causes: prerequisites missing, corrupt MSI, or conflicting software.'
    }
    '0x87D13B64' = @{
        Description = 'Application was not detected after install (32-bit/64-bit mismatch)'
        Category    = 'Detection'
        Remediation = 'Check whether app and detection rule reference the same architecture (x86 vs x64). Adjust detection paths.'
    }
    '0x87D13B68' = @{
        Description = 'Dependent app install failed'
        Category    = 'Dependency'
        Remediation = 'Check the status of dependency apps. Fix failing dependencies before retrying the parent app.'
    }
    '0x87D13B6A' = @{
        Description = 'Application install failed due to a dependency conflict'
        Category    = 'Dependency'
        Remediation = 'Review dependency chain for circular or conflicting requirements. Simplify dependencies if possible.'
    }
    '0x87D13B93' = @{
        Description = 'Download failed - hash validation error'
        Category    = 'Network'
        Remediation = 'Content may be corrupted in transit. Re-upload the app package and retry deployment.'
    }
    '0x87D13B95' = @{
        Description = 'Install failed with an unspecified error during install phase'
        Category    = 'Install'
        Remediation = 'Review Intune Management Extension logs on the device (C:\ProgramData\Microsoft\IntuneManagementExtension\Logs).'
    }
    '0x87D13B97' = @{
        Description = 'Install command timed out'
        Category    = 'Install'
        Remediation = 'Increase the install timeout in the app configuration or optimize the installer for faster completion.'
    }
    '0x87D13B9E' = @{
        Description = 'App requirement rule not met'
        Category    = 'Requirements'
        Remediation = 'Review requirement rules (OS version, disk space, etc.). Ensure the device meets all specified requirements.'
    }
    '0x87D13BA0' = @{
        Description = 'No applicable device configuration or user found'
        Category    = 'Assignment'
        Remediation = 'Verify the app is assigned to the correct user or device group. Check group membership.'
    }
    '0x87D13BA7' = @{
        Description = 'App install is throttled by the Intune service'
        Category    = 'Service'
        Remediation = 'Wait and retry. The Intune service may be rate-limiting requests during peak usage.'
    }
    '0x87D13B80' = @{
        Description = 'Download of app content failed'
        Category    = 'Network'
        Remediation = 'Verify network connectivity and that firewall allows Intune content delivery endpoints.'
    }
    '0x87D13B82' = @{
        Description = 'Decryption of downloaded content failed'
        Category    = 'Install'
        Remediation = 'Re-upload the app package. If persistent, check for antivirus interfering with the Intune agent.'
    }
    '0x87D13B66' = @{
        Description = 'The app was removed because it was superseded'
        Category    = 'Lifecycle'
        Remediation = 'Expected behavior when supersedence is configured. The newer app should be installed instead.'
    }
    '0x87D1FDE9' = @{
        Description = 'User declined the app installation'
        Category    = 'User'
        Remediation = 'For required apps, use device-context install to bypass user prompts.'
    }
    '0x87D300C8' = @{
        Description = 'Network not available'
        Category    = 'Network'
        Remediation = 'Ensure the device has an active network connection. Check Wi-Fi or VPN status.'
    }
    '0x80073CF9' = @{
        Description = 'Package installation failed (AppX/MSIX)'
        Category    = 'Install'
        Remediation = 'Check that the MSIX/AppX package is signed correctly and meets OS version requirements.'
    }
    '0x80073CFB' = @{
        Description = 'Package is already installed'
        Category    = 'Install'
        Remediation = 'The app may already be present. Check detection rules or remove the existing version first.'
    }
    '0x80073CF0' = @{
        Description = 'Package dependencies not installed'
        Category    = 'Dependency'
        Remediation = 'Install required framework packages (VCLibs, .NET Native) before the app.'
    }
    '0x87D13B92' = @{
        Description = 'Script execution failed during install'
        Category    = 'Install'
        Remediation = 'Review the install script for errors. Check execution policy and script compatibility.'
    }
    '0x87D13B98' = @{
        Description = 'Pre-install detection found the app already installed'
        Category    = 'Detection'
        Remediation = 'App is already present. If reinstall is needed, uninstall first or update detection rules.'
    }
    '0x87D13BA1' = @{
        Description = 'GRS (Global Retry Schedule) check failed'
        Category    = 'Service'
        Remediation = 'The device needs to check in with the Intune service. Trigger a manual sync.'
    }
    '0x80070652' = @{
        Description = 'Another installation is already in progress'
        Category    = 'Install'
        Remediation = 'Wait for the current installation to complete before retrying.'
    }
    '0x87D13BAC' = @{
        Description = 'App install failed due to untrusted certificate'
        Category    = 'Security'
        Remediation = 'Ensure the app package is signed with a trusted certificate. Deploy the signing certificate if needed.'
    }
    '0x80070005' = @{
        Description = 'Access denied during installation'
        Category    = 'Permissions'
        Remediation = 'Ensure the install runs in SYSTEM context. Check file system permissions on the target path.'
    }
    '0x87D13BAD' = @{
        Description = 'Minimum OS version requirement not met'
        Category    = 'Requirements'
        Remediation = 'Update the device OS to meet the minimum version specified in the app requirements.'
    }
    '0x87D13BAE' = @{
        Description = 'Minimum disk space requirement not met'
        Category    = 'Requirements'
        Remediation = 'Free up disk space on the device to meet the minimum requirement specified in the app configuration.'
    }
    '0x80004005' = @{
        Description = 'Unspecified error (E_FAIL)'
        Category    = 'General'
        Remediation = 'Review IME logs on the device for detailed error info. Common causes: corrupt installer, permission issues.'
    }
    '0x87D13B6E' = @{
        Description = 'Auto-update supersedence - old version removed'
        Category    = 'Lifecycle'
        Remediation = 'Expected behavior. The old version is being replaced by the superseding app.'
    }
    '0x87D13BA2' = @{
        Description = 'Device is not in a valid state for app install'
        Category    = 'Device'
        Remediation = 'Ensure the device is enrolled, compliant, and has an active Intune management agent.'
    }
}

function Get-InTUIErrorCodeInfo {
    <#
    .SYNOPSIS
        Looks up an Intune error code and returns description, category, and remediation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ErrorCode
    )

    # Normalize hex format
    $normalized = $ErrorCode.Trim()
    if ($normalized -notmatch '^0x') {
        # Try to interpret as a decimal and convert to hex
        $parsed = 0
        if ([int64]::TryParse($normalized, [ref]$parsed)) {
            $normalized = '0x{0:X8}' -f $parsed
        }
        else {
            $normalized = "0x$normalized"
        }
    }

    $normalized = $normalized.ToUpper() -replace '^0X', '0x'

    if ($script:IntuneErrorCodes.ContainsKey($normalized)) {
        return $script:IntuneErrorCodes[$normalized]
    }

    return $null
}
