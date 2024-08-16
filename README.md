# Android ROM Boot Image Patcher

This script is designed to extract the `boot.img` from an Android ROM installation package (ZIP file) and patch it with Magisk. It replicates the functionality of the Magisk app by extracting binaries from the Magisk APK and using them to patch the boot image, just as the app would on a device. The script is compatible with AOSP-based ROMs.

## How It Works

The script works by extracting binaries from the Magisk APK and utilizing them, along with the boot image patch script provided by Magisk, to perform the patching process. This approach replicates the patching process that would typically occur on an Android device, taking into account various factors such as:

- Presence of `vbmeta`
- Whether the ROM is encrypted, etc.

One key modification in this script is that it reads the `build.prop` file extracted from the ROM's system image instead of using `getprop` (which would be used if the patching were done directly on the phone). This ensures that the patching process uses the correct system properties that correspond to the specific ROM being patched.

## Background and Inspiration

The inspiration for this script came from my interest in the Magisk patching process. Upon examining the patch script provided by Magisk, I realized that the script primarily calls binaries based on certain parameters. This discovery led me to create this script, which automates the patching process on a host machine.

## Usage

### 1. Clone the repository:
```bash
git clone --recurse-submodules https://github.com/0xsharkboyMagisk-Boot-Patcher && cd Magisk-Boot-Patcher
   ```
### 2. Make the script executable:
```bash
chmod +x patch_boot.sh
```

### 3. Install dependencies:
- On DEBIAN/Ubuntu based distros:
```bash
sudo apt install $(cat dependencies)
```
- On Arch based distros (with yay):
```bash
yay -S $(cat dependencies)
```

### 4. Run the script with root privileges:
- To patch with Magisk:
```bash
sudo ./patch_boot.sh [rom_package.zip, ...]
```
- To patch with Kitsune, use the `-k` flag:
```bash
sudo ./patch_boot.sh -k [rom_package.zip, ...]
```

## Testing and Feedback

I encourage you to test this script on your own AOSP-based ROMs. If it doesn't work as expected, please open an issue on the GitHub repository. Be sure to include the following details in your issue:

- A detailed description of what didn’t work.
- A link to download the ROM that caused the issue.
- Source code or additional documentation for the ROM, if available.

## Disclaimer

This script is intended for users with advanced knowledge of Android ROMs and custom recoveries. Use it at your own risk. I am not responsible for any damage that may occur to your device.

## Credits
 - [sdat2img](https://github.com/xpirt/sdat2img/tree/master) by [@xpirt](https://github.com/xpirt)
 - [magisk_for_linux](https://github.com/daboynb/magisk_for_linux) by [@daboynb](https://github.com/daboynb)

## Support
[<img src="https://github.com/user-attachments/assets/b05920cb-22d5-4db3-9033-e81ae6911a0b" width="200px" />](https://ko-fi.com/0xsharkboy)

