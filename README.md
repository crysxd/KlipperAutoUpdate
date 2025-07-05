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
     make clear && make menuconfig
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
   - Create a new config file called `klipper_auto_update.conf`. More about the config and an example file can be found in the Git repository.
   - List all your boards here and save.

5. **Run the script:**
   ```bash
   ~/klipper_auto_update/klipper_auto_update.sh
   ```

## Config

The `klipper_auto_update.conf` config contains all your boards. Add one entry for each board. To flash, you need to provide the correct `flash_mode`:

- **Raspberry Pi:** For the "host MCU," use `make`.
- **All other MCUs:** For anything else use `katapult`

For `katapult` you also need to provide a `flash_target`:

- **CAN bus:** Provide `-i can0 -u {can uuid}` and replace `{can uuid}` with the correct UUID for the device, e.g., `9c50d1bd9a07`.
- **USB:** Provide `-d /dev/serial/by-id/{usb device}` and replace `{usb device}` with the correct path, e.g., `usb-Klipper_rp2040_45474E621A86D2CA-if00`.

The config files linked for each board must correspond to the files you create with `make menuconfig` and then `cp`
