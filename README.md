# InTUI - Intune Terminal User Interface

A PowerShell terminal UI for managing Microsoft Intune resources via Microsoft Graph API. Uses a custom ANSI TUI engine with Catppuccin Mocha colors, Unicode box-drawing, gradient decorations, and flicker-free cursor-positioned redraws. Mimics the Intune admin center experience directly in your terminal.

![PowerShell](https://img.shields.io/badge/PowerShell-7.2+-blue)
![Graph API](https://img.shields.io/badge/Microsoft%20Graph-v1.0%20%7C%20beta-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## Features

- **Devices** - Browse all managed devices, filter by OS (Windows, iOS, macOS, Android), view compliance overview, device details with hardware info, Defender threat status panel, execute remote actions (sync, restart, rename, retire, wipe), and bulk operations
- **Apps** - Browse all managed apps, filter by platform or type (Win32, Store, Web, M365), view assignments, monitor device/user install status, view Win32 app dependencies, create app assignments, and bulk assign to groups
- **App Protection** - Browse iOS, Android, and Windows MAM policies, view VPP token status and license tracking
- **Users** - Browse and search users, view managed devices, app installations, group memberships, and license details
- **Groups** - Browse security, M365, and dynamic groups, view members, owners, device members, and dynamic membership rules
- **Configuration Profiles** - Browse device configuration profiles, filter by platform, view assignments, device status summaries, and conflict detection
- **Compliance Policies** - Browse compliance policies by platform, view assignments, per-setting status, and device compliance states
- **Scripts & Remediations** - Browse PowerShell scripts and proactive remediations, view assignments, device run states, and script content
- **Enrollment** - View Autopilot devices and deployment profiles, enrollment configurations (ESP), Apple Push Certificate status, and Apple DEP/ABM token management
- **Security** - Browse security baselines, endpoint protection policies, lookup BitLocker recovery keys, and Defender overview dashboard
- **Conditional Access** - Browse CA policies (read-only), view named locations, and filter sign-in logs
- **Reports** - Stale device reports, app install failure summaries, license utilization, compliance trend charts, and enrollment trend charts
- **Multi-Tenant** - Save tenant profiles for quick switching and tenant health summary on connect
- **Dashboard** - Summary panels with device, app, user, and group counts plus compliance statistics, with live auto-refresh mode

### Tools

- **Global Search** - Search across devices, apps, users, and groups simultaneously
- **Keyboard Shortcuts** - Vim-style navigation with shortcut bar and help overlay
- **Bookmarks** - Save and recall frequent navigation paths
- **Script Recording** - Record Graph API actions and export as replayable PowerShell scripts
- **Caching** - Local response caching with configurable TTL for faster navigation

### Navigation

- Arrow-key interactive menus with accordion sections (falls back to numbered input on non-interactive terminals)
- Breadcrumb trails show your current location
- Drill-through navigation between entities (e.g., User -> Devices -> Device Detail)
- Back navigation at every level (Escape key)
- Catppuccin Mocha color palette with gradient-decorated borders

## Prerequisites

- PowerShell 7.2+
- [Microsoft.Graph.Authentication](https://www.powershellgallery.com/packages/Microsoft.Graph.Authentication) module

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
# Launch directly
./Start-InTUI.ps1

# Connect to a specific tenant
./Start-InTUI.ps1 -TenantId "contoso.onmicrosoft.com"

# Or import as a module and use the alias
Import-Module ./InTUI.psd1
intui

# Full function names also work
Connect-InTUI
Start-InTUI
```

## Project Structure

```text
InTUI/
├── Start-InTUI.ps1           # Launch script with dependency installer
├── InTUI.psd1                # Module manifest
├── InTUI.psm1                # Root module
├── Private/
│   ├── AnsiPalette.ps1       # Catppuccin Mocha colors, markup parser, Write-InTUIText
│   ├── AnsiGradient.ps1      # Per-character RGB gradient interpolation
│   ├── AnsiWidth.ps1         # Console width detection
│   ├── AnsiCapability.ps1    # Arrow key and true color detection
│   ├── RenderMenuBox.ps1     # Unicode-bordered menu box renderer
│   ├── RenderPanel.ps1       # Content panel with gradient borders
│   ├── RenderTable.ps1       # Auto-width column table renderer
│   ├── RenderBarChart.ps1    # Horizontal bar chart with block chars
│   ├── MenuArrowSingle.ps1   # Arrow-key single selection
│   ├── MenuArrowMulti.ps1    # Arrow-key multi-select (Space/A/Enter)
│   ├── MenuArrowAccordion.ps1# Accordion-style expandable menu
│   ├── MenuClassic.ps1       # Numbered input fallback
│   ├── InputPrompt.ps1       # Text input and Y/N confirmation
│   ├── SpinnerProgress.ps1   # Rotating spinner with elapsed time
│   ├── UIHelpers.ps1         # High-level UI abstraction layer
│   ├── GraphHelpers.ps1      # Graph API connection, pagination, requests
│   ├── Logging.ps1           # Logging system
│   ├── Configuration.ps1     # Configuration management
│   ├── TenantProfiles.ps1    # Multi-tenant profile switching
│   ├── BulkOperations.ps1    # Bulk device actions and CSV export
│   ├── Cache.ps1             # Local response caching with TTL
│   ├── ScriptRecording.ps1   # Record and export Graph API actions
│   ├── KeyboardShortcuts.ps1 # Shortcut bar and help overlay
│   ├── Bookmarks.ps1         # Bookmark management
│   └── GlobalSearch.ps1      # Cross-entity search
├── Public/
│   ├── Connect-InTUI.ps1     # Connect-InTUI function
│   ├── Start-InTUI.ps1       # Start-InTUI entry point
│   └── Export-InTUIData.ps1  # Non-interactive data export for scripting
└── Views/
    ├── Dashboard.ps1              # Summary dashboard with auto-refresh
    ├── Devices.ps1                # Device management views
    ├── Apps.ps1                   # App management and assignments
    ├── AppProtection.ps1          # MAM policies and VPP tokens
    ├── Users.ps1                  # User management views
    ├── Groups.ps1                 # Group management views
    ├── ConfigurationProfiles.ps1  # Config profiles with conflict detection
    ├── CompliancePolicies.ps1     # Compliance policy views
    ├── Scripts.ps1                # PowerShell scripts and remediations
    ├── Enrollment.ps1             # Autopilot, ESP, and DEP/ABM tokens
    ├── Security.ps1               # Security baselines and Defender
    ├── ConditionalAccess.ps1      # CA policies, locations, sign-in logs
    └── Reports.ps1                # Reports and trend charts
```

## Graph API Design

InTUI exclusively uses:

- **`Microsoft.Graph.Authentication`** for connection and token management
- **`Invoke-MgGraphRequest`** for all API calls

No other Microsoft.Graph sub-modules are required. This keeps the dependency footprint minimal and gives full control over API calls including beta endpoint access.

### Required Permissions

| Scope | Purpose |
| ----- | ------- |
| `DeviceManagementManagedDevices.ReadWrite.All` | Device management and remote actions |
| `DeviceManagementApps.ReadWrite.All` | App management |
| `DeviceManagementConfiguration.Read.All` | Configuration profile status |
| `User.Read.All` | User directory access |
| `Group.Read.All` | Group directory access |
| `GroupMember.Read.All` | Group membership enumeration |
| `Directory.Read.All` | License and directory details |

## Device Actions

| Action | Description |
| ------ | ----------- |
| Sync | Triggers device check-in |
| Restart | Reboots the device |
| Rename | Changes the device name (applies on next sync) |
| Retire | Removes company data, keeps personal data |
| Wipe | Factory resets the device (double confirmation required) |

## Roadmap

### Configuration Profiles & Compliance Policies

- [x] Browse and view device configuration profiles
- [x] View per-setting compliance status across devices
- [x] Compliance policy list with assignment details
- [x] Configuration profile conflict detection and display

### App Management Enhancements

- [x] Create and edit app assignments directly from TUI
- [x] Win32 app dependency and supersedence visualization
- [x] App protection policy (MAM) browsing and status
- [x] VPP token status and license tracking for iOS/macOS

### Bulk Operations

- [x] Multi-select devices for bulk sync, restart, or retire
- [x] Bulk assign apps to groups
- [x] Export device/user/app lists to CSV from any view

### Scripts & Remediations

- [x] Browse and view PowerShell script assignments
- [x] Proactive remediation script status per device
- [x] Script execution history and output viewer

### Enrollment

- [x] Autopilot device list and profile assignments
- [x] Enrollment status page (ESP) configuration viewer
- [x] Apple DEP/ABM token status and device sync

### Security & Endpoint Protection

- [x] Microsoft Defender for Endpoint threat status per device
- [x] Security baseline assignment and compliance view
- [x] BitLocker recovery key lookup
- [x] Firewall and antivirus policy status

### Conditional Access

- [x] Browse Conditional Access policies (read-only)
- [x] Named locations viewer
- [x] Sign-in log viewer with filtering

### Reporting & Dashboards

- [x] Compliance trend charts with ANSI bar charts
- [x] Device enrollment trend by platform
- [x] Stale device report (no check-in for X days)
- [x] App install failure summary with error codes
- [x] License utilization overview

### Multi-Tenant Support

- [x] Saved tenant profiles with quick switching
- [x] Tenant health summary on connect

### UX Improvements

- [x] Keyboard shortcut bar (vim-style navigation)
- [x] Bookmarkable views (save frequent navigation paths)
- [x] Local caching layer for faster repeated lookups
- [x] Configurable cache settings via Settings menu
- [x] Live auto-refresh mode for monitoring dashboards
- [x] Global search across all entity types
- [ ] Command palette (Ctrl+P style) for quick navigation

### Automation & Integration

- [x] Record actions as replayable PowerShell scripts
- [ ] Webhook listener for real-time compliance change alerts
- [x] Pipe-friendly output mode for scripting (`Export-InTUIData`)
- [x] JSON/CSV export of device and policy configurations for diff/version control
