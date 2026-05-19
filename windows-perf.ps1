<#
.SYNOPSIS
    Windows 11 Performance, Privacy & QoL Optimization Script
.DESCRIPTION
    Comprehensive Windows 11 optimization for power users and developers.
    Covers: power plans, services, network, privacy, UI speed, bloatware removal,
    gaming/GPU, memory/disk, developer tools, and more.

    Designed for high-end workstations but safe for any Windows 11 machine.
    Creates a restore point before making changes. Every tweak is documented.

    Run as Administrator for full effect. User-level tweaks apply without elevation.
.NOTES
    Author : github.com/withseismic
    License: MIT
    Tested : Windows 11 Pro 24H2 (Build 26100)
    Machine: Ryzen 9 5950X / 128GB / RTX 3090
.LINK
    https://github.com/withseismic/windows-perf
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Interactive,
    [switch]$DryRun,
    [string[]]$Only,
    [string[]]$Skip,
    [switch]$Help
)

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

$Script:Version = "1.0.0"
$Script:LogFile = "$env:USERPROFILE\Desktop\windows-perf-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$Script:IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$Script:TweaksApplied = 0
$Script:TweaksFailed = 0
$Script:TweaksSkipped = 0

# DNS provider options
$Script:DnsProviders = @{
    "cloudflare" = @("1.1.1.1", "1.0.0.1")
    "google"     = @("8.8.8.8", "8.8.4.4")
    "quad9"      = @("9.9.9.9", "149.112.112.112")
}

# Apps to remove - conservative list, nothing that breaks core Windows
$Script:BloatwareApps = @(
    "Microsoft.Copilot",
    "Microsoft.YourPhone",
    "Clipchamp.Clipchamp",
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.BingSearch",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.People",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.MixedReality.Portal",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.SkypeApp",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Microsoft.Todos",
    "MicrosoftCorporationII.QuickAssist",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.Office.OneNote",
    "Microsoft.WindowsMaps",
    "Microsoft.Edge.GameAssist",
    "MSTeams",
    "MicrosoftWindows.CrossDevice",
    "Microsoft.GetHelp",
    "Microsoft.WindowsAlarms",
    "Microsoft.OutlookForWindows",
    "MicrosoftWindows.Client.WebExperience",
    "Microsoft.WidgetsPlatformRuntime",
    "Microsoft.Windows.DevHome",
    "Microsoft.WindowsSoundRecorder",
    "microsoft.windowscommunicationsapps"
)

# Services to disable
$Script:BloatServices = @(
    @{Name="DiagTrack";          Desc="Telemetry data collection"},
    @{Name="dmwappushservice";   Desc="WAP push messages"},
    @{Name="SysMain";            Desc="Superfetch (unnecessary with SSD + plenty of RAM)"},
    @{Name="WSearch";            Desc="Windows Search indexer (use Everything instead)"},
    @{Name="MapsBroker";         Desc="Offline maps manager"},
    @{Name="lfsvc";              Desc="Geolocation tracking"},
    @{Name="RetailDemo";         Desc="Retail demo experience"},
    @{Name="WerSvc";             Desc="Windows error reporting"},
    @{Name="Fax";                Desc="Fax service"},
    @{Name="wisvc";              Desc="Windows Insider program"}
)

# Scheduled tasks to disable
$Script:BloatTasks = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp",
    "\Microsoft\Windows\Application Experience\PcaPatchDbTask",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\Feedback\Siuf\DmClient",
    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
    "\Microsoft\Windows\Maps\MapsToastTask",
    "\Microsoft\Windows\Maintenance\WinSAT"
)

# ═══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

function Write-Log {
    param([string]$Message, [string]$Status = "OK", [switch]$NoNewLine)
    $color = switch ($Status) {
        "OK"    { "Green" }
        "SKIP"  { "Yellow" }
        "FAIL"  { "Red" }
        "INFO"  { "Cyan" }
        "WARN"  { "DarkYellow" }
        default { "White" }
    }
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logLine = "[$timestamp][$Status] $Message"
    Write-Host "[$Status] " -ForegroundColor $color -NoNewline
    if ($NoNewLine) { Write-Host $Message -NoNewline } else { Write-Host $Message }
    Add-Content -Path $Script:LogFile -Value $logLine -ErrorAction SilentlyContinue
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord",
        [string]$Description = ""
    )
    if ($DryRun) {
        Write-Log "(DRY RUN) Would set $Path\$Name = $Value" "INFO"
        return
    }
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -ErrorAction Stop
    } catch {
        Write-Log "Registry failed: $Path\$Name - $($_.Exception.Message)" "FAIL"
        $Script:TweaksFailed++
    }
}

function Confirm-Action {
    param([string]$Message, [bool]$Default = $true)
    if (-not $Interactive) { return $true }
    $defaultHint = if ($Default) { "[Y/n]" } else { "[y/N]" }
    $response = Read-Host "$Message $defaultHint"
    if ([string]::IsNullOrWhiteSpace($response)) { return $Default }
    return $response -match '^[Yy]'
}

function Show-Banner {
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $cpu = (Get-CimInstance Win32_Processor).Name.Trim()
    $gpu = (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch "Microsoft" } | Select-Object -First 1).Name
    $build = [System.Environment]::OSVersion.Version.Build

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║         windows-perf v$Script:Version                        ║" -ForegroundColor Cyan
    Write-Host "  ║         Windows 11 Performance Optimizer             ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Machine : $env:COMPUTERNAME" -ForegroundColor Gray
    Write-Host "  CPU     : $cpu" -ForegroundColor Gray
    Write-Host "  GPU     : $gpu" -ForegroundColor Gray
    Write-Host "  RAM     : ${ram}GB" -ForegroundColor Gray
    Write-Host "  Build   : $build" -ForegroundColor Gray
    Write-Host "  Admin   : $Script:IsAdmin" -ForegroundColor $(if ($Script:IsAdmin) { "Green" } else { "Yellow" })
    if ($DryRun) { Write-Host "  Mode    : DRY RUN (no changes)" -ForegroundColor Yellow }
    Write-Host ""
}

function Show-Help {
    $helpText = @'

  windows-perf.ps1 - Windows 11 Performance Optimizer

  USAGE:
    .\windows-perf.ps1                  # Run all tweaks (recommended)
    .\windows-perf.ps1 -Interactive     # Prompt before each category
    .\windows-perf.ps1 -DryRun         # Preview changes without applying
    .\windows-perf.ps1 -Only power,net # Run specific modules only
    .\windows-perf.ps1 -Skip bloatware # Skip specific modules

  MODULES:
    power       Ultimate Performance power plan, core parking, idle states
    services    Disable bloat services (telemetry, search, superfetch, etc.)
    network     DNS, Nagle, TCP, RSS, RSC, throttling, port range
    privacy     Telemetry, ads, tracking, Bing, Cortana, Copilot, Edge nags
    ui          Menu speed, animations, visual effects, shutdown speed
    explorer    File extensions, hidden files, classic context menu, paths
    taskbar     Remove widgets, chat, search, copilot, task view
    gaming      GPU scheduling, Game Mode, DVR, TDR, NVIDIA max perf
    memory      Pagefile, TRIM, NTFS, hibernation, large cache, compression
    bloatware   Remove 30+ preinstalled junk apps + block reinstall
    onedrive    Full OneDrive removal and cleanup
    developer   Git, dev mode, long paths, UTF-8, NTFS, ports, NODE_OPTIONS
    defender    Defender exclusions for dev folders/processes (huge build boost)
    input       Mouse acceleration, sticky/filter/toggle key prompts
    misc        Dark mode, clipboard, background apps, lock screen, maintenance
    tasks       Disable telemetry/CEIP/diagnostic scheduled tasks
    wsl         WSL2 memory, CPU, swap, sparse VHD optimization

  FLAGS:
    -All            Run everything without prompts
    -Interactive    Ask before each module
    -DryRun         Show what would change, change nothing
    -Only [list]    Comma-separated modules to run
    -Skip [list]    Comma-separated modules to skip
    -Help           Show this message

  NOTES:
    * Run as Administrator for full effect
    * Creates a System Restore point before changes
    * Logs all actions to ~/Desktop/windows-perf-*.log
    * Reboot required after running for full effect

'@
    Write-Host $helpText -ForegroundColor Gray
}

function ShouldRun {
    param([string]$Module)
    if ($Only -and $Only.Count -gt 0) { return $Module -in $Only }
    if ($Skip -and $Skip.Count -gt 0) { return $Module -notin $Skip }
    return $true
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: POWER PLAN
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-PowerOptimization {
    Write-Host "`n━━━ Power Plan ━━━" -ForegroundColor Magenta
    if (-not $Script:IsAdmin) {
        Write-Log "Skipping power plan (requires admin)" "SKIP"
        $Script:TweaksSkipped++
        return
    }
    if (-not (Confirm-Action "Activate Ultimate Performance power plan?")) { return }

    try {
        $existing = powercfg /list | Select-String "Ultimate Performance"
        if (-not $existing) {
            powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
        }
        $guid = (powercfg /list | Select-String "Ultimate Performance").ToString() -replace '.*(\w{8}-\w{4}-\w{4}-\w{4}-\w{12}).*', '$1'

        if (-not $DryRun) {
            powercfg /setactive $guid
            # USB selective suspend off
            powercfg /setacvalueindex $guid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
            # PCI Express Link State Power Management off
            powercfg /setacvalueindex $guid 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0
            # CPU min/max 100%
            powercfg /setacvalueindex $guid 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 100
            powercfg /setacvalueindex $guid 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec 100
            # Disk never sleeps
            powercfg /setacvalueindex $guid 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0
            # Display never sleeps
            powercfg /setacvalueindex $guid 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 0
            # System never sleeps
            powercfg /setacvalueindex $guid 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0
            # Disable core parking (all cores always available - critical for parallel compilation)
            powercfg /setacvalueindex $guid 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583 100
            # Disable processor idle states (keeps cores hot for faster response)
            powercfg /setacvalueindex $guid 54533251-82be-4824-96c1-47b60b740d00 5d76a2ca-e8c0-402f-a133-2158492d58ad 0 2>$null
            powercfg /setactive $guid
        }
        Write-Log "Ultimate Performance plan activated"
        Write-Log "USB suspend, PCI-E power mgmt, CPU throttle, sleep: all disabled"
        $Script:TweaksApplied++
    } catch {
        Write-Log "Power plan failed: $_" "FAIL"
        $Script:TweaksFailed++
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: SERVICES
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-ServiceOptimization {
    Write-Host "`n━━━ Services ━━━" -ForegroundColor Magenta
    if (-not $Script:IsAdmin) {
        Write-Log "Skipping services (requires admin)" "SKIP"
        $Script:TweaksSkipped++
        return
    }
    if (-not (Confirm-Action "Disable bloat services?")) { return }

    foreach ($svc in $Script:BloatServices) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if (-not $service) { continue }
        if ($service.StartType -eq "Disabled") {
            Write-Log "$($svc.Name) already disabled" "SKIP"
            continue
        }
        if (-not $DryRun) {
            try {
                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
                Write-Log "Disabled $($svc.Name) - $($svc.Desc)"
                $Script:TweaksApplied++
            } catch {
                Write-Log "Failed to disable $($svc.Name): $_" "FAIL"
                $Script:TweaksFailed++
            }
        } else {
            Write-Log "(DRY RUN) Would disable $($svc.Name) - $($svc.Desc)" "INFO"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: NETWORK
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-NetworkOptimization {
    param([string]$DnsProvider = "cloudflare")

    Write-Host "`n━━━ Network ━━━" -ForegroundColor Magenta
    if (-not (Confirm-Action "Optimize network settings?")) { return }

    # DNS
    if ($Script:IsAdmin) {
        $dns = $Script:DnsProviders[$DnsProvider]
        if ($dns) {
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Virtual|Loopback" } | Select-Object -First 1
            if ($adapter -and -not $DryRun) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $dns
                Clear-DnsClientCache
                Write-Log "DNS set to $DnsProvider ($($dns -join ', ')) on $($adapter.Name)"
            } elseif ($adapter) {
                Write-Log "(DRY RUN) Would set DNS to $DnsProvider on $($adapter.Name)" "INFO"
            }
            $Script:TweaksApplied++
        }
    } else {
        Write-Log "DNS change requires admin" "SKIP"
        $Script:TweaksSkipped++
    }

    # Nagle's algorithm
    if ($Script:IsAdmin) {
        $interfaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue
        foreach ($iface in $interfaces) {
            Set-RegistryValue -Path $iface.PSPath -Name "TcpAckFrequency" -Value 1
            Set-RegistryValue -Path $iface.PSPath -Name "TCPNoDelay" -Value 1
        }
        Write-Log "Nagle's algorithm disabled (lower latency)"
        $Script:TweaksApplied++
    }

    # RSS + RSC (distribute network processing across all cores)
    if ($Script:IsAdmin -and -not $DryRun) {
        Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
            try { Set-NetAdapterRss -Name $_.Name -Enabled $true -ErrorAction Stop } catch {}
            try { Enable-NetAdapterRsc -Name $_.Name -IPv4 -ErrorAction Stop } catch {}
        }
        Write-Log "Network RSS + RSC enabled (multi-core network processing)"
        $Script:TweaksApplied++
    }

    # TCP stack
    if ($Script:IsAdmin -and -not $DryRun) {
        netsh int tcp set global autotuninglevel=normal 2>$null | Out-Null
        netsh int tcp set global rss=enabled 2>$null | Out-Null
        netsh int tcp set global dca=enabled 2>$null | Out-Null
        netsh int tcp set global timestamps=disabled 2>$null | Out-Null
        netsh int tcp set global ecncapability=enabled 2>$null | Out-Null
        Write-Log "TCP stack optimized (RSS, DCA, ECN, timestamps off)"
        $Script:TweaksApplied++
    }

    # Disable network throttling (multimedia scheduler limits bandwidth to 10 packets/ms by default)
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF
        Write-Log "Network throttling disabled"
        $Script:TweaksApplied++
    }

    # Disable Delivery Optimization P2P uploads
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0
        Write-Log "Windows Update P2P delivery (upload to strangers) disabled"
        $Script:TweaksApplied++
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: PRIVACY & TELEMETRY
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-PrivacyOptimization {
    Write-Host "`n━━━ Privacy & Telemetry ━━━" -ForegroundColor Magenta
    if (-not (Confirm-Action "Apply privacy and telemetry tweaks?")) { return }

    # --- User-level (no admin) ---
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $contentSettings = @{
        "SubscribedContent-338388Enabled" = 0
        "SubscribedContent-338389Enabled" = 0
        "SubscribedContent-310093Enabled" = 0
        "SubscribedContent-338393Enabled" = 0
        "SubscribedContent-353694Enabled" = 0
        "SubscribedContent-353696Enabled" = 0
        "SystemPaneSuggestionsEnabled"    = 0
        "SoftLandingEnabled"              = 0
        "RotatingLockScreenEnabled"       = 0
        "RotatingLockScreenOverlayEnabled"= 0
        "SilentInstalledAppsEnabled"      = 0
        "ContentDeliveryAllowed"          = 0
        "OemPreInstalledAppsEnabled"      = 0
        "PreInstalledAppsEnabled"         = 0
        "PreInstalledAppsEverEnabled"     = 0
        "FeatureManagementEnabled"        = 0
    }
    foreach ($key in $contentSettings.Keys) {
        Set-RegistryValue -Path $cdm -Name $key -Value $contentSettings[$key]
    }
    Write-Log "Content delivery / silent installs / suggestions disabled"

    # Advertising ID
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0
    Write-Log "Advertising ID disabled"

    # Feedback frequency
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "PeriodInNanoSeconds" -Value 0
    Write-Log "Feedback requests disabled"

    # Bing in Start
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0
    Write-Log "Bing search in Start menu disabled"

    # Tailored experiences
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0

    # --- System-level (admin) ---
    if ($Script:IsAdmin) {
        # Telemetry to zero
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "MaxTelemetryAllowed" -Value 0
        Write-Log "System telemetry set to zero"

        # Activity history
        $sysPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        Set-RegistryValue -Path $sysPath -Name "EnableActivityFeed" -Value 0
        Set-RegistryValue -Path $sysPath -Name "PublishUserActivities" -Value 0
        Set-RegistryValue -Path $sysPath -Name "UploadUserActivities" -Value 0
        Write-Log "Activity history disabled"

        # Cortana / web search
        $wsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
        Set-RegistryValue -Path $wsPath -Name "AllowCortana" -Value 0
        Set-RegistryValue -Path $wsPath -Name "DisableWebSearch" -Value 1
        Set-RegistryValue -Path $wsPath -Name "ConnectedSearchUseWeb" -Value 0
        Write-Log "Cortana and web search disabled"

        # Consumer features
        $ccPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        Set-RegistryValue -Path $ccPath -Name "DisableSoftLanding" -Value 1
        Set-RegistryValue -Path $ccPath -Name "DisableWindowsConsumerFeatures" -Value 1
        Set-RegistryValue -Path $ccPath -Name "DisableCloudOptimizedContent" -Value 1
        Write-Log "Consumer features and cloud content disabled"

        # Copilot
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
        Write-Log "Copilot disabled via policy"

        # Edge nagging
        $edgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        Set-RegistryValue -Path $edgePath -Name "HideFirstRunExperience" -Value 1
        Set-RegistryValue -Path $edgePath -Name "DefaultBrowserSettingEnabled" -Value 0
        Set-RegistryValue -Path $edgePath -Name "DefaultBrowserSettingsCampaignEnabled" -Value 0
        Set-RegistryValue -Path $edgePath -Name "HubsSidebarEnabled" -Value 0
        Set-RegistryValue -Path $edgePath -Name "ShowRecommendationsEnabled" -Value 0
        Write-Log "Edge nag prompts suppressed"
    }

    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: UI SPEED
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-UIOptimization {
    Write-Host "`n━━━ UI Speed ━━━" -ForegroundColor Magenta
    if (-not (Confirm-Action "Speed up UI animations and menus?")) { return }

    $desktop = "HKCU:\Control Panel\Desktop"

    # Zero menu delay
    Set-RegistryValue -Path $desktop -Name "MenuShowDelay" -Value "0" -Type String
    # Disable minimize animation
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -Type String
    Write-Log "Menu delay and minimize animation eliminated"

    # Faster shutdown behavior
    Set-RegistryValue -Path $desktop -Name "WaitToKillAppTimeout" -Value "2000" -Type String
    Set-RegistryValue -Path $desktop -Name "HungAppTimeout" -Value "1000" -Type String
    Set-RegistryValue -Path $desktop -Name "AutoEndTasks" -Value "1" -Type String
    Set-RegistryValue -Path $desktop -Name "LowLevelHooksTimeout" -Value 1000
    Write-Log "App kill timeout reduced (faster shutdown)"

    # Visual effects - performance tuned, keep font smoothing
    $vePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    Set-RegistryValue -Path $vePath -Name "VisualFXSetting" -Value 3
    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-RegistryValue -Path $advPath -Name "ListviewAlphaSelect" -Value 0
    Set-RegistryValue -Path $advPath -Name "TaskbarAnimations" -Value 0
    Write-Log "Visual effects set to performance (font smoothing preserved)"

    # ClearType stays on
    Set-RegistryValue -Path $desktop -Name "FontSmoothing" -Value "2" -Type String
    Set-RegistryValue -Path $desktop -Name "FontSmoothingType" -Value 2

    # Disable Aero Peek
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "AlwaysHibernateThumbnails" -Value 0
    Write-Log "Aero Peek disabled"

    # System-level shutdown speed
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "WaitToKillServiceTimeout" -Value "2000" -Type String
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -Name "StartupDelayInMSec" -Value 0
        Write-Log "Service kill timeout + startup delay optimized"
    }

    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: FILE EXPLORER
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-ExplorerOptimization {
    Write-Host "`n━━━ File Explorer ━━━" -ForegroundColor Magenta
    if (-not (Confirm-Action "Apply File Explorer quality-of-life tweaks?")) { return }

    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $expPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"

    # Show file extensions
    Set-RegistryValue -Path $advPath -Name "HideFileExt" -Value 0
    # Show hidden files
    Set-RegistryValue -Path $advPath -Name "Hidden" -Value 1
    # Open to "This PC"
    Set-RegistryValue -Path $advPath -Name "LaunchTo" -Value 1
    # Disable shortcut suffix
    Set-RegistryValue -Path $expPath -Name "link" -Value ([byte[]](0x00,0x00,0x00,0x00)) -Type Binary
    # Disable recent files in Quick Access
    Set-RegistryValue -Path $advPath -Name "Start_TrackDocs" -Value 0
    # Full path in title bar
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath" -Value 1
    Write-Log "Explorer: extensions visible, hidden files shown, full path, This PC default"

    # Classic right-click context menu (Windows 11)
    $ctxPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    Set-RegistryValue -Path $ctxPath -Name "(Default)" -Value "" -Type String
    Write-Log "Classic right-click context menu restored"

    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: TASKBAR
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-TaskbarOptimization {
    Write-Host "`n━━━ Taskbar ━━━" -ForegroundColor Magenta
    if (-not (Confirm-Action "Clean up taskbar (remove widgets, chat, search, copilot)?")) { return }

    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    Set-RegistryValue -Path $advPath -Name "TaskbarDa" -Value 0        # Widgets
    Set-RegistryValue -Path $advPath -Name "ShowTaskViewButton" -Value 0
    Set-RegistryValue -Path $advPath -Name "TaskbarMn" -Value 0        # Chat
    Set-RegistryValue -Path $advPath -Name "ShowCopilotButton" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0
    Write-Log "Removed: Widgets, Task View, Chat, Copilot, Search box"

    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: GAMING & GPU
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-GamingOptimization {
    Write-Host "`n━━━ Gaming & GPU ━━━" -ForegroundColor Magenta
    if (-not (Confirm-Action "Apply gaming and GPU optimizations?")) { return }

    # User-level: Game Bar DVR off, Game Mode on
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "UseNexusForGameBarEnabled" -Value 0
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0
    Set-RegistryValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0
    Write-Log "Game Bar DVR disabled, Game Mode enabled"

    # Fullscreen optimization config
    $gcs = "HKCU:\System\GameConfigStore"
    Set-RegistryValue -Path $gcs -Name "GameDVR_DXGIHonorPowerPolicy" -Value 0
    Set-RegistryValue -Path $gcs -Name "GameDVR_HonorUserFSEBehaviorMode" -Value 0
    Set-RegistryValue -Path $gcs -Name "GameDVR_EFSEFeatureFlags" -Value 0
    Set-RegistryValue -Path $gcs -Name "GameDVR_FSEBehavior" -Value 2
    Set-RegistryValue -Path $gcs -Name "GameDVR_FSEBehaviorMode" -Value 2
    Write-Log "Fullscreen optimizations configured"

    if ($Script:IsAdmin) {
        # Hardware-accelerated GPU scheduling
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2
        Write-Log "Hardware-accelerated GPU scheduling enabled"

        # NVIDIA max performance (if NVIDIA GPU present)
        $nvidiaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000"
        if (Test-Path $nvidiaPath) {
            Set-RegistryValue -Path $nvidiaPath -Name "PerfLevelSrc" -Value 0x2222
            Set-RegistryValue -Path $nvidiaPath -Name "PowerMizerEnable" -Value 1
            Set-RegistryValue -Path $nvidiaPath -Name "PowerMizerLevel" -Value 1
            Set-RegistryValue -Path $nvidiaPath -Name "PowerMizerLevelAC" -Value 1
            Write-Log "NVIDIA power management set to maximum performance"
        }

        # Multimedia scheduler - prioritize games/GPU tasks
        $mmcss = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-RegistryValue -Path $mmcss -Name "SystemResponsiveness" -Value 0
        Set-RegistryValue -Path "$mmcss\Tasks\Games" -Name "GPU Priority" -Value 8
        Set-RegistryValue -Path "$mmcss\Tasks\Games" -Name "Priority" -Value 6
        Set-RegistryValue -Path "$mmcss\Tasks\Games" -Name "Scheduling Category" -Value "High" -Type String
        Write-Log "Multimedia scheduler: GPU and game priority maximized"

        # Increase TDR timeout (prevents GPU timeout during CUDA/ML/heavy compute)
        $gfxDrivers = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        Set-RegistryValue -Path $gfxDrivers -Name "TdrDelay" -Value 10
        Set-RegistryValue -Path $gfxDrivers -Name "TdrDdiDelay" -Value 10
        Write-Log "GPU TDR timeout increased to 10s (prevents timeout during heavy compute)"

        # Disable GPU preemption granularity (reduces microstutters)
        Set-RegistryValue -Path "$gfxDrivers\Scheduler" -Name "EnablePreemption" -Value 0
        Write-Log "GPU preemption disabled (reduces microstutters)"
    }

    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: MEMORY & DISK
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-MemoryOptimization {
    Write-Host "`n━━━ Memory & Disk ━━━" -ForegroundColor Magenta
    if (-not $Script:IsAdmin) {
        Write-Log "Skipping memory/disk (requires admin)" "SKIP"
        $Script:TweaksSkipped++
        return
    }
    if (-not (Confirm-Action "Optimize memory and disk settings?")) { return }

    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)

    # Pagefile: disable if >= 64GB RAM, set small if >= 32GB
    if ($ramGB -ge 64) {
        try {
            $cs = Get-CimInstance Win32_ComputerSystem
            if ($cs.AutomaticManagedPagefile -and -not $DryRun) {
                $cs | Set-CimInstance -Property @{AutomaticManagedPagefile = $false}
            }
            if (-not $DryRun) {
                Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Remove-CimInstance -ErrorAction SilentlyContinue
            }
            Write-Log "Pagefile disabled (${ramGB}GB RAM)"
        } catch {
            Write-Log "Pagefile change failed: $_" "FAIL"
        }
    } elseif ($ramGB -ge 32) {
        Write-Log "Pagefile: consider reducing to 4GB with ${ramGB}GB RAM" "INFO"
    } else {
        Write-Log "Pagefile: keeping default (${ramGB}GB RAM)" "SKIP"
    }

    # NTFS optimizations
    if (-not $DryRun) {
        fsutil behavior set disablelastaccess 1 | Out-Null
        fsutil behavior set disabledeletenotify 0 | Out-Null
    }
    Write-Log "NTFS: last access timestamps off, TRIM on"

    # Large system cache for high-RAM systems
    $memPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    if ($ramGB -ge 32) {
        Set-RegistryValue -Path $memPath -Name "LargeSystemCache" -Value 1
        Set-RegistryValue -Path $memPath -Name "IoPageLockLimit" -Value 983040
        Write-Log "Large system cache + IO page lock optimized for ${ramGB}GB"
    }

    # Disable hibernation (saves RAM-sized disk space)
    if (-not $DryRun) {
        powercfg /hibernate off 2>$null
    }
    Write-Log "Hibernation disabled (saves ${ramGB}GB disk space)"

    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: BLOATWARE REMOVAL
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-BloatwareRemoval {
    Write-Host "`n━━━ Bloatware Removal ━━━" -ForegroundColor Magenta
    if (-not (Confirm-Action "Remove preinstalled bloatware apps?")) { return }

    $removed = 0
    foreach ($app in $Script:BloatwareApps) {
        $pkg = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
        if (-not $pkg) { continue }
        if ($DryRun) {
            Write-Log "(DRY RUN) Would remove $app" "INFO"
            continue
        }
        try {
            $pkg | Remove-AppxPackage -ErrorAction Stop
            Write-Log "Removed $app"
            $removed++
        } catch {
            Write-Log "Failed to remove $app" "FAIL"
            $Script:TweaksFailed++
        }
    }

    # Deprovision so they don't come back (admin only)
    if ($Script:IsAdmin -and -not $DryRun) {
        $deprovCount = 0
        foreach ($app in $Script:BloatwareApps) {
            $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $app }
            if ($prov) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                    $deprovCount++
                } catch {}
            }
        }
        if ($deprovCount -gt 0) {
            Write-Log "Deprovisioned $deprovCount packages (won't return on updates)"
        }
    }

    # Block auto-download of store apps
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SilentInstalledAppsEnabled" -Value 0
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name "AutoDownload" -Value 2
    }

    Write-Log "Removed $removed apps total"
    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: DEVELOPER
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-DeveloperOptimization {
    Write-Host "`n━━━ Developer QoL ━━━" -ForegroundColor Magenta
    if (-not (Confirm-Action "Apply developer-focused optimizations?")) { return }

    # Developer mode
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -Value 1
    Write-Log "Developer mode enabled"

    # Git optimizations
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and -not $DryRun) {
        git config --global fetch.parallel 0
        git config --global diff.algorithm histogram
        git config --global help.autocorrect 20
        git config --global merge.conflictstyle zdiff3
        git config --global rerere.enabled true
        git config --global pack.threads 0
        git config --global core.fsmonitor true
        git config --global core.untrackedcache true
        Write-Log "Git: parallel fetch, histogram diff, fsmonitor, rerere, zdiff3 merge"
    } elseif (-not $git) {
        Write-Log "Git not found, skipping git config" "SKIP"
    }

    # Windows Terminal as default
    $wt = Get-Command wt -ErrorAction SilentlyContinue
    if ($wt) {
        $consolePath = "HKCU:\Console\%%Startup"
        Set-RegistryValue -Path $consolePath -Name "DelegationConsole" -Value "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}" -Type String
        Set-RegistryValue -Path $consolePath -Name "DelegationTerminal" -Value "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" -Type String
        Write-Log "Windows Terminal set as default terminal"
    }

    # Long paths enabled (needed for node_modules and deep repos)
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1
        Write-Log "Long paths enabled (fixes deep node_modules)"
    }

    # UTF-8 system locale
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage" -Name "ACP" -Value "65001" -Type String
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage" -Name "OEMCP" -Value "65001" -Type String
        Write-Log "System code page set to UTF-8" "INFO"
    }

    # NTFS 8.3 short filename generation off (reduces overhead on every file create)
    if ($Script:IsAdmin -and -not $DryRun) {
        fsutil behavior set disable8dot3 1 | Out-Null
        fsutil behavior set memoryusage 2 | Out-Null
        Write-Log "NTFS: 8.3 names disabled, memory usage optimized"
    }

    # Disable memory compression (pointless overhead with 32GB+ RAM)
    if ($Script:IsAdmin -and -not $DryRun) {
        $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
        if ($ramGB -ge 32) {
            try {
                Disable-MMAgent -MemoryCompression -ErrorAction Stop
                Write-Log "Memory compression disabled (${ramGB}GB RAM makes it pure overhead)"
            } catch {
                Write-Log "Memory compression change requires reboot" "INFO"
            }
        }
    }

    # Environment variables for parallel builds
    $envVars = @{
        "NODE_OPTIONS" = "--max-old-space-size=16384"
    }
    foreach ($key in $envVars.Keys) {
        $current = [Environment]::GetEnvironmentVariable($key, "User")
        if (-not $current -and -not $DryRun) {
            [Environment]::SetEnvironmentVariable($key, $envVars[$key], "User")
            Write-Log "Set $key=$($envVars[$key])"
        }
    }

    # Increase ephemeral port range (helps Docker, npm, many concurrent connections)
    if ($Script:IsAdmin -and -not $DryRun) {
        netsh int ipv4 set dynamic tcp start=1025 num=64510 2>$null | Out-Null
        netsh int ipv6 set dynamic tcp start=1025 num=64510 2>$null | Out-Null
        Write-Log "Ephemeral port range expanded (1025-65535)"
    }

    # Reduce TIME_WAIT for faster port recycling
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "TcpTimedWaitDelay" -Value 30
        Write-Log "TCP TIME_WAIT reduced to 30s"
    }

    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: WINDOWS DEFENDER EXCLUSIONS (build speed)
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-DefenderOptimization {
    Write-Host "`n━━━ Defender Dev Exclusions ━━━" -ForegroundColor Magenta
    if (-not $Script:IsAdmin) {
        Write-Log "Skipping Defender exclusions (requires admin)" "SKIP"
        $Script:TweaksSkipped++
        return
    }
    if (-not (Confirm-Action "Add Defender exclusions for dev folders? (massive build speed boost)")) { return }

    # Common dev paths
    $devPaths = @(
        "$env:USERPROFILE\source",
        "$env:USERPROFILE\projects",
        "$env:USERPROFILE\repos",
        "$env:USERPROFILE\.cargo",
        "$env:USERPROFILE\.rustup",
        "$env:USERPROFILE\.nuget",
        "$env:USERPROFILE\go",
        "$env:USERPROFILE\AppData\Local\Temp",
        "$env:USERPROFILE\AppData\Roaming\npm",
        "C:\dev",
        "D:\dev",
        "E:\dev"
    )

    # Common dev processes
    $devProcesses = @(
        "node.exe", "npm.cmd", "pnpm.exe", "yarn.exe", "bun.exe",
        "cargo.exe", "rustc.exe", "rustup.exe",
        "go.exe", "gopls.exe",
        "python.exe", "python3.exe", "pip.exe",
        "dotnet.exe", "msbuild.exe",
        "git.exe", "git-remote-https.exe",
        "Code.exe", "devenv.exe",
        "wt.exe", "WindowsTerminal.exe",
        "pwsh.exe", "powershell.exe"
    )

    if (-not $DryRun) {
        $addedPaths = 0
        foreach ($p in $devPaths) {
            if (Test-Path $p) {
                try {
                    Add-MpPreference -ExclusionPath $p -ErrorAction Stop
                    $addedPaths++
                } catch {}
            }
        }
        Write-Log "Added $addedPaths dev folder exclusions"

        $addedProcs = 0
        foreach ($proc in $devProcesses) {
            try {
                Add-MpPreference -ExclusionProcess $proc -ErrorAction Stop
                $addedProcs++
            } catch {}
        }
        Write-Log "Added $addedProcs dev process exclusions"
    } else {
        Write-Log "(DRY RUN) Would add exclusions for dev folders and processes" "INFO"
    }

    Write-Log "Defender will skip scanning builds, node_modules, etc." "INFO"
    Write-Log "This is the single biggest build-speed improvement on Windows" "INFO"
    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: INPUT
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-InputOptimization {
    Write-Host "`n━━━ Input ━━━" -ForegroundColor Magenta
    if (-not (Confirm-Action "Disable mouse acceleration and accessibility prompts?")) { return }

    # Raw mouse input (no acceleration)
    Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "0" -Type String
    Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Type String
    Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Type String
    Write-Log "Mouse acceleration disabled (raw input)"

    # Kill Sticky Keys / Filter Keys / Toggle Keys prompts
    Set-RegistryValue -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Value "506" -Type String
    Set-RegistryValue -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name "Flags" -Value "122" -Type String
    Set-RegistryValue -Path "HKCU:\Control Panel\Accessibility\ToggleKeys" -Name "Flags" -Value "58" -Type String
    Write-Log "Sticky Keys / Filter Keys / Toggle Keys prompts disabled"

    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: MISC QoL
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-MiscOptimization {
    Write-Host "`n━━━ Misc QoL ━━━" -ForegroundColor Magenta
    if (-not (Confirm-Action "Apply miscellaneous quality-of-life tweaks?")) { return }

    # Dark mode
    $personalize = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    Set-RegistryValue -Path $personalize -Name "AppsUseLightTheme" -Value 0
    Set-RegistryValue -Path $personalize -Name "SystemUsesLightTheme" -Value 0
    Write-Log "Dark mode enabled (system + apps)"

    # Clipboard history (Win+V)
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1
    Write-Log "Clipboard history enabled (Win+V)"

    # Scroll inactive windows
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "MouseWheelRouting" -Value 2
    Write-Log "Scroll inactive windows enabled"

    # Disable snap assist flyout
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SnapAssist" -Value 0
    Write-Log "Snap assist flyout disabled"

    # Foreground app priority
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38
        Write-Log "Foreground app priority boosted"
    }

    # Disable background apps (global switch)
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1
    Write-Log "Background apps globally disabled"

    # Increase icon cache (prevents flickering with many files)
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "Max Cached Icons" -Value "8192" -Type String
        Write-Log "Icon cache increased to 8192"
    }

    # Disable lock screen (boot straight to password)
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen" -Value 1
        Write-Log "Lock screen disabled"
    }

    # Disable automatic maintenance (random defrag/diagnostics)
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" -Name "MaintenanceDisabled" -Value 1
        Write-Log "Automatic maintenance disabled"
    }

    # Disable Windows Error Reporting
    if ($Script:IsAdmin) {
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1
        Write-Log "Windows Error Reporting disabled"
    }

    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: SCHEDULED TASKS
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-TaskCleanup {
    Write-Host "`n━━━ Scheduled Tasks ━━━" -ForegroundColor Magenta
    if (-not $Script:IsAdmin) {
        Write-Log "Skipping scheduled tasks (requires admin)" "SKIP"
        $Script:TweaksSkipped++
        return
    }
    if (-not (Confirm-Action "Disable telemetry scheduled tasks?")) { return }

    foreach ($taskName in $Script:BloatTasks) {
        if ($DryRun) {
            Write-Log "(DRY RUN) Would disable: $(Split-Path $taskName -Leaf)" "INFO"
            continue
        }
        try {
            Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
            Write-Log "Disabled: $(Split-Path $taskName -Leaf)"
        } catch {
            Write-Log "Could not disable $(Split-Path $taskName -Leaf)" "SKIP"
        }
    }
    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: ONEDRIVE REMOVAL
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-OneDriveRemoval {
    Write-Host "`n━━━ OneDrive ━━━" -ForegroundColor Magenta
    $od = Get-Process OneDrive -ErrorAction SilentlyContinue
    $odPkg = Get-AppxPackage -Name "Microsoft.OneDriveSync" -ErrorAction SilentlyContinue
    if (-not $od -and -not $odPkg) {
        Write-Log "OneDrive not found" "SKIP"
        return
    }
    if (-not (Confirm-Action "Uninstall OneDrive?")) { return }

    if (-not $DryRun) {
        Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue

        $setupPath = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
        if (-not (Test-Path $setupPath)) { $setupPath = "$env:SystemRoot\System32\OneDriveSetup.exe" }

        if (Test-Path $setupPath) {
            Start-Process $setupPath -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue
        } else {
            $odPkg | Remove-AppxPackage -ErrorAction SilentlyContinue
        }

        # Clean startup entry
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue

        # Clean Explorer namespace
        Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace" -ErrorAction SilentlyContinue | ForEach-Object {
            $val = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).'(default)'
            if ($val -match "OneDrive") {
                Remove-Item $_.PSPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Write-Log "OneDrive uninstalled and cleaned up"
    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: WSL2 OPTIMIZATION
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-WSLOptimization {
    Write-Host "`n━━━ WSL2 ━━━" -ForegroundColor Magenta
    $wsl = Get-Command wsl -ErrorAction SilentlyContinue
    if (-not $wsl) {
        Write-Log "WSL not installed" "SKIP"
        return
    }
    if (-not (Confirm-Action "Optimize WSL2 configuration?")) { return }

    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $wslRam = [math]::Floor($ramGB / 2)
    $cpuCount = (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors

    $wslConfig = @"
[wsl2]
memory=${wslRam}GB
processors=$cpuCount
swap=0
localhostForwarding=true

[experimental]
autoMemoryReclaim=dropcache
sparseVhd=true
"@

    $wslConfigPath = "$env:USERPROFILE\.wslconfig"
    if (-not $DryRun) {
        $wslConfig | Out-File -FilePath $wslConfigPath -Encoding UTF8 -Force
        Write-Log "WSL2: ${wslRam}GB RAM, $cpuCount cores, no swap, sparse VHD, auto memory reclaim"
    } else {
        Write-Log "(DRY RUN) Would write .wslconfig with ${wslRam}GB RAM, $cpuCount cores" "INFO"
    }
    $Script:TweaksApplied++
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

if ($Help) {
    Show-Help
    return
}

Show-Banner

# Create restore point (admin only, best-effort)
if ($Script:IsAdmin -and -not $DryRun) {
    Write-Host "Creating System Restore point..." -ForegroundColor Gray
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "windows-perf pre-optimization" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Log "Restore point created" "OK"
    } catch {
        Write-Log "Restore point skipped (may already exist today)" "WARN"
    }
}

# Run modules
$modules = @(
    @{Name="power";     Fn={Invoke-PowerOptimization}},
    @{Name="services";  Fn={Invoke-ServiceOptimization}},
    @{Name="network";   Fn={Invoke-NetworkOptimization}},
    @{Name="privacy";   Fn={Invoke-PrivacyOptimization}},
    @{Name="ui";        Fn={Invoke-UIOptimization}},
    @{Name="explorer";  Fn={Invoke-ExplorerOptimization}},
    @{Name="taskbar";   Fn={Invoke-TaskbarOptimization}},
    @{Name="gaming";    Fn={Invoke-GamingOptimization}},
    @{Name="memory";    Fn={Invoke-MemoryOptimization}},
    @{Name="bloatware"; Fn={Invoke-BloatwareRemoval}},
    @{Name="onedrive";  Fn={Invoke-OneDriveRemoval}},
    @{Name="developer"; Fn={Invoke-DeveloperOptimization}},
    @{Name="defender";  Fn={Invoke-DefenderOptimization}},
    @{Name="input";     Fn={Invoke-InputOptimization}},
    @{Name="misc";      Fn={Invoke-MiscOptimization}},
    @{Name="tasks";     Fn={Invoke-TaskCleanup}},
    @{Name="wsl";       Fn={Invoke-WSLOptimization}}
)

foreach ($mod in $modules) {
    if (ShouldRun $mod.Name) {
        & $mod.Fn
    } else {
        Write-Log "Module '$($mod.Name)' skipped by user" "SKIP"
    }
}

# Summary
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║              OPTIMIZATION COMPLETE                  ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Applied : $Script:TweaksApplied modules" -ForegroundColor Green
Write-Host "  Skipped : $Script:TweaksSkipped modules" -ForegroundColor Yellow
Write-Host "  Failed  : $Script:TweaksFailed items" -ForegroundColor $(if ($Script:TweaksFailed -gt 0) { "Red" } else { "Green" })
Write-Host "  Log     : $Script:LogFile" -ForegroundColor Gray
Write-Host ""

if (-not $DryRun) {
    Write-Host "  RESTART REQUIRED for full effect." -ForegroundColor Yellow
    Write-Host "  Changes active after reboot: GPU scheduling, pagefile," -ForegroundColor Gray
    Write-Host "  context menu, services, hibernation, code pages." -ForegroundColor Gray
    Write-Host ""
}
