# Technical Specifications

## Purpose
This project creates a comprehensive snapshot of a Linux system's hardware and configuration
before decommissioning. The goal is to preserve both raw data for technical reference and
a human-readable report for nostalgia and quick reference.

## Script Requirements

### Environment
- Bash 4.0+
- Root/sudo access for privileged commands (dmidecode, hdparm, smartctl, fdisk)
- Gentoo Linux (for Gentoo-specific captures)

### Dependencies (Optional - script handles missing gracefully)
- hdparm: Disk benchmarking
- smartmontools: SMART data (smartctl)
- nvme-cli: NVMe drive info
- lm_sensors: Temperature readings
- pciutils: lspci
- usbutils: lsusb
- app-portage/gentoolkit: qlist for package listing

## Output Structure

```
<hostname>-YYYY-MM-DD/
├── raw/
│   ├── uname.txt
│   ├── hostnamectl.txt
│   ├── os-release.txt
│   ├── uptime.txt
│   ├── cpuinfo.txt
│   ├── lscpu.txt
│   ├── meminfo.txt
│   ├── free.txt
│   ├── dmidecode.txt
│   ├── dmidecode-memory.txt
│   ├── lsblk.txt
│   ├── df.txt
│   ├── fdisk.txt
│   ├── hdparm-<dev>.txt
│   ├── smartctl-<dev>.txt
│   ├── nvme-list.txt
│   ├── nvme-smart-<dev>.txt
│   ├── lspci.txt
│   ├── lsusb.txt
│   ├── gpu-info.txt
│   ├── nvidia-smi.txt (if available)
│   ├── ip-addr.txt
│   ├── ip-route.txt
│   ├── sensors.txt
│   ├── lsmod.txt
│   ├── cmdline.txt
│   ├── kernel-config.txt
│   ├── grub.cfg
│   ├── last-logins.txt
│   └── gentoo/                    # Gentoo-specific (if detected)
│       ├── gentoo-release.txt
│       ├── emerge-info.txt
│       ├── installed-packages.txt
│       ├── world.txt
│       ├── make.conf.txt
│       ├── eselect-profile.txt
│       ├── package.use/
│       ├── package.accept_keywords/
│       ├── package.keywords/
│       ├── package.mask/
│       ├── package.unmask
│       ├── package.license
│       ├── package.env/
│       └── env/
└── <hostname>-report-YYYY-MM-DD.txt
```

## Report Format

The human-readable report uses plain text with clear section headers and formatting:

```
================================================================================
                    SYSTEM LEGACY REPORT: <hostname>
                    Generated: YYYY-MM-DD HH:MM:SS
================================================================================

SYSTEM OVERVIEW
---------------
Hostname:       <hostname>
OS:             Gentoo Linux
Kernel:         <kernel version>
Architecture:   x86_64
Uptime:         <uptime>

CPU
---
Model:          <cpu model>
Cores:          <physical cores>
Threads:        <logical processors>
...
```

## Error Handling

- Missing commands are detected and logged with warnings
- Script continues even if some captures fail (no "die on first error")
- All errors are logged to stderr and included in the report warnings section
- 0-byte drives (empty card readers) are automatically skipped

## Security Considerations

- Some raw data may contain serial numbers and hardware identifiers
- Network config may reveal IP addresses
- Consider privacy before sharing the output
