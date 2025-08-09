# KlipperAutoUpdate

You can fully automate the updates for Klipper, including reflashing the boards. I flash all my boards in this stream:

- [Flashing Boards Stream](https://www.youtube.com/watch?v=tLyi-2RE09s&list=PL1fjlNqlUKnUjV9GKHGI1oXRcxDsKKw-X&index=32)

I create the script with setup here, but an earlier iteration:

- [Script Setup Stream](https://www.youtube.com/watch?v=tne5wVYEaQs&list=PL1fjlNqlUKnUjV9GKHGI1oXRcxDsKKw-X&index=33)

## Preconditions

Your boards must initially be manually flashed with Katapult and Klipper once. Katapult is a bootloader that allows easy flashing of your board and is a key part of this automation. Start by following the [Esoterical guide](https://canbus.esoterical.online/mainboard_flashing.html) to flash all your Klipper boards with Katapult and Klipper. The guide is specific for CAN bus, but you can apply it for USB-connected boards as well. Just make sure to use "Communication interface: USB" when building Klipper with `make menuconfig` and not "Communication interface: CAN bus."

## Setup

1. **Login via SSH to your machine.**
2. **Clone the repository:**
   ```bash
   cd ~ && git clone https://github.com/crysxd/KlipperAutoUpdate.git klipper_auto_update
   ```
3. **For each of your boards:**
   - Navigate to the Klipper directory:
     ```bash
     cd ~/klipper
     ```
   - Configure your board:
     ```bash
     make clean && make menuconfig
     ```
   - Ensure the "bootloader" is set so you don't override Katapult.
   - Save and exit.
   - Klipper will create a `.config` file with the values you entered.
   - Copy the `.config` file to the `klipper_auto_update` directory:
     ```bash
     cp ~/klipper/.config ~/klipper_auto_update/{board_name}.config
     ```
     Replace `{board_name}` with a unique name without spaces, e.g., `m4p.config`.
   - Note: If you have the same board type twice, you only need to do this once.

4. **Create a config file for the script:**
   - Open your Klipper web interface and go to the config section.
   - Create a new config file called `klipper_auto_update.conf`. 
   - List all your boards here and save.
   - The script will create a default config file if none exists to help you get started.

5. **Run the script:**
   ```bash
   ~/klipper_auto_update/klipper_auto_update.sh
   ```

## Configuration

The `klipper_auto_update.conf` config contains all your boards. Add one entry for each board using the format `[board <board_id>]`. 

### Basic Configuration Parameters

- **`description`**: Human-readable description of the board
- **`config_file`**: Path to the Klipper config file (created with `make menuconfig`)
- **`flash_method`**: How to flash the board

### Flash Methods

#### Raspberry Pi (Host MCU)
For the "host MCU," use `make`:
```ini
[board rpi]
description = "Raspberry Pi MCU"
config_file = "rpi.config"
flash_method = "make"
```

#### Katapult Flashing
For all other MCUs, use `flash_method = "katapult"` with the appropriate parameters:

##### Direct USB Flashing
```ini
[board lis2dw]
description = "ADXL345/LIS2DW accelerometer"
config_file = "adxl.config"
flash_method = "katapult"
katapult_usb_device = "/dev/serial/by-id/usb-Klipper_rp2040_45474E621A86D2CA-if00"
```

##### Direct CAN Flashing
```ini
[board sb2209]
description = "SB2209 toolhead board"
config_file = "sb2209.config"
flash_method = "katapult"
katapult_can_uuid = "9c50d1bd9a07"
```

##### USB/CAN Bridge Flashing
For mainboards that act as USB/CAN bridges, use both bridge parameters. The script will automatically:
1. Put the device into boot mode via CAN
2. Flash via USB to avoid breaking the bridge connection. You can get this ID by running `~/katapult/scripts/flashtool.py -i can0 -u c1980e2023a1 -r; ls /dev/serial/by-id/` (replace `-u` with your uuid) and then looking for the katapult device. Please note after this you need to power down the printer or press the reset button on the board to reset the state.

```ini
[board m4p]
description = "Manta M8P board with USB/CAN bridge"
config_file = "m8p.config"
flash_method = "katapult"
katapult_can_bridge_usb_device = "/dev/serial/by-id/usb-katapult_stm32h723xx_140028000951313339373836-if00"
katapult_can_bridge_can_uuid = "c1980e2023a1"
```

### Legacy Configuration (Deprecated)
The old `flash_target` parameter is still supported but deprecated:
```ini
[board legacy_board]
description = "Legacy configuration format"
config_file = "legacy.config"
flash_method = "katapult_legacy"
flash_target = "-d /dev/serial/by-id/usb-Klipper_stm32g0b1xx_3200310019504B5735313920-if00"
```

## Complete Example Configuration

```ini
# Klipper Auto-Update Configuration
[board rpi]
description = "Raspberry Pi MCU"
config_file = "rpi.config"
flash_method = "make"

[board m4p]
description = "Manta M4P mainboard with USB/CAN bridge"
config_file = "m4p.config"
flash_method = "katapult"
katapult_can_bridge_usb_device = "/dev/serial/by-id/usb-katapult_stm32h723xx_140028000951313339373836-if00"
katapult_can_bridge_can_uuid = "c1980e2023a1"

[board sb2209]
description = "SB2209 toolhead board"
config_file = "sb2209.config"
flash_method = "katapult"
katapult_can_uuid = "9c50d1bd9a07"

[board lis2dw]
description = "ADXL345/LIS2DW accelerometer"
config_file = "adxl.config"
flash_method = "katapult"
katapult_usb_device = "/dev/serial/by-id/usb-Klipper_rp2040_45474E621A86D2CA-if00"
```

## Configuration Notes

- The config files (e.g., `m4p.config`) must correspond to the files you create with `make menuconfig` and then copy with `cp ~/klipper/.config ~/klipper_auto_update/{board_name}.config`
- For USB devices, use the full `/dev/serial/by-id/` path to ensure consistency across reboots
- For CAN devices, use the UUID without any prefixes
- The script automatically detects which flashing method to use based on the parameters you provide
- USB/CAN bridge boards require special handling to avoid breaking the bridge connection during flashing

## Troubleshooting

- If boards don't come back online after flashing, try rebooting: `sudo reboot now`
- Make sure all `/dev/serial/by-id/` paths are correct and exist on your system
- Verify CAN UUIDs are correct by running `~/katapult/scripts/flashtool.py -i can0 -q`
- Check that Katapult bootloader is properly installed on all boards before using this script