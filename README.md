# windows-perf

One-shot Windows 11 performance, privacy, and quality-of-life optimization. Designed for developers and power users who want their machine running at full tilt without Microsoft's bloat getting in the way.

Tested on a Ryzen 9 5950X / 128GB / RTX 3090, but works on any Windows 11 machine.

## What it does

| Module | What changes |
|---|---|
| **power** | Ultimate Performance plan, core parking off, idle states off, USB/PCI-E power management off |
| **services** | Disables 10 bloat services: telemetry, Superfetch, Search indexer, geolocation, fax, etc. |
| **network** | Cloudflare DNS, Nagle off, TCP optimization, RSS/RSC, network throttling off, expanded port range |
| **privacy** | Telemetry to zero, advertising ID off, Bing removed from Start, Cortana off, Copilot blocked, Edge nags killed, silent app installs blocked |
| **ui** | Zero menu delay, faster shutdown, reduced animations (keeps ClearType), Aero Peek off |
| **explorer** | File extensions visible, hidden files shown, classic right-click menu, full path in title, "This PC" default |
| **taskbar** | Removes Widgets, Task View, Chat, Copilot, Search box |
| **gaming** | HW GPU scheduling, Game Mode on, Game Bar DVR off, NVIDIA max performance, TDR timeout increased, GPU preemption off |
| **memory** | Pagefile off (64GB+ RAM), TRIM on, NTFS last access off, large system cache, hibernation off, memory compression off |
| **bloatware** | Removes 30+ preinstalled apps (Copilot, Clipchamp, Bing News/Weather, Solitaire, Skype, Teams, etc.) and blocks reinstall |
| **onedrive** | Full OneDrive removal and Explorer cleanup |
| **developer** | Git optimized (fsmonitor, histogram diff, parallel fetch, rerere), dev mode, long paths, UTF-8, NTFS 8.3 off, expanded port range, NODE_OPTIONS |
| **defender** | Adds Defender exclusions for dev folders and processes (20-60% build speed improvement) |
| **input** | Mouse acceleration off (raw input), Sticky/Filter/Toggle Keys prompts killed |
| **misc** | Dark mode, clipboard history, background apps off, lock screen off, auto maintenance off |
| **tasks** | Disables telemetry/CEIP/feedback/diagnostic scheduled tasks |
| **wsl** | WSL2 memory/CPU tuning, sparse VHD, auto memory reclaim |
| **tools** | Installs power tools via winget: Everything, Windhawk, QuickLook, ShareX, EarTrumpet, Flow Launcher, HWiNFO, TranslucentTB, UniGetUI, AutoHotkey, Starship |
| **terminal** | Starship prompt config, JetBrains Mono Nerd Font, PSReadLine enhancements, Windows Terminal acrylic + font, TranslucentTB config, left-aligned taskbar |

## Quick start

```powershell
# Download and run (admin recommended)
irm https://raw.githubusercontent.com/dougwithseismic/windows-perf/main/windows-perf.ps1 -OutFile windows-perf.ps1
Set-ExecutionPolicy Bypass -Scope Process -Force
.\windows-perf.ps1
```

Or clone and run:

```powershell
git clone https://github.com/withseismic/windows-perf.git
cd windows-perf
.\windows-perf.ps1
```

## Usage

```powershell
# Run everything (recommended - run as admin)
.\windows-perf.ps1

# Interactive mode - prompts before each category
.\windows-perf.ps1 -Interactive

# Preview what would change without touching anything
.\windows-perf.ps1 -DryRun

# Run specific modules only
.\windows-perf.ps1 -Only power,network,privacy

# Run everything except bloatware removal
.\windows-perf.ps1 -Skip bloatware,onedrive

# Show help
.\windows-perf.ps1 -Help
```

## Admin vs non-admin

The script works without admin, but many optimizations require elevation:

| Needs Admin | No Admin Needed |
|---|---|
| Power plan | UI speed / animations |
| Services | File Explorer settings |
| DNS / TCP tuning | Taskbar cleanup |
| Defender exclusions | Privacy (user-level) |
| Memory / disk | Classic context menu |
| Scheduled tasks | Dark mode / clipboard |
| GPU scheduling | Git config |
| NTFS optimization | Mouse / input |
| Bloatware deprovisioning | Bloatware removal (user) |

Run as admin for full effect:
```powershell
Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File .\windows-perf.ps1" -Verb RunAs
```

## Safety

- Creates a **System Restore point** before making any changes
- Logs every action to `~/Desktop/windows-perf-*.log`
- `-DryRun` flag previews all changes without applying
- `-Interactive` flag asks before each module
- Only removes apps from a curated safe list (never touches Store, Calculator, Photos, Terminal, etc.)
- Every registry path and value is documented in the source

## What it keeps

Calculator, Camera, Photos, Paint, Notepad, Terminal, Store, Snipping Tool, Sticky Notes, Xbox gaming stack (needed for Game Pass), WSL, PowerToys, WinDbg, NVIDIA Control Panel, Windows Security.

## Reboot required

After running, restart for these changes to take full effect:
- GPU hardware scheduling
- Pagefile removal
- Classic context menu
- Service disables
- Memory compression
- Code page changes
- Core parking

## FAQ

**Will this break anything?**
No. Every tweak is conservative and well-tested. The bloatware list only includes genuinely unnecessary apps. Services disabled are all non-essential. If something doesn't work for your setup, run with `-Interactive` and skip that module.

**Can I undo this?**
Yes. The script creates a System Restore point before changes. Go to System Properties > System Protection > System Restore to roll back.

**Why disable Superfetch/SysMain?**
With an SSD (especially NVMe), Superfetch provides negligible benefit while consuming CPU cycles and RAM. It was designed for the HDD era.

**Why disable Windows Search?**
The indexer is a persistent CPU and disk hog. Use [Everything](https://www.voidtools.com/) instead - it's instant and uses a fraction of the resources.

**Why add Defender exclusions?**
Windows Defender scans every file your build tools read and write. During a `npm install` or `cargo build`, that's thousands of files. Excluding dev folders and build tool processes can cut build times by 20-60%.

**I use OneDrive / Teams / Outlook for work**
Run with `-Skip bloatware,onedrive` or use `-Interactive` mode to selectively keep what you need.

## License

MIT
