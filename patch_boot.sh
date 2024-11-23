#!/bin/bash

# Argument check
if [ $# == 0 ]; then
    echo "Usage: $0 [<path_to_zip_package> ...]"
    exit 1
fi

# Root check
if [ "$(whoami)" != root ]; then
    echo "Please run this script using sudo."
    exit 1
fi

if [ "$1" = "-c" ]; then
  variant="canary"
else
  variant="magisk"
fi

script_path="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

#programs=("adb" "brotli" "curl" "dos2unix" "ed" "fastboot" "file" "jq" "python3" "unzip")
programs=()

# Check if all required programs are installed
for program in "${programs[@]}"; do
    if ! command -v "$program" &>/dev/null; then
        echo "$program is not installed. Please install it and run this script again."
        exit 1
    fi
done

setup_env() {
    [ -z $KEEPVERITY ] && export KEEPVERITY=true
    [ -z $KEEPFORCEENCRYPT ] && export KEEPFORCEENCRYPT=true

    if grep -q "vbmeta.img" "${script_path}/magisk_files/updater-script"; then
        export PATCHVBMETAFLAG=false
    else
        export PATCHVBMETAFLAG=true
    fi
}

patch_scripts() {
    local util_script="${script_path}/magisk_files/util_functions.sh"
    
    # Get line number
    local line=$(grep -n '/proc/self/fd/$OUTFD' "$util_script" | cut -d: -f1)

    # Add echo "$1" and delete the line
    (
    echo "$line"
    echo 'd'
    echo "$line-1"
    echo a
    echo '    echo "$1"'
    echo .
    echo wq
    ) | ed "$util_script" > /dev/null 2>&1

    # Replace build.prop path
    sed -i 's/\/system\/build.prop/.\/build.prop/g' "$util_script"
}

get_magisk_files() {
    local temp_dir="$(mktemp -d)"

    # Download and extract Magisk
    if [ "$variant" = "canary" ]; then
        local magisk_url=$(curl -s https://api.github.com/repos/topjohnwu/Magisk/releases | grep 'browser_download_url' | grep 'canary' | grep 'app-release.apk' | head -n 1 | cut -d \" -f 4)
    else
        local magisk_url=$(curl -s https://api.github.com/repos/topjohnwu/Magisk/releases/latest | grep 'browser_download_url' | cut -d \" -f 4)
    fi

    echo "Downloading ${variant} from ${magisk_url}..."
    wget "$magisk_url" -O "$temp_dir/Magisk.apk" &>/dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to download Magisk. Please check your internet connection and try again."
        rm -rf "$temp_dir"
        exit 1
    fi
    unzip "$temp_dir/Magisk.apk" -d "$temp_dir" &>/dev/null

    # Copy needed files
    mkdir -p "$script_path/magisk_files/"
    cp "$temp_dir/assets/boot_patch.sh" "$script_path/magisk_files/"
    cp "$temp_dir/assets/util_functions.sh" "$script_path/magisk_files/"
    cp "$temp_dir/assets/stub.apk" "$script_path/magisk_files/"
    cp "$temp_dir/lib/x86_64/libmagiskboot.so" "$script_path/magisk_files/magiskboot"
    cp "$temp_dir/lib/armeabi-v7a/libmagisk.so" "$script_path/magisk_files/magisk32"
    cp "$temp_dir/lib/arm64-v8a/libmagisk.so" "$script_path/magisk_files/magisk64"
    cp "$temp_dir/lib/arm64-v8a/libmagiskinit.so" "$script_path/magisk_files/magiskinit"

    rm -rf "$temp_dir"
}

get_rom_files() {
    local temp_dir="$(mktemp -d)"

    # Extract boot.img from ROM zip package
    unzip "$1" -d "$temp_dir" &>/dev/null
    cp "$temp_dir/boot.img" "$script_path/magisk_files/"

    # Extract build.prop
    if [[ -f "$temp_dir/system.new.dat.br" ]]; then
        brotli --decompress "$temp_dir/system.new.dat.br" -o "$temp_dir/system.new.dat" &>/dev/null
    fi
    python3 "$script_path/sdat2img/sdat2img.py" "$temp_dir/system.transfer.list" "$temp_dir/system.new.dat" "$temp_dir/system.img" &>/dev/null
    if [[ $(file "$temp_dir/system.img") == *EROFS* ]]; then
        local temp_mount_dir=$(mktemp -d)

        echo "EROFS system detected, mounting system.img to extract build.prop"
        mount -t erofs "$temp_dir/system.img" "$temp_mount_dir"
        cp "$temp_mount_dir/system/build.prop" "$script_path/magisk_files/build.prop"
        umount "$temp_mount_dir"
        rm -rf "$temp_mount_dir"
    else
        debugfs -R "dump system/build.prop $script_path/magisk_files/build.prop" "$temp_dir/system.img" &>/dev/null
    fi

    # Extract updater-script
    cp "$temp_dir/META-INF/com/google/android/updater-script" "$script_path/magisk_files/"

    rm -rf "$temp_dir"
}

get_props() {
    local REGEX="s/^$1=//p"
    local FILE="$script_path/magisk_files/build.prop"

    cat $FILE 2>/dev/null | dos2unix | sed -n "$REGEX" | head -n 1
}

move_patched() {
    patched_name="$(get_props "ro.build.product")_$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 5).img"

    # Move patched boot.img to output folder
    mv "$script_path/magisk_files/new-boot.img" "$script_path/out/${variant}_${patched_name}"

    mv "$script_path/magisk_files/boot.img" "$script_path/out/stock_$patched_name"
}

clean_files () {
    rm -f "$script_path/magisk_files/boot.img"
    rm -f "$script_path/magisk_files/build.prop"
    rm -f "$script_path/magisk_files/updater-script"
}

patch_boot() {
    echo "Getting needed files from ${variant}..."
    get_magisk_files

    echo "Patching ${variant} util scripts..."
    patch_scripts

    for zip_package in "$@"; do
        if [[ $zip_package == "-k" || "$zip_package" == "-c" ]]; then
          continue
        fi
        echo -e "\nProcessing $zip_package..."
        echo "---------------------------------------------"
        if [[ "$zip_package" != *.zip ]]; then
            echo "$zip_package is not a zip file."
        else
            echo "Getting needed files from rom zip package..."
            get_rom_files "$zip_package"

            echo "Patching boot.img..."
            setup_env
            sh "$script_path/magisk_files/boot_patch.sh" "$script_path/magisk_files/boot.img" #&>/dev/null

            move_patched
            clean_files
            echo "Done! Patched boot.img can be found at out/${variant}_${patched_name}"
        fi
    done

    echo -e "\nCleaning up..."
    rm -rf "$script_path/magisk_files/"
}

patch_boot "$@"
