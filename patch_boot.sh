#!/bin/bash

# Sudo check
if [ `whoami` = root ];
then
    echo "Don't run this script as root"
    exit 1
fi

script_path="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

check_dependencies() {
    programs=("adb" "fastboot" "dos2unix" "unzip" "curl" "ed")

    for program in "${programs[@]}"; do
        if ! command -v "$program" >/dev/null 2>&1; then
            echo "$program is not installed. Please install it and run again this script"
            exit 1
        fi
    done
}

setup_env() {
    export KEEPVERITY=true
    export KEEPFORCEENCRYPT=true
}

patch_scripts() {
    # Get line
    line=$(grep -n '/proc/self/fd/$OUTFD' util_functions.sh | awk '{print $1}' | sed 's/.$//')

    # Add echo "$1" and delete the line
    (
    echo "$line"
    echo 'd'
    echo "$line-1"
    echo a
    echo '    echo "$1"'
    echo .
    echo wq
    ) | ed util_functions.sh > /dev/null 2>&1

    # Replace getprop
    sed -i 's/getprop/adb shell getprop/g' util_functions.sh
}

get_scripts() {
    #Create temp dir
    local temp_dir=$(mktemp -d)
    cd $temp_dir

    # Download magisk package
    wget $(curl -s https://api.github.com/repos/topjohnwu/Magisk/releases/latest | grep 'browser_download_url' | cut -d\" -f4) >/dev/null 2>&1

    # Unzip and get script and binaries
    unzip ./Magisk-v*.apk -d $temp_dir >/dev/null 2>&1
    cp $temp_dir/assets/boot_patch.sh $script_path/magisk_files/boot_patch.sh
    cp $temp_dir/assets/util_functions.sh $script_path/magisk_files/util_functions.sh
    cp $temp_dir/assets/stub.apk $script_path/magisk_files/stub.apk
    cp $temp_dir/lib/x86_64/libmagiskboot.so $script_path/magisk_files/magiskboot
    cp $temp_dir/lib/armeabi-v7a/libmagisk32.so $script_path/magisk_files/magisk32
    cp $temp_dir/lib/arm64-v8a/libmagisk64.so $script_path/magisk_files/magisk64
    cp $temp_dir/lib/arm64-v8a/libmagiskinit.so $script_path/magisk_files/magiskinit

    # Remove temp dir
    rm -rf $temp_dir

    cd $script_path/magisk_files/
}

clean_files() {
    find $script_path/magisk_files/ -type f ! -name "*.img" ! -name ".*" -delete
    find $script_path/magisk_files/ -type f -name "*.img" -exec mv {} $script_path/out/ \;
}

path_boot() {
    check_dependencies

    echo "Getting needed scripts and binaries from magisk package"
    get_scripts

    patch_scripts

    echo "Setting up env variables"
    setup_env

    clean_files
}

path_boot
