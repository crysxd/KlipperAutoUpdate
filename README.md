# KlipperAutoUpdate
You can fully automate the updates for Klipper, including to reflash the boards.

Requirement: Your boards are initially manually flashed with Katapult and Klipper once

Katapult is a bootloader that allows the easy flashing of your board and is a key part of this automation. Start by following the [Esoterical guide](https://canbus.esoterical.online/mainboard_flashing.html) to flash all your Klpper boards with Katapult and Klipper. The guide is specific for Canbus, but you can 1:1 apply it for USB connected boards as well, 
just make sure to use "Communication interface: USB" when building Klipper with `make menuconfig` and not "Communication interface: Canbus"

I flash all my boards in this stream:
https://www.youtube.com/watch?v=tLyi-2RE09s&list=PL1fjlNqlUKnUjV9GKHGI1oXRcxDsKKw-X&index=32

I create the script with setup here, but an earlier itereation:
https://www.youtube.com/watch?v=tne5wVYEaQs&list=PL1fjlNqlUKnUjV9GKHGI1oXRcxDsKKw-X&index=33

# Setup

- Login via SSH to your machine
- `cd ~ && git clone https://github.com/crysxd/KlipperAutoUpdate.git klipper_auto_update` to create a new folder
- For each of your boards:
  - `cd ~/klipper`
  - `make clear && make menuconfig`
  - Configure your board here. Make sure to have the "bootloader" set so you don't override Katapult.
  - `q` and save
  - Klipper now created a `.config` file with the values you entered
  - `cp ~/klipper/.config ~/klipper_auto_update/{board_name}.config` to copy the file and save it for later. Replace `{board_name}` to a unique name without spaces, e.g. `m4p.config`
  - As a side note, if you have the same board type twice, you only need to do this once
- You now have config files for each board in your `~/klipper_auto_update` directory
- Now we create a config file for the script
  - Open your Klipper webinterface and go to the config section
  - Create a new config file called `klipper_auto_update.conf`, more about the config below and an example file can be found in the git above
  - List all your boards here and save.
- Everything is ready! You can run `~/klipper_auto_update/klipper_auto_update.sh` :)

# Config
The `boards.conf` config contains all your boards, add one entry for each baord.
To flash, you need to provide the correct flash target

- Canbus: Provide `-i can0 -u {can uuid}` and replace `{can uuid}` with the correct uuid for the device, e.g. `9c50d1bd9a07`
- USB: -d /dev/serial/by-id/{usb device}` and replace `{usb device}` with the correct path, e.g. `usb-Klipper_rp2040_45474E621A86D2CA-if00`
- Raspberry Pi: For the "host MCU" use `make`