# InTUI - Intune Terminal User Interface

A PowerShell Spectre Console TUI for managing Microsoft Intune resources via Microsoft Graph API. Mimics the Intune admin center experience directly in your terminal.

![PowerShell](https://img.shields.io/badge/PowerShell-7.2+-blue)
![Graph API](https://img.shields.io/badge/Microsoft%20Graph-v1.0%20%7C%20beta-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Features

- **Devices** - Browse all managed devices, filter by OS (Windows, iOS, macOS, Android), view compliance overview, device details with hardware info, and execute remote actions (sync, restart, rename, retire, wipe)
- **Apps** - Browse all managed apps, filter by platform or type (Win32, Store, Web, M365), view assignments, and monitor device/user install status
- **Users** - Browse and search users, view managed devices, app installations, group memberships, and license details
- **Groups** - Browse security, M365, and dynamic groups, view members, owners, device members, and dynamic membership rules
- **Configuration Profiles** - Browse device configuration profiles, filter by platform (Windows, iOS, macOS, Android), view assignments, and device status summaries
- **Dashboard** - Summary panels with device, app, user, and group counts plus compliance statistics

### Navigation

- Breadcrumb trails show your current location
- Drill-through navigation between entities (e.g., User -> Devices -> Device Detail)
- Back navigation at every level
- Color-coded compliance states and OS icons

## Prerequisites

- PowerShell 7.2+
- [Microsoft.Graph.Authentication](https://www.powershellgallery.com/packages/Microsoft.Graph.Authentication) module
- [PwshSpectreConsole](https://www.powershellgallery.com/packages/PwshSpectreConsole) module

## Installation

```powershell
# Clone the repo
git clone https://github.com/jorgeasaurus/InTUI.git
cd InTUI

# Install dependencies
./Start-InTUI.ps1 -Install
```

## Usage

```powershell
# Launch InTUI (will prompt for Graph authentication)
./Start-InTUI.ps1

# Connect to a specific tenant
./Start-InTUI.ps1 -TenantId "contoso.onmicrosoft.com"

# Or import as a module
Import-Module ./InTUI.psd1
Connect-InTUI
Start-InTUI
```

## Project Structure

```
InTUI/
├── Start-InTUI.ps1           # Launch script with dependency installer
├── InTUI.psd1                # Module manifest
├── InTUI.psm1                # Root module
├── Private/
│   ├── GraphHelpers.ps1      # Graph API connection, pagination, requests
│   └── UIHelpers.ps1         # Spectre Console UI widgets and helpers
├── Public/
│   ├── Connect-InTUI.ps1     # Connect-InTUI function
│   └── Start-InTUI.ps1       # Start-InTUI entry point
└── Views/
    ├── Dashboard.ps1          # Summary dashboard
    ├── Devices.ps1            # Device management views
    ├── Apps.ps1               # App management views
    ├── Users.ps1              # User management views
    ├── Groups.ps1             # Group management views
    └── ConfigurationProfiles.ps1  # Configuration profile views
```

## Graph API Design

InTUI exclusively uses:

- **`Microsoft.Graph.Authentication`** for connection and token management
- **`Invoke-MgGraphRequest`** for all API calls

No other Microsoft.Graph sub-modules are required. This keeps the dependency footprint minimal and gives full control over API calls including beta endpoint access.

### Required Permissions

| Scope | Purpose |
|-------|---------|
| `DeviceManagementManagedDevices.ReadWrite.All` | Device management and remote actions |
| `DeviceManagementApps.ReadWrite.All` | App management |
| `DeviceManagementConfiguration.Read.All` | Configuration profile status |
| `User.Read.All` | User directory access |
| `Group.Read.All` | Group directory access |
| `GroupMember.Read.All` | Group membership enumeration |
| `Directory.Read.All` | License and directory details |

## Device Actions

| Action | Description |
|--------|-------------|
| Sync | Triggers device check-in |
| Restart | Reboots the device |
| Rename | Changes the device name (applies on next sync) |
| Retire | Removes company data, keeps personal data |
| Wipe | Factory resets the device (double confirmation required) |

## Roadmap

### Configuration Profiles & Compliance Policies
- [x] Browse and view device configuration profiles
- [ ] View per-setting compliance status across devices
- [ ] Compliance policy list with assignment details
- [ ] Configuration profile conflict detection and display

### App Management Enhancements
- [ ] Create and edit app assignments directly from TUI
- [ ] Win32 app dependency and supersedence visualization
- [ ] App protection policy (MAM) browsing and status
- [ ] VPP token status and license tracking for iOS/macOS

### Bulk Operations
- [ ] Multi-select devices for bulk sync, restart, or retire
- [ ] Bulk assign apps to groups
- [ ] Export device/user/app lists to CSV from any view

### Scripts & Remediations
- [ ] Browse and view PowerShell script assignments
- [ ] Proactive remediation script status per device
- [ ] Script execution history and output viewer

### Enrollment
- [ ] Autopilot device list and profile assignments
- [ ] Enrollment status page (ESP) configuration viewer
- [ ] Apple DEP/ABM token status and device sync

### Security & Endpoint Protection
- [ ] Microsoft Defender for Endpoint threat status per device
- [ ] Security baseline assignment and compliance view
- [ ] BitLocker recovery key lookup
- [ ] Firewall and antivirus policy status

### Conditional Access
- [ ] Browse Conditional Access policies (read-only)
- [ ] Named locations viewer
- [ ] Sign-in log viewer with filtering

### Reporting & Dashboards
- [ ] Compliance trend charts using Spectre Canvas
- [ ] Device enrollment trend over time
- [ ] Stale device report (no check-in for X days)
- [ ] App install failure summary with error codes
- [ ] License utilization overview

### Multi-Tenant Support
- [ ] Saved tenant profiles with quick switching
- [ ] Side-by-side tenant comparison views
- [ ] Tenant health summary on connect

### UX Improvements
- [ ] Keyboard shortcut bar (vim-style navigation)
- [ ] Bookmarkable views (save frequent navigation paths)
- [ ] Local caching layer for faster repeated lookups
- [ ] Configurable page sizes and refresh intervals
- [ ] Live auto-refresh mode for monitoring dashboards
- [ ] Search-as-you-type across all entity types
- [ ] Command palette (Ctrl+P style) for quick navigation

### Automation & Integration
- [ ] Record actions as replayable PowerShell scripts
- [ ] Webhook listener for real-time compliance change alerts
- [ ] Pipe-friendly output mode for scripting (`Start-InTUI -NonInteractive`)
- [ ] JSON/YAML export of device and policy configurations for diff/version control
