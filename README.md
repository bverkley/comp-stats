# System Legacy Capture

A comprehensive bash script that captures detailed hardware information, system configuration, and performance benchmarks from a Linux system. Perfect for preserving a snapshot of your machine before decommissioning, upgrading, or just for nostalgia.

## Features

The script captures and organizes data into both raw files (for archival) and a human-readable report:

### Hardware Information
- **CPU**: Model, cores, threads, cache, frequency scaling
- **Memory**: Total RAM, usage, module details (speeds, manufacturers, part numbers)
- **Storage**: All drives with model/serial, partition layout, usage, SMART health data
- **GPU**: Graphics cards, NVIDIA details (via nvidia-smi)
- **PCI Devices**: Full PCI bus enumeration
- **USB Devices**: All connected USB devices
- **Motherboard/BIOS**: DMI data including BIOS version, board info

### Performance Benchmarks
- **Disk Benchmarks**: hdparm timing tests for both SATA and NVMe drives
- **SMART Data**: Drive health, power-on hours, temperature history

### System Configuration
- **Kernel**: Version, boot parameters, loaded modules, full kernel config
- **Bootloader**: GRUB configuration
- **Network**: Interfaces, IP addresses, routing table
- **Sensors**: Temperature readings from CPU, drives, GPU

### Gentoo Linux Extras
All Gentoo-specific data is organized in a `raw/gentoo/` subfolder:
- World file (`/var/lib/portage/world`)
- Portage configuration (`emerge --info`, `make.conf`)
- Installed packages list
- Current profile
- Full `/etc/portage/package.*` directory structures preserved

## Requirements

### Required
- Bash 4.0+
- Linux system

### Optional (script handles missing tools gracefully)
| Tool | Package | Purpose |
|------|---------|---------|
| hdparm | sys-apps/hdparm | Disk benchmarks |
| smartctl | sys-apps/smartmontools | SMART health data |
| nvme | sys-apps/nvme-cli | NVMe drive info |
| sensors | sys-apps/lm-sensors | Temperature readings |
| lspci | sys-apps/pciutils | PCI device listing |
| lsusb | sys-apps/usbutils | USB device listing |
| dmidecode | sys-apps/dmidecode | BIOS/motherboard info |
| qlist | app-portage/gentoolkit | Gentoo package listing |

## Installation

```bash
git clone https://github.com/bverkley/system-legacy-capture.git
cd system-legacy-capture
chmod +x capture-system.sh
```

## Usage

For complete capture including benchmarks and SMART data, run with sudo:

```bash
sudo ./capture-system.sh
```

The script can also run without root, but some captures will be skipped:

```bash
./capture-system.sh
```

### Output

The script creates a timestamped directory:

```
<hostname>-YYYY-MM-DD/
├── raw/                              # Raw command outputs
│   ├── cpuinfo.txt
│   ├── lscpu.txt
│   ├── meminfo.txt
│   ├── dmidecode.txt
│   ├── lsblk.txt
│   ├── hdparm-sda.txt
│   ├── smartctl-sda.txt
│   ├── kernel-config.txt
│   ├── grub.cfg
│   ├── gentoo/                       # Gentoo-specific (if applicable)
│   │   ├── world.txt
│   │   ├── make.conf.txt
│   │   ├── package.use/
│   │   └── ...
│   └── ... (40+ files)
└── <hostname>-report-YYYY-MM-DD.txt  # Human-readable report
```

### Sample Report Output

```
================================================================================
                    SYSTEM LEGACY REPORT: myhost
                    Generated: 2026-01-17 14:30:00
================================================================================

SYSTEM OVERVIEW
---------------
Hostname:       myhost
OS:             Gentoo Linux
Kernel:         Linux myhost 6.12.41-gentoo x86_64
Uptime:         up 73 days, 14:40

CPU
---
  Model name:      Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz
  CPU(s):          12
  Thread(s):       2 per core
  Core(s):         6 per socket

MEMORY
------
                 total        used        free
  Mem:           125Gi        31Gi        13Gi

DISK BENCHMARKS (hdparm)
------------------------
Device: /dev/sda
  Timing cached reads:   25000 MB in  2.00 seconds = 12500.00 MB/sec
  Timing buffered disk reads: 600 MB in  3.01 seconds = 199.34 MB/sec

...
```

## Privacy Notice

The captured data may contain:
- Hardware serial numbers
- Network IP addresses
- Hostnames and usernames (from login history)

Review the output before sharing publicly.

## Contributing

Contributions welcome! Feel free to open issues or submit pull requests.

## Credits

- **Idea & Direction**: [Brian Verkley](https://github.com/bverkley)
- **Code Generation**: Built with [Cursor IDE](https://cursor.sh) and [Claude Opus 4.5](https://anthropic.com) (Anthropic)

## License

MIT License - see [LICENSE](LICENSE) for details.
