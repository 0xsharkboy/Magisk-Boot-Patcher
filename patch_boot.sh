#!/bin/bash

# Usage message
usage() {
    echo "Usage: $0 <path_to_zip_package>"
    exit 1
}

# Argument check
if [ $# -ne 1 ]; then
    usage
fi

zip_package="$(realpath "$1")"

# Check if the argument is a .zip file
if [[ "$zip_package" != *.zip ]]; then
    echo "Please provide zip package as argument"
    usage
fi

# Sudo check
if [ "$(whoami)" = root ]; then
    echo "Don't run this script as root"
    exit 1
fi

script_path="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

check_dependencies() {
    local programs=("adb" "fastboot" "dos2unix" "unzip" "curl" "ed" "brotli" "abootimg" "lz4" "cpio")

    for program in "${programs[@]}"; do
        if ! command -v "$program" &>/dev/null; then
            echo "$program is not installed. Please install it and run this script again."
            exit 1
        fi
    done
}

setup_env() {
    export KEEPVERITY=true
    export KEEPFORCEENCRYPT=true

    if grep -q "vbmeta.img" "${script_path}/magisk_files/updater-script"; then
        export PATCHVBMETAFLAG=true
    else
        export PATCHVBMETAFLAG=false
    fi
}

patch_scripts() {
    local util_file="${script_path}/magisk_files/util_functions.sh"
    local patch_file="${script_path}/magisk_files/boot_patch.sh"
    
    # Get line number
    local line=$(grep -n '/proc/self/fd/$OUTFD' "$util_file" | cut -d: -f1)

    # Add echo "$1" and delete the line
    (
    echo "$line"
    echo 'd'
    echo "$line-1"
    echo a
    echo '    echo "$1"'
    echo .
    echo wq
    ) | ed $script_path/magisk_files/util_functions.sh > /dev/null 2>&1

    # Replace build.prop path
    sed -i 's/\/system\/build.prop/.\/build.prop/g' "$util_file"

    # Use sudo for chmod to be able to use it on the extracted build.prop
    sed -i 's/chmod/sudo chmod/g' "$patch_file"
}

get_files() {
    local temp_dir="$(mktemp -d)"

    # Download and unzip Magisk package
    local magisk_url=$(curl -s https://api.github.com/repos/topjohnwu/Magisk/releases/latest | grep 'browser_download_url' | cut -d\" -f4)
    wget "$magisk_url" -O "$temp_dir/Magisk.apk" &>/dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to download Magisk. Please check your internet connection and try again."
        rm -rf "$temp_dir"
        exit 1
    fi
    unzip "$temp_dir/Magisk.apk" -d "$temp_dir" &>/dev/null

    mkdir -p "$script_path/magisk_files/"
    cp "$temp_dir/assets/boot_patch.sh" "$script_path/magisk_files/"
    cp "$temp_dir/assets/util_functions.sh" "$script_path/magisk_files/"
    cp "$temp_dir/assets/stub.apk" "$script_path/magisk_files/"
    cp "$temp_dir/lib/x86_64/libmagiskboot.so" "$script_path/magisk_files/magiskboot"
    cp "$temp_dir/lib/armeabi-v7a/libmagisk32.so" "$script_path/magisk_files/magisk32"
    cp "$temp_dir/lib/arm64-v8a/libmagisk64.so" "$script_path/magisk_files/magisk64"
    cp "$temp_dir/lib/arm64-v8a/libmagiskinit.so" "$script_path/magisk_files/magiskinit"
    find $temp_dir -delete

    # Extract ROM: get boot.img and build.prop
    unzip "$zip_package" -d "$temp_dir" &>/dev/null
    cp "$temp_dir/boot.img" "$script_path/magisk_files/"
    brotli --decompress "$temp_dir/system.new.dat.br" -o "$temp_dir/system.new.dat" &>/dev/null
    python "$script_path/sdat2img/sdat2img.py" "$temp_dir/system.transfer.list" "$temp_dir/system.new.dat" "$temp_dir/system.img" &>/dev/null
    sudo debugfs -R "dump system/build.prop $script_path/magisk_files/build.prop" "$temp_dir/system.img" &>/dev/null
    cp "$temp_dir/META-INF/com/google/android/updater-script" "$script_path/magisk_files/"

    # Extract fstab from boot.img
    cd $temp_dir/
    abootimg -x $temp_dir/boot.img &>/dev/null
    mkdir "$temp_dir/boot"
    cd "$temp_dir/boot/"
    if file "$temp_dir/initrd.img" | grep -q "LZ4"; then
        lz4 -d "$temp_dir/initrd.img" "$temp_dir/initrd.img.uncompressed" &>/dev/null
        cpio -idmv < "$temp_dir/initrd.img.uncompressed" &>/dev/null
    else
        zcat "$temp_dir/initrd.img" | cpio -idmv &>/dev/null
    fi
    local fstab="$(find ./ -type f -name 'fstab.*')"
    if [ ! -z "$fstab" ]; then
        cp "$fstab" "$script_path/magisk_files/fstab"
    fi
    cd $script_path

    rm -rf "$temp_dir"
}

get_props() {
    local REGEX="s/^$1=//p"
    local FILE="$script_path/magisk_files/build.prop"

    cat $FILE 2>/dev/null | dos2unix | sed -n "$REGEX" | head -n 1
}

clean_files() {
    patched_name="magisk_$(get_props "ro.build.product")_$(tr -dc A-Za-z0-9 </dev/urandom | head -c 5).img"

    # Move patched boot.img to output folder
    mv "$script_path/magisk_files/new-boot.img" "$script_path/out/$patched_name"

    # Clean Magisk files
    rm -rf "$script_path/magisk_files/"
}

patch_boot() {
    check_dependencies

    echo "Getting needed files from Magisk and zip package..."
    get_files

    echo "Patching Magisk util scripts..."
    patch_scripts

    echo "Patching boot.img..."
    setup_env
    sh "$script_path/magisk_files/boot_patch.sh" "$script_path/magisk_files/boot.img" &>/dev/null

    clean_files
    echo "Done! Patched boot.img can be found at out/${patched_name}"
}

patch_boot
