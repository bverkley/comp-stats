#!/bin/bash
# capture-system.sh - Comprehensive system snapshot script
# 
# This script captures detailed hardware information, system configuration, and
# performance benchmarks before decommissioning a Linux system. The goal is to 
# preserve both raw data for technical reference and a human-readable report for
# nostalgia and quick reference.
#
# The script creates an output directory named <hostname>-<date> containing:
#   - raw/: Directory with raw command outputs for archival
#   - <hostname>-report-<date>.txt: Formatted human-readable report
#
# Some commands require root access (dmidecode, hdparm, smartctl, fdisk).
# Run with sudo for complete capture, or run as regular user for partial capture.

# Don't use set -e because we want to continue capturing even if individual commands fail
# We log errors and continue rather than dying on first failure
set -uo pipefail

# Configuration
HOSTNAME=$(hostname)
DATE=$(date +%Y-%m-%d)
DATETIME=$(date '+%Y-%m-%d %H:%M:%S')
OUTPUT_DIR="${HOSTNAME}-${DATE}"
RAW_DIR="${OUTPUT_DIR}/raw"
REPORT="${OUTPUT_DIR}/${HOSTNAME}-report-${DATE}.txt"

# Track warnings for missing tools
WARNINGS=()

# Helper function to log messages to both console and report
log() {
    echo "$1"
}

# Helper function to add a warning
warn() {
    local msg="WARNING: $1"
    echo "$msg" >&2
    WARNINGS+=("$msg")
}

# Helper function to check if a command exists
cmd_exists() {
    command -v "$1" &>/dev/null
}

# Helper function to run a command and save output, handling missing commands gracefully
# Arguments: output_file command [args...]
capture_cmd() {
    local outfile="$1"
    shift
    local cmd="$1"
    local exit_code
    
    if ! cmd_exists "$cmd"; then
        warn "Command '$cmd' not found, skipping capture to $outfile"
        echo "Command '$cmd' not available on this system" > "${RAW_DIR}/${outfile}"
        return 1
    fi
    
    log "  Capturing: $*"
    # Run the command and capture exit code before it gets overwritten
    "$@" > "${RAW_DIR}/${outfile}" 2>&1
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        warn "Command '$*' failed (exit code $exit_code)"
        return 1
    fi
    return 0
}

# Helper function to copy a file if it exists
capture_file() {
    local src="$1"
    local dest="$2"
    
    if [[ -f "$src" ]]; then
        log "  Capturing: $src"
        if ! cp "$src" "${RAW_DIR}/${dest}" 2>&1; then
            warn "Failed to copy '$src'"
            return 1
        fi
        return 0
    else
        warn "File '$src' not found"
        echo "File '$src' not found on this system" > "${RAW_DIR}/${dest}"
        return 1
    fi
}

# Create output directory structure
setup_directories() {
    log "Creating output directory: ${OUTPUT_DIR}"
    mkdir -p "${RAW_DIR}"
}

# Capture core system information
capture_core_system() {
    log ""
    log "=== Capturing Core System Information ==="
    
    capture_cmd "uname.txt" uname -a
    capture_cmd "hostnamectl.txt" hostnamectl || true
    capture_file "/etc/os-release" "os-release.txt"
    capture_cmd "uptime.txt" uptime
    capture_cmd "date.txt" date
    capture_cmd "last-logins.txt" last -20 || true
    capture_cmd "who.txt" who -a || true
}

# Capture CPU information
capture_cpu() {
    log ""
    log "=== Capturing CPU Information ==="
    
    capture_file "/proc/cpuinfo" "cpuinfo.txt"
    capture_cmd "lscpu.txt" lscpu
}

# Capture memory information
capture_memory() {
    log ""
    log "=== Capturing Memory Information ==="
    
    capture_file "/proc/meminfo" "meminfo.txt"
    capture_cmd "free.txt" free -h
    
    # dmidecode requires root
    if [[ $EUID -eq 0 ]]; then
        capture_cmd "dmidecode.txt" dmidecode
        capture_cmd "dmidecode-memory.txt" dmidecode -t memory
    else
        warn "Running as non-root, skipping dmidecode (memory details)"
    fi
}

# Capture storage information and run benchmarks
capture_storage() {
    log ""
    log "=== Capturing Storage Information ==="
    
    capture_cmd "lsblk.txt" lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,SERIAL,MOUNTPOINT
    capture_cmd "df.txt" df -h
    capture_cmd "mount.txt" mount
    
    # fdisk requires root
    if [[ $EUID -eq 0 ]]; then
        capture_cmd "fdisk.txt" fdisk -l
    else
        warn "Running as non-root, skipping fdisk -l"
    fi
    
    # Get list of block devices for benchmarking (only actual disks, not partitions)
    # We separate SATA/SAS drives from NVMe since they use different tools
    # Filter out 0-byte drives (like empty card reader slots that show up as devices)
    local sata_devices nvme_devices
    sata_devices=$(lsblk -dnpo NAME,TYPE,SIZE | awk '$2=="disk" && $3!="0B" {print $1}' | grep -v nvme || true)
    nvme_devices=$(lsblk -dnpo NAME,TYPE,SIZE | awk '$2=="disk" && $3!="0B" {print $1}' | grep nvme || true)
    
    log ""
    log "=== Running SATA/SAS Disk Benchmarks ==="
    
    # hdparm only works on SATA/SAS drives, not NVMe
    for dev in $sata_devices; do
        local devname
        devname=$(basename "$dev")
        
        # hdparm benchmark (requires root for timing tests)
        if cmd_exists hdparm; then
            if [[ $EUID -eq 0 ]]; then
                log "  Benchmarking $dev with hdparm..."
                capture_cmd "hdparm-${devname}.txt" hdparm -itT "$dev" || true
            else
                # Can still get identity info without root on some systems
                log "  Capturing $dev identity info with hdparm (no benchmarks without root)..."
                capture_cmd "hdparm-${devname}.txt" hdparm -i "$dev" || true
            fi
        else
            warn "hdparm not found, skipping disk benchmarks"
        fi
        
        # SMART data (requires root)
        if cmd_exists smartctl; then
            if [[ $EUID -eq 0 ]]; then
                log "  Capturing SMART data for $dev..."
                capture_cmd "smartctl-${devname}.txt" smartctl -a "$dev" || true
            else
                warn "Running as non-root, skipping smartctl for $dev"
            fi
        else
            warn "smartctl not found, skipping SMART data"
        fi
    done
    
    # NVMe specific captures
    if [[ -n "$nvme_devices" ]]; then
        log ""
        log "=== Capturing NVMe Drive Information ==="
        
        if cmd_exists nvme; then
            capture_cmd "nvme-list.txt" nvme list || true
            
            for ndev in $nvme_devices; do
                local ndevname
                ndevname=$(basename "$ndev")
                
                # NVMe smart-log requires root
                if [[ $EUID -eq 0 ]]; then
                    log "  Capturing NVMe smart-log for $ndev..."
                    capture_cmd "nvme-smart-${ndevname}.txt" nvme smart-log "$ndev" || true
                else
                    warn "Running as non-root, skipping nvme smart-log for $ndev"
                fi
                
                # smartctl also works on NVMe and provides useful info
                if cmd_exists smartctl; then
                    if [[ $EUID -eq 0 ]]; then
                        log "  Capturing SMART data for $ndev..."
                        capture_cmd "smartctl-${ndevname}.txt" smartctl -a "$ndev" || true
                    else
                        warn "Running as non-root, skipping smartctl for $ndev"
                    fi
                fi
                
                # hdparm timing tests (-tT) work on NVMe even though identity (-i) doesn't
                if cmd_exists hdparm; then
                    if [[ $EUID -eq 0 ]]; then
                        log "  Benchmarking $ndev with hdparm..."
                        capture_cmd "hdparm-${ndevname}.txt" hdparm -tT "$ndev" || true
                    else
                        warn "Running as non-root, skipping hdparm benchmarks for $ndev"
                    fi
                fi
            done
        else
            warn "nvme-cli not found, skipping NVMe-specific captures"
        fi
    fi
}

# Capture PCI and USB devices
capture_pci_usb() {
    log ""
    log "=== Capturing PCI and USB Devices ==="
    
    capture_cmd "lspci.txt" lspci -vvv || capture_cmd "lspci.txt" lspci -v || capture_cmd "lspci.txt" lspci
    capture_cmd "lsusb.txt" lsusb -v || capture_cmd "lsusb.txt" lsusb || true
}

# Capture GPU information
capture_gpu() {
    log ""
    log "=== Capturing GPU Information ==="
    
    # Extract VGA info from lspci
    if cmd_exists lspci; then
        lspci | grep -iE 'vga|3d|display' > "${RAW_DIR}/gpu-info.txt" 2>&1 || true
    fi
    
    # NVIDIA specific
    if cmd_exists nvidia-smi; then
        log "  Capturing NVIDIA GPU info..."
        capture_cmd "nvidia-smi.txt" nvidia-smi
        capture_cmd "nvidia-smi-query.txt" nvidia-smi -q || true
    fi
    
    # AMD specific
    if cmd_exists radeontop; then
        capture_cmd "radeontop.txt" radeontop -d - -l 1 || true
    fi
}

# Capture network configuration
capture_network() {
    log ""
    log "=== Capturing Network Configuration ==="
    
    capture_cmd "ip-addr.txt" ip addr
    capture_cmd "ip-route.txt" ip route
    capture_cmd "ip-link.txt" ip link
    
    # Also try older commands if available
    capture_cmd "ifconfig.txt" ifconfig -a || true
}

# Capture sensor readings
capture_sensors() {
    log ""
    log "=== Capturing Sensor Readings ==="
    
    if cmd_exists sensors; then
        capture_cmd "sensors.txt" sensors
    else
        warn "lm_sensors not installed, skipping temperature readings"
    fi
}

# Capture kernel information
capture_kernel() {
    log ""
    log "=== Capturing Kernel Information ==="
    
    capture_cmd "lsmod.txt" lsmod
    capture_file "/proc/cmdline" "cmdline.txt"
    capture_file "/proc/version" "version.txt"
    
    # Try to find and capture kernel config
    local kver
    kver=$(uname -r)
    if [[ -f "/proc/config.gz" ]]; then
        log "  Capturing kernel config from /proc/config.gz..."
        zcat /proc/config.gz > "${RAW_DIR}/kernel-config.txt" 2>&1 || true
    elif [[ -f "/boot/config-${kver}" ]]; then
        capture_file "/boot/config-${kver}" "kernel-config.txt"
    else
        warn "Kernel config not found"
    fi
    
    # Capture GRUB configuration
    if [[ -f "/boot/grub/grub.cfg" ]]; then
        capture_file "/boot/grub/grub.cfg" "grub.cfg"
    elif [[ -f "/boot/grub2/grub.cfg" ]]; then
        capture_file "/boot/grub2/grub.cfg" "grub.cfg"
    else
        log "  GRUB config not found (may be using different bootloader)"
    fi
}

# Capture Gentoo-specific information
# All Gentoo data is stored in raw/gentoo/ subfolder to keep it organized
# and make it clear this section only runs on Gentoo systems
capture_gentoo() {
    log ""
    log "=== Capturing Gentoo-Specific Information ==="
    
    # Check if this is a Gentoo system
    if [[ ! -f /etc/gentoo-release ]]; then
        log "  Not a Gentoo system, skipping Gentoo-specific captures"
        return 0
    fi
    
    # Create Gentoo-specific subdirectory
    local GENTOO_DIR="${RAW_DIR}/gentoo"
    mkdir -p "${GENTOO_DIR}"
    
    # Helper to capture to gentoo subfolder
    capture_gentoo_cmd() {
        local outfile="$1"
        shift
        local cmd="$1"
        local exit_code
        
        if ! cmd_exists "$cmd"; then
            warn "Command '$cmd' not found, skipping capture to gentoo/$outfile"
            echo "Command '$cmd' not available on this system" > "${GENTOO_DIR}/${outfile}"
            return 1
        fi
        
        log "  Capturing: $*"
        "$@" > "${GENTOO_DIR}/${outfile}" 2>&1
        exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            warn "Command '$*' failed (exit code $exit_code)"
            return 1
        fi
        return 0
    }
    
    # Helper to copy file to gentoo subfolder
    capture_gentoo_file() {
        local src="$1"
        local dest="$2"
        
        if [[ -f "$src" ]]; then
            log "  Capturing: $src"
            if ! cp "$src" "${GENTOO_DIR}/${dest}" 2>&1; then
                warn "Failed to copy '$src'"
                return 1
            fi
            return 0
        else
            warn "File '$src' not found"
            return 1
        fi
    }
    
    # Helper to copy directory to gentoo subfolder, preserving structure
    capture_gentoo_dir() {
        local src="$1"
        local dest="$2"
        
        if [[ -d "$src" ]]; then
            log "  Capturing directory: $src"
            if ! cp -r "$src" "${GENTOO_DIR}/${dest}" 2>&1; then
                warn "Failed to copy directory '$src'"
                return 1
            fi
            return 0
        elif [[ -f "$src" ]]; then
            # It's a file, not a directory
            log "  Capturing file: $src"
            if ! cp "$src" "${GENTOO_DIR}/${dest}" 2>&1; then
                warn "Failed to copy '$src'"
                return 1
            fi
            return 0
        else
            log "  Not found: $src (skipping)"
            return 1
        fi
    }
    
    # Basic Gentoo info
    capture_gentoo_file "/etc/gentoo-release" "gentoo-release.txt"
    
    # Portage info
    if cmd_exists emerge; then
        capture_gentoo_cmd "emerge-info.txt" emerge --info
    fi
    
    # Installed packages
    if cmd_exists qlist; then
        log "  Capturing installed packages with qlist..."
        capture_gentoo_cmd "installed-packages.txt" qlist -Iv
    elif cmd_exists eix; then
        log "  Capturing installed packages with eix..."
        capture_gentoo_cmd "installed-packages.txt" eix -I --format '<installedversions:NAMEVERSION>' || true
    elif cmd_exists emerge; then
        log "  Capturing installed packages with emerge..."
        capture_gentoo_cmd "installed-packages.txt" emerge -ep @world || true
    fi
    
    # World file - the list of explicitly installed packages
    capture_gentoo_file "/var/lib/portage/world" "world.txt"
    
    # Main portage configuration
    capture_gentoo_file "/etc/portage/make.conf" "make.conf.txt"
    
    # Portage package configuration directories - preserve full structure
    # These can be either files or directories depending on user preference
    capture_gentoo_dir "/etc/portage/package.use" "package.use"
    capture_gentoo_dir "/etc/portage/package.accept_keywords" "package.accept_keywords"
    capture_gentoo_dir "/etc/portage/package.keywords" "package.keywords"
    capture_gentoo_dir "/etc/portage/package.mask" "package.mask"
    capture_gentoo_dir "/etc/portage/package.unmask" "package.unmask"
    capture_gentoo_dir "/etc/portage/package.license" "package.license"
    capture_gentoo_dir "/etc/portage/package.env" "package.env"
    capture_gentoo_dir "/etc/portage/env" "env"
    
    # Profile
    if cmd_exists eselect; then
        capture_gentoo_cmd "eselect-profile.txt" eselect profile show
    fi
    
    log "  Gentoo data saved to: ${GENTOO_DIR}/"
}

# Generate the human-readable report
generate_report() {
    log ""
    log "=== Generating Human-Readable Report ==="
    
    {
        # Header
        echo "================================================================================"
        echo "                    SYSTEM LEGACY REPORT: ${HOSTNAME}"
        echo "                    Generated: ${DATETIME}"
        echo "================================================================================"
        echo ""
        
        # System Overview
        echo "SYSTEM OVERVIEW"
        echo "---------------"
        echo "Hostname:       ${HOSTNAME}"
        if [[ -f "${RAW_DIR}/os-release.txt" ]]; then
            local os_name os_version
            os_name=$(grep -E '^NAME=' "${RAW_DIR}/os-release.txt" | cut -d= -f2 | tr -d '"' || echo "Unknown")
            os_version=$(grep -E '^VERSION=' "${RAW_DIR}/os-release.txt" | cut -d= -f2 | tr -d '"' || echo "")
            echo "OS:             ${os_name} ${os_version}"
        fi
        if [[ -f "${RAW_DIR}/uname.txt" ]]; then
            echo "Kernel:         $(cat "${RAW_DIR}/uname.txt")"
        fi
        if [[ -f "${RAW_DIR}/uptime.txt" ]]; then
            echo "Uptime:         $(cat "${RAW_DIR}/uptime.txt")"
        fi
        echo ""
        
        # CPU Summary
        echo "CPU"
        echo "---"
        if [[ -f "${RAW_DIR}/lscpu.txt" ]]; then
            grep -E '^(Model name|CPU\(s\)|Thread|Core|Socket|CPU max MHz|CPU min MHz|Cache|Architecture)' "${RAW_DIR}/lscpu.txt" | sed 's/^/  /' || true
        fi
        echo ""
        
        # Memory Summary
        echo "MEMORY"
        echo "------"
        if [[ -f "${RAW_DIR}/free.txt" ]]; then
            echo "Current Usage:"
            cat "${RAW_DIR}/free.txt" | sed 's/^/  /'
        fi
        echo ""
        if [[ -f "${RAW_DIR}/dmidecode-memory.txt" ]] && [[ -s "${RAW_DIR}/dmidecode-memory.txt" ]]; then
            echo "Physical Memory Modules:"
            # Extract key memory info from dmidecode
            grep -E '^\s*(Size|Type|Speed|Manufacturer|Part Number|Configured|Locator):' "${RAW_DIR}/dmidecode-memory.txt" | grep -v "No Module Installed" | head -40 | sed 's/^/  /' || true
        fi
        echo ""
        
        # Storage Summary
        echo "STORAGE"
        echo "-------"
        if [[ -f "${RAW_DIR}/lsblk.txt" ]]; then
            echo "Block Devices:"
            cat "${RAW_DIR}/lsblk.txt" | sed 's/^/  /'
        fi
        echo ""
        if [[ -f "${RAW_DIR}/df.txt" ]]; then
            echo "Disk Usage:"
            cat "${RAW_DIR}/df.txt" | sed 's/^/  /'
        fi
        echo ""
        
        # Disk Benchmarks
        echo "DISK BENCHMARKS (hdparm)"
        echo "------------------------"
        for f in "${RAW_DIR}"/hdparm-*.txt; do
            if [[ -f "$f" ]] && ! grep -q "not available\|not found" "$f"; then
                local devname
                devname=$(basename "$f" .txt | sed 's/hdparm-//')
                echo "Device: /dev/${devname}"
                # Extract timing results
                grep -E '(Timing|Model|Serial|reads|cached)' "$f" | sed 's/^/  /' || true
                echo ""
            fi
        done
        
        # SMART Summary
        echo "DRIVE HEALTH (SMART)"
        echo "--------------------"
        for f in "${RAW_DIR}"/smartctl-*.txt; do
            if [[ -f "$f" ]] && ! grep -q "not available\|not found" "$f"; then
                local devname
                devname=$(basename "$f" .txt | sed 's/smartctl-//')
                echo "Device: /dev/${devname}"
                # Extract key SMART info
                grep -E '(Model|Serial|Capacity|SMART overall-health|Power_On_Hours|Temperature|Reallocated|Pending|Uncorrectable)' "$f" | head -15 | sed 's/^/  /' || true
                echo ""
            fi
        done
        
        # NVMe Summary
        if [[ -f "${RAW_DIR}/nvme-list.txt" ]] && ! grep -q "not available" "${RAW_DIR}/nvme-list.txt"; then
            echo "NVME DRIVES"
            echo "-----------"
            cat "${RAW_DIR}/nvme-list.txt" | sed 's/^/  /'
            echo ""
        fi
        
        # GPU Summary
        echo "GRAPHICS"
        echo "--------"
        if [[ -f "${RAW_DIR}/gpu-info.txt" ]] && [[ -s "${RAW_DIR}/gpu-info.txt" ]]; then
            cat "${RAW_DIR}/gpu-info.txt" | sed 's/^/  /'
        fi
        if [[ -f "${RAW_DIR}/nvidia-smi.txt" ]] && ! grep -q "not available" "${RAW_DIR}/nvidia-smi.txt"; then
            echo ""
            echo "NVIDIA GPU Details:"
            head -20 "${RAW_DIR}/nvidia-smi.txt" | sed 's/^/  /'
        fi
        echo ""
        
        # Network Summary
        echo "NETWORK INTERFACES"
        echo "------------------"
        if [[ -f "${RAW_DIR}/ip-addr.txt" ]]; then
            # Show interface names with IPs
            grep -E '^[0-9]+:|inet ' "${RAW_DIR}/ip-addr.txt" | sed 's/^/  /' || cat "${RAW_DIR}/ip-addr.txt" | sed 's/^/  /'
        fi
        echo ""
        
        # Sensors
        if [[ -f "${RAW_DIR}/sensors.txt" ]] && ! grep -q "not available\|not found" "${RAW_DIR}/sensors.txt"; then
            echo "TEMPERATURE SENSORS"
            echo "-------------------"
            cat "${RAW_DIR}/sensors.txt" | sed 's/^/  /'
            echo ""
        fi
        
        # PCI Devices Summary
        echo "PCI DEVICES (Summary)"
        echo "---------------------"
        if [[ -f "${RAW_DIR}/lspci.txt" ]]; then
            # Just show the first line of each device (the summary)
            grep -E '^[0-9a-f]+:' "${RAW_DIR}/lspci.txt" | head -30 | sed 's/^/  /' || head -30 "${RAW_DIR}/lspci.txt" | sed 's/^/  /'
        fi
        echo ""
        
        # USB Devices Summary
        echo "USB DEVICES (Summary)"
        echo "---------------------"
        if [[ -f "${RAW_DIR}/lsusb.txt" ]]; then
            grep -E '^Bus' "${RAW_DIR}/lsusb.txt" | head -20 | sed 's/^/  /' || head -20 "${RAW_DIR}/lsusb.txt" | sed 's/^/  /'
        fi
        echo ""
        
        # Kernel Info
        echo "KERNEL"
        echo "------"
        if [[ -f "${RAW_DIR}/cmdline.txt" ]]; then
            echo "Boot Parameters:"
            cat "${RAW_DIR}/cmdline.txt" | sed 's/^/  /'
        fi
        echo ""
        echo "Loaded Modules (count): $(wc -l < "${RAW_DIR}/lsmod.txt" 2>/dev/null || echo "unknown")"
        echo ""
        
        # Gentoo-specific summary (data is in raw/gentoo/ subfolder)
        if [[ -f "${RAW_DIR}/gentoo/gentoo-release.txt" ]]; then
            echo "GENTOO CONFIGURATION"
            echo "--------------------"
            if [[ -f "${RAW_DIR}/gentoo/eselect-profile.txt" ]]; then
                echo "Profile:"
                cat "${RAW_DIR}/gentoo/eselect-profile.txt" | sed 's/^/  /'
            fi
            echo ""
            if [[ -f "${RAW_DIR}/gentoo/world.txt" ]]; then
                local world_count
                world_count=$(wc -l < "${RAW_DIR}/gentoo/world.txt" 2>/dev/null || echo "unknown")
                echo "World File Packages: ${world_count}"
            fi
            if [[ -f "${RAW_DIR}/gentoo/installed-packages.txt" ]]; then
                local pkg_count
                pkg_count=$(wc -l < "${RAW_DIR}/gentoo/installed-packages.txt" 2>/dev/null || echo "unknown")
                echo "Total Installed Packages: ${pkg_count}"
            fi
            echo ""
            if [[ -f "${RAW_DIR}/gentoo/make.conf.txt" ]]; then
                echo "make.conf highlights:"
                grep -E '^(CFLAGS|CXXFLAGS|MAKEOPTS|USE|ACCEPT_KEYWORDS|VIDEO_CARDS|INPUT_DEVICES)=' "${RAW_DIR}/gentoo/make.conf.txt" | sed 's/^/  /' || true
            fi
            echo ""
        fi
        
        # Warnings
        if [[ ${#WARNINGS[@]} -gt 0 ]]; then
            echo "CAPTURE WARNINGS"
            echo "----------------"
            for w in "${WARNINGS[@]}"; do
                echo "  - $w"
            done
            echo ""
        fi
        
        # Footer
        echo "================================================================================"
        echo "Raw data files are available in: ${RAW_DIR}/"
        echo "================================================================================"
        
    } > "${REPORT}"
    
    log "Report generated: ${REPORT}"
}

# Main execution
main() {
    log "==============================================="
    log "System Legacy Capture Script"
    log "==============================================="
    log "Hostname: ${HOSTNAME}"
    log "Date: ${DATE}"
    log "Output Directory: ${OUTPUT_DIR}"
    log ""
    
    if [[ $EUID -ne 0 ]]; then
        warn "Not running as root. Some captures (dmidecode, hdparm benchmarks, smartctl, fdisk) will be skipped or limited."
        log ""
    fi
    
    setup_directories
    
    capture_core_system
    capture_cpu
    capture_memory
    capture_storage
    capture_pci_usb
    capture_gpu
    capture_network
    capture_sensors
    capture_kernel
    capture_gentoo
    
    generate_report
    
    log ""
    log "==============================================="
    log "Capture Complete!"
    log "==============================================="
    log "Output directory: ${OUTPUT_DIR}"
    log "Report: ${REPORT}"
    log "Raw data: ${RAW_DIR}/"
    
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        log ""
        log "There were ${#WARNINGS[@]} warnings during capture."
        log "Check the report for details."
    fi
}

main "$@"
