# Project Status

## Version 1.0 - Released 2026-01-17

### Summary
Comprehensive system snapshot script that captures hardware information, system configuration,
performance benchmarks, and Gentoo-specific details. Outputs both raw data files and a 
human-readable report.

### Features Implemented
- Core system info (uname, uptime, os-release)
- CPU details (cpuinfo, lscpu)
- Memory info (meminfo, free, dmidecode)
- Storage with benchmarks (lsblk, df, hdparm, smartctl, nvme)
- PCI/USB device enumeration
- GPU info (nvidia-smi support)
- Network configuration
- Sensor readings (temperatures)
- Kernel config and GRUB bootloader config
- Gentoo-specific captures in dedicated subfolder (world file, portage configs, packages)

### Technical Highlights
- Graceful error handling (continues on failures, logs warnings)
- Skips 0-byte drives (empty card reader slots)
- Separate handling for SATA vs NVMe drives
- Preserves Gentoo /etc/portage directory structures
- Works with or without root (partial capture without sudo)

## Release History
- v1.0 (2026-01-17): Initial release
