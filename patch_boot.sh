#!/bin/bash

# Sudo check
if [ `whoami` = root ];
then
    echo "Don't run this script as root"
    exit 1
fi

script_path="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
zip_package="$(realpath $1)"

check_dependencies() {
    programs=("adb" "fastboot" "dos2unix" "unzip" "curl" "ed" "brotli")

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

    # Replace build.prop path
    sed -i 's/\/system\/build.prop/.\/build.prop/g' util_functions.sh
}

get_files() {
    #Create temp dir
    local temp_dir="$(pwd)/temp"
    mkdir $temp_dir
    cd $temp_dir

    # Download magisk package
    wget $(curl -s https://api.github.com/repos/topjohnwu/Magisk/releases/latest | grep 'browser_download_url' | cut -d\" -f4) > /dev/null 2>&1

    # Unzip Magisk and get script and binaries
    unzip ./Magisk-v*.apk -d $temp_dir >/dev/null 2>&1
    mkdir $script_path/magisk_files/
    cp $temp_dir/assets/boot_patch.sh $script_path/magisk_files/boot_patch.sh
    cp $temp_dir/assets/util_functions.sh $script_path/magisk_files/util_functions.sh
    cp $temp_dir/assets/stub.apk $script_path/magisk_files/stub.apk
    cp $temp_dir/lib/x86_64/libmagiskboot.so $script_path/magisk_files/magiskboot
    cp $temp_dir/lib/armeabi-v7a/libmagisk32.so $script_path/magisk_files/magisk32
    cp $temp_dir/lib/arm64-v8a/libmagisk64.so $script_path/magisk_files/magisk64
    cp $temp_dir/lib/arm64-v8a/libmagiskinit.so $script_path/magisk_files/magiskinit
    find $temp_dir -delete

    # Extract rom: get boot.img and build.prop
    unzip $zip_package -d $temp_dir > /dev/null 2>&1
    cp $temp_dir/boot.img $script_path/magisk_files/boot.img
    brotli --decompress $temp_dir/system.new.dat.br -o $temp_dir/system.new.dat > /dev/null 2>&1
    python $script_path/sdat2img/sdat2img.py $temp_dir/system.transfer.list $temp_dir/system.new.dat $temp_dir/system.img > /dev/null 2>&1
    cd $temp_dir
    sudo debugfs -R "dump system/build.prop build.prop" system.img > /dev/null 2>&1
    cp $temp_dir/build.prop $script_path/magisk_files/build.prop

    # Remove temp dir
    rm -rf $temp_dir

    cd $script_path/magisk_files/
}

clean_files() {
    patched_name="magisk_patched_$(tr -dc A-Za-z0-9 </dev/urandom | head -c 5).img"

    # Move patched boot.img in out folder
    mv new-boot.img $script_path/out/$patched_name

    # Clean Magisk files
    rm -rf $script_path/magisk_files/
}

path_boot() {
    check_dependencies

    echo "Getting needed files from Magisk and zip package..."
    get_files
    echo ""

    echo "Patching Magisk utils script..."
    echo ""
    patch_scripts

    echo "Patching boot.img..."
    echo ""
    setup_env
    sh boot_patch.sh boot.img > /dev/null 2>&1

    clean_files
    echo "Done ! Patched boot.img can be found at out/${patched_name}"
}

path_boot
