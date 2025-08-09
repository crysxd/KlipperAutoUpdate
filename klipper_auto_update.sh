#!/bin/bash
set -e

# Configuration
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
KLIPPER_DIR="$HOME/klipper"
KATAPULT_DIR="$HOME/katapult"
MAKE_JOBS=$(nproc)

# Global variables set by printer data selection
PRINTER_DATA_DIR=""
CONFIG_FILE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are available
check_dependencies() {
    log_info "Checking dependencies..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    if [[ ! -d "$KLIPPER_DIR" ]]; then
        log_error "Klipper directory not found: $KLIPPER_DIR"
        exit 1
    fi
    
    if [[ ! -d "$PRINTER_DATA_DIR/config" ]]; then
        log_error "Printer config directory not found: $PRINTER_DATA_DIR/config"
        exit 1
    fi
    
    log_success "Dependencies check passed"
}

# Stop Klipper service
stop_klipper() {
    log_info "Stopping Klipper service..."
    if sudo service klipper stop; then
        log_success "Klipper service stopped"
    else
        log_error "Failed to stop Klipper service"
        exit 1
    fi
}

# Update Klipper source code
update_klipper_source() {
    log_info "Updating Klipper source code..."
    cd "$KLIPPER_DIR"
    
    if git pull; then
        log_success "Klipper source updated"
    else
        log_error "Failed to update Klipper source"
        exit 1
    fi
}

# Flash via Katapult with CAN bridge support
flash_katapult() {
    local katapult_usb_device="$1"
    local katapult_can_uuid="$2"
    local katapult_can_bridge_usb_device="$3"
    local katapult_can_bridge_can_uuid="$4"
    local device_id="$5"
    
    if [[ ! -d "$KATAPULT_DIR" ]]; then
        log_error "Katapult directory not found: $KATAPULT_DIR"
        return 1
    fi
    
    # Check if CAN bridge is configured
    if [[ -n "$katapult_can_bridge_usb_device" && -n "$katapult_can_bridge_can_uuid" ]]; then
        log_info "USB/CAN bridge detected - using two-step flashing process"
        
        # Step 1: Put the device into boot mode via CAN
        log_info "Step 1: Putting device into Katapult boot mode..."
        local reset_cmd="python3 $KATAPULT_DIR/scripts/flashtool.py -i can0 -u $katapult_can_bridge_can_uuid -r"
        log_info "Executing: $reset_cmd"
        
        if eval "$reset_cmd"; then
            log_success "Device put into boot mode"
        else
            log_error "Failed to put device into boot mode"
            return 1
        fi
        
        # Wait a moment for the device to enter boot mode
        log_info "Waiting for device to enter boot mode..."
        sleep 3
        
        # Step 2: Flash via USB using the bridge USB device
        log_info "Step 2: Flashing firmware via USB..."
        local flash_cmd="python3 $KATAPULT_DIR/scripts/flashtool.py -f $KLIPPER_DIR/out/klipper.bin -d $katapult_can_bridge_usb_device"
        log_info "Executing: $flash_cmd"
        
        if eval "$flash_cmd"; then
            log_success "Firmware flashed successfully via USB"
        else
            log_error "Failed to flash firmware via USB"
            return 1
        fi
        
    elif [[ -n "$katapult_usb_device" ]]; then
        # Direct USB flashing
        log_info "Direct USB flashing..."
        local flash_cmd="python3 $KATAPULT_DIR/scripts/flashtool.py -f $KLIPPER_DIR/out/klipper.bin -d $katapult_usb_device"
        log_info "Executing: $flash_cmd"
        
        if eval "$flash_cmd"; then
            log_success "Firmware flashed successfully via USB"
        else
            log_error "Failed to flash firmware via USB"
            return 1
        fi
        
    elif [[ -n "$katapult_can_uuid" ]]; then
        # Direct CAN flashing
        log_info "Direct CAN flashing..."
        local flash_cmd="python3 $KATAPULT_DIR/scripts/flashtool.py -f $KLIPPER_DIR/out/klipper.bin -i can0 -u $katapult_can_uuid"
        log_info "Executing: $flash_cmd"
        
        if eval "$flash_cmd"; then
            log_success "Firmware flashed successfully via CAN"
        else
            log_error "Failed to flash firmware via CAN"
            return 1
        fi
        
    else
        log_error "No valid Katapult flashing parameters found for device $device_id. Either katapult_usb_device, katapult_can_uuid, or both katapult_can_bridge_usb_device and katapult_can_bridge_can_uuid must be specified."
        return 1
    fi
    
    return 0
}

# Build and flash a single device
build_and_flash_device() {
    local device_id="$1"
    local config_file="$2"
    local flash_method="$3"
    local flash_target="$4"
    local description="$5"
    local katapult_usb_device="$6"
    local katapult_can_uuid="$7"
    local katapult_can_bridge_usb_device="$8"
    local katapult_can_bridge_can_uuid="$9"
    
    echo ""
    echo "=========================================="
    log_info "Processing device: $device_id ($description)"
    echo "=========================================="
    
    # Resolve config file path
    local full_config_path="$SCRIPT_DIR/$config_file"
    if [[ ! -f "$full_config_path" ]]; then
        log_error "Config file not found: $full_config_path"
        return 1
    fi
    
    log_info "Using config: $config_file"
    
    # Clean and build
    log_info "Cleaning previous build..."
    if make clean KCONFIG_CONFIG="$full_config_path"; then
        log_success "Clean completed"
    else
        log_error "Clean failed for $device_id"
        return 1
    fi
    
    log_info "Building Klipper firmware (using $MAKE_JOBS parallel jobs)..."
    if make -j"$MAKE_JOBS" KCONFIG_CONFIG="$full_config_path"; then
        log_success "Build completed for $device_id"
    else
        log_error "Build failed for $device_id"
        return 1
    fi
    
    # Flash firmware
    log_info "Flashing firmware..."
    if [[ "$flash_method" == "make" ]]; then
        if make flash KCONFIG_CONFIG="$full_config_path"; then
            log_success "Flashing completed for $device_id"
        else
            log_error "Flashing failed for $device_id"
            return 1
        fi
    elif [[ "$flash_method" == "katapult" ]]; then
        if flash_katapult "$katapult_usb_device" "$katapult_can_uuid" "$katapult_can_bridge_usb_device" "$katapult_can_bridge_can_uuid" "$device_id"; then
            log_success "Flashing completed for $device_id"
        else
            log_error "Flashing failed for $device_id"
            return 1
        fi
    elif [[ "$flash_method" == "katapult_legacy" ]]; then
        # Legacy support for old flash_target parameter
        local flash_cmd="python3 $KATAPULT_DIR/scripts/flashtool.py -f $KLIPPER_DIR/out/klipper.bin $flash_target"
        log_info "Executing legacy command: $flash_cmd"
        
        if eval "$flash_cmd"; then
            log_success "Flashing completed for $device_id"
        else
            log_error "Flashing failed for $device_id"
            return 1
        fi
    else
        log_error "Unknown flash method: $flash_method"
        return 1
    fi
    
    log_success "Device $device_id processed successfully"
}

# Find and select printer data directory
select_printer_data_dir() {
    log_info "Searching for printer data directories..."
    
    # Find all printer_data directories
    local printer_dirs=($(find "$HOME" -maxdepth 1 -type d -name "printer_data*" 2>/dev/null | sort))
    
    if [[ ${#printer_dirs[@]} -eq 0 ]]; then
        log_error "No printer_data directories found in $HOME"
        log_error "Expected to find directories like ~/printer_data or ~/printer_data_printer1"
        exit 1
    elif [[ ${#printer_dirs[@]} -eq 1 ]]; then
        PRINTER_DATA_DIR="${printer_dirs[0]}"
        log_info "Found single printer data directory: $PRINTER_DATA_DIR"
    else
        log_info "Found multiple printer data directories:"
        for i in "${!printer_dirs[@]}"; do
            echo "  $((i+1)). ${printer_dirs[i]}"
        done
        
        while true; do
            read -p "Select printer data directory (1-${#printer_dirs[@]}): " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#printer_dirs[@]} ]]; then
                PRINTER_DATA_DIR="${printer_dirs[$((choice-1))]}"
                log_info "Selected: $PRINTER_DATA_DIR"
                break
            else
                log_error "Invalid choice. Please enter a number between 1 and ${#printer_dirs[@]}"
            fi
        done
    fi
    
    # Set config file path
    CONFIG_FILE="$PRINTER_DATA_DIR/config/klipper_auto_update.conf"
    log_info "Configuration file will be: $CONFIG_FILE"
}

# Create config file if it doesn't exist
create_config_if_missing() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warning "Configuration file not found, creating default config..."
        
        # Ensure config directory exists
        mkdir -p "$(dirname "$CONFIG_FILE")"
        
        # Create default config file
        cat > "$CONFIG_FILE" << 'EOF'
# Klipper Auto-Update Configuration
# This file defines the devices to build and flash during Klipper updates
# Format: [board <id>]
# 
# Edit this file through your web interface (Mainsail/Fluidd) in the config section

[board rpi]
description = "Raspberry Pi MCU"
config_file = "rpi_klipper_makemenu.config"
flash_method = "make"

# Example boards with new Katapult parameters:

# Direct USB flashing
#[board lis2dw]
#description = "ADXL345/LIS2DW accelerometer"
#config_file = "adxl_klipper_makemenu.config"
#flash_method = "katapult"
#katapult_usb_device = "/dev/serial/by-id/usb-Klipper_rp2040_45474E621A86D2CA-if00"

# Direct CAN flashing
#[board sb2209]
#description = "SB2209 toolhead board"
#config_file = "sb2209_klipper_makemenu.config"
#flash_method = "katapult"
#katapult_can_uuid = "9c50d1bd9a07"

# USB/CAN Bridge flashing (mainboard with USB/CAN bridge)
#[board m4p]
#description = "Manta M4P board with USB/CAN bridge"
#config_file = "m4p_klipper_makemenu.config"
#flash_method = "katapult"
#katapult_can_bridge_usb_device = "/dev/serial/by-id/usb-katapult_stm32h723xx_140028000951313339373836-if00"
#katapult_can_bridge_can_uuid = "c1980e2023a1"

# Legacy format (still supported but deprecated)
#[board legacy_board]
#description = "Legacy configuration format"
#config_file = "legacy_klipper_makemenu.config"
#flash_method = "katapult_legacy"
#flash_target = "-d /dev/serial/by-id/usb-Klipper_stm32g0b1xx_3200310019504B5735313920-if00"

# Configuration Notes:
# - For direct USB flashing: Use katapult_usb_device
# - For direct CAN flashing: Use katapult_can_uuid  
# - For USB/CAN bridge: Use both katapult_can_bridge_usb_device and katapult_can_bridge_can_uuid
# - The script will automatically detect which method to use based on available parameters
# - To configure your board: make clean && make menuconfig
EOF
        
        log_success "Created default configuration file: $CONFIG_FILE"
        log_info "You can now edit this file through your web interface or directly with a text editor"
        log_info "Uncomment and modify the example boards as needed for your setup"
    fi
}

get_klipper_version() {
    if [[ -d "$KLIPPER_DIR/.git" ]]; then
        cd "$KLIPPER_DIR"
        # Get version in Klipper's format: tag-commits_since_tag-commit_hash
        local version=$(git describe --always --tags --long 2>/dev/null || echo "unknown")
        echo "$version"
    else
        echo "unknown (not a git repository)"
    fi
}

read_config() {
    local config_file="$1"
    local section="$2"
    local key="$3"
    
    awk -F ' = ' -v section="$section" -v key="$key" '
    /^\[/ { 
        current_section = $0
        gsub(/^\[|\]$/, "", current_section)
    }
    current_section == section && $1 == key { 
        gsub(/^"/, "", $2)
        gsub(/"$/, "", $2)
        print $2
        exit
    }
    ' "$config_file"
}

# Get all board sections from config
get_board_sections() {
    grep '^\[board ' "$CONFIG_FILE" | sed 's/^\[board //' | sed 's/\]$//'
}

# Process all devices from config
process_devices() {
    log_info "Processing devices from configuration..."
    
    local boards=($(get_board_sections))
    local device_count=${#boards[@]}
    log_info "Found $device_count devices to process"
    
    for board_id in "${boards[@]}"; do
        local section="board $board_id"
        local config_file=$(read_config "$CONFIG_FILE" "$section" "config_file")
        local flash_method=$(read_config "$CONFIG_FILE" "$section" "flash_method")
        local flash_target=$(read_config "$CONFIG_FILE" "$section" "flash_target")
        local description=$(read_config "$CONFIG_FILE" "$section" "description")
        local katapult_usb_device=$(read_config "$CONFIG_FILE" "$section" "katapult_usb_device")
        local katapult_can_uuid=$(read_config "$CONFIG_FILE" "$section" "katapult_can_uuid")
        local katapult_can_bridge_usb_device=$(read_config "$CONFIG_FILE" "$section" "katapult_can_bridge_usb_device")
        local katapult_can_bridge_can_uuid=$(read_config "$CONFIG_FILE" "$section" "katapult_can_bridge_can_uuid")
        
        if build_and_flash_device "$board_id" "$config_file" "$flash_method" "$flash_target" "$description" \
                                  "$katapult_usb_device" "$katapult_can_uuid" "$katapult_can_bridge_usb_device" "$katapult_can_bridge_can_uuid"; then
            log_success "Successfully processed $board_id"
        else
            log_error "Failed to process $board_id"
            # Ask user if they want to continue
            read -p "Continue with remaining devices? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Aborting remaining devices"
                break
            fi
        fi
    done
}

# Start Klipper service
start_klipper() {
    log_info "Starting Klipper service..."
    if sudo service klipper start; then
        log_success "Klipper service started"
    else
        log_error "Failed to start Klipper service"
        exit 1
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "         Klipper Update Script"
    echo "=========================================="
    
    # First, find and select printer data directory
    select_printer_data_dir
    
    # Create config file if it doesn't exist
    create_config_if_missing
    
    # Get initial Klipper version
    cd "$KLIPPER_DIR" 2>/dev/null || { log_error "Cannot access Klipper directory"; exit 1; }
    local klipper_version_before=$(get_klipper_version)
    log_info "Klipper version before update: $klipper_version_before"
    
    check_dependencies
    stop_klipper
    update_klipper_source
    
    # Get updated Klipper version
    local klipper_version_after=$(get_klipper_version)
    log_info "Klipper version after update: $klipper_version_after"
    
    cd "$KLIPPER_DIR"
    process_devices
    
    start_klipper
    
    echo ""
    echo "=========================================="
    log_success "Klipper update completed successfully!"
    echo "=========================================="
    log_info "Version Summary:"
    log_info "  Before: $klipper_version_before"
    log_info "  After:  $klipper_version_after"
    
    if [[ "$klipper_version_before" != "$klipper_version_after" ]]; then
        log_success "Klipper was updated to a newer version!"
    else
        log_info "Klipper was already up to date"
    fi
    
    log_info "Configuration file: $CONFIG_FILE"
    log_info "Edit via web interface or directly to modify board settings"
    echo ""
    log_warning "Sometimes a reboot is required for boards to come back online after flashing."
    log_warning "Run 'sudo reboot now' if Klipper does not come back online after flashing."
    echo "=========================================="
}

# Run main function
main "$@"