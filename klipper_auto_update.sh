#!/bin/bash
set -e

# Configuration
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG_FILE="$SCRIPT_DIR/klipper_devices.conf"
KLIPPER_DIR="$HOME/klipper"
KATAPULT_DIR="$HOME/katapult"
MAKE_JOBS=$(nproc)

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

# Build and flash a single device
build_and_flash_device() {
    local device_id="$1"
    local config_file="$2"
    local flash_method="$3"
    local flash_target="$4"
    local description="$5"
    
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
        if [[ ! -d "$KATAPULT_DIR" ]]; then
            log_error "Katapult directory not found: $KATAPULT_DIR"
            return 1
        fi
        
        local flash_cmd="python3 $KATAPULT_DIR/scripts/flashtool.py -f $KLIPPER_DIR/out/klipper.bin $flash_target"
        log_info "Executing: $flash_cmd"
        
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

# Read INI-style config file
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
        
        if build_and_flash_device "$board_id" "$config_file" "$flash_method" "$flash_target" "$description"; then
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
    
    check_dependencies
    stop_klipper
    update_klipper_source
    
    cd "$KLIPPER_DIR"
    process_devices
    
    start_klipper
    
    echo ""
    echo "=========================================="
    log_success "Klipper update completed successfully!"
    echo "=========================================="
}

# Run main function
main "$@"