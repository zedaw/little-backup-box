#!/usr/bin/env bash

# IMPORTANT:
# Run the install-little-backup-box.sh script first
# to install the required packages and configure the system.

# Specify devices and their mount points
STORAGE_DEV=$(mount | grep backupdisk | awk '{print $1}' | cut -d"/" -f3)
STORAGE_MOUNT_POINT="/media/backupdisk"
CARD_MOUNT_POINT="/media/card"

checkBackupDiskMounted() {
  # Set the ACT LED to heartbeat
  sudo sh -c "echo heartbeat > /sys/class/leds/led0/trigger"

  if mount | grep backupdisk > /dev/null; then
    echo "BackupDisk $STORAGE_DEV is mounted on $STORAGE_MOUNT_POINT"
    # Set the ACT LED to blink at 1000ms to indicate that the storage device has been mounted
    sudo sh -c "echo timer > /sys/class/leds/led0/trigger"
    sudo sh -c "echo 1000 > /sys/class/leds/led0/delay_on"
  else
    echo "BackupDisk is not found!"
    sudo sh -c "echo mmc0 > /sys/class/leds/led0/trigger"
    exit -1
  fi
} 

findAllUsbCards() {
  USB=($(ls -l /dev/disk/by-id | grep .*usb.*part | awk '{print $9}'));
}

selectUsbCard() {
  MAX_ITEM_NUMBER=${#USB[*]}
  if [ $MAX_ITEM_NUMBER -lt 1 ]; then
    echo "No USB device found. Ensure a device is inserted."
    exit -1
  fi

  if [ $MAX_ITEM_NUMBER == 1 ]; then
     ITEM_NUMBER=1
  else
    INDEX=1
    for i in ${USB[@]}
    do
      echo "[$INDEX] $i"
      ((INDEX++))
    done 

    while true; do
      read -p "Select the device to use : " ITEM_NUMBER 
      if [ $ITEM_NUMBER -gt 0 -a $ITEM_NUMBER -le $MAX_ITEM_NUMBER ]; then
        break;
      fi
      echo "Invalid choice, accepted values are [1-$MAX_ITEM_NUMBER]"
    done
  fi

  USB_SELECTED=${USB[($ITEM_NUMBER -1)]}
}

getUsbDeviceInfos() {
  CARD_LABEL=$(ls -l /dev/disk/by-id/ | grep $USB_SELECTED | awk '{print $9}');
  CARD_DEV=$(ls -l /dev/disk/by-id/ | grep $USB_SELECTED | awk '{print $11}' | cut -d"/" -f3);
  CARD_UUID=$(ls -l /dev/disk/by-uuid/ | grep $CARD_DEV | awk '{print $9'}); 
  echo Device Name : $CARD_LABEL
  echo Device Link : $CARD_DEV 
  echo Device UUID : $CARD_UUID
}

assignUUID() {
  if [ ! -z $CARD_UUID ]; then
    read -p "CARD ID is $CARD_UUID ok?" key
  else
    CARD_UUID=$(hexdump -n 4 -e '"%X"' /dev/random);
    read -p "generated CARD ID is $CARD_UUID ok?" key
  fi
}

continueOrExit() {
  while true; do
    read -p "Do you want to continue (Y) or exit (N) ? " continueResponse
    if [ "Y" == "$continueResponse" -o "y" == "$continueResponse" ]; then
      break;
    else
      exit 0;
    fi
  done
}

mountUsbDisk() {
  # Set the ACT LED to heartbeat
  sudo sh -c "echo heartbeat > /sys/class/leds/led0/trigger"

  # Wait for a USB storage device (e.g., a USB flash drive)
  STORAGE=$(ls /dev/* | grep $STORAGE_DEV | cut -d"/" -f3)
  while [ -z ${STORAGE} ]
    do
    sleep 1
    STORAGE=$(ls /dev/* | grep $STORAGE_DEV | cut -d"/" -f3)
  done

  # When the USB storage device is detected, mount it
  mount /dev/$STORAGE_DEV $STORAGE_MOUNT_POINT

  # Set the ACT LED to blink at 1000ms to indicate that the storage device has been mounted
  sudo sh -c "echo timer > /sys/class/leds/led0/trigger"
  sudo sh -c "echo 1000 > /sys/class/leds/led0/delay_on"
}

mountCard() {
  if mount | grep "/dev/$CARD_DEV" > /dev/null; then
    CARD_MOUNT_POINT=$(sudo mount | grep "/dev/$CARD_DEV" | awk '{print $3}';)
    echo "USB Card /dev/$CARD_DEV is already mounted on $CARD_MOUNT_POINT"
  else
    echo "Mount USB Card on $CARD_MOUNT_POINT"
    sudo mount /dev/$CARD_DEV $CARD_MOUNT_POINT
  fi

  # # Set the ACT LED to blink at 500ms to indicate that the card has been mounted
  sudo sh -c "echo 500 > /sys/class/leds/led0/delay_on"

  if [ -z $CARD_UUID ]; then
    # Create the CARD_ID file containing a random 8-digit identifier if doesn't exist
    if [ ! -f $CARD_MOUNT_POINT/CARD_ID ]; then
      CARD_UUID=$(hexdump -n 4 -e '"%X"' /dev/random);
      echo $CARD_UUID > $CARD_MOUNT_POINT/CARD_ID
    fi
    # Read the 8-digit identifier number from the CARD_ID file on the card
    # and use it as a directory name in the backup path
    read -r CARD_UUID < $CARD_MOUNT_POINT/CARD_ID
  fi

  BACKUP_PATH=$STORAGE_MOUNT_POINT/backup/card/"$CARD_UUID"
}

unmountCard() {
  sudo umount $CARD_MOUNT_POINT
  echo "USB Card can be safely removed"
}

backup() {
  # Perform backup using rsync
  rsync -avh --stats --human-readable --info=progress2 $CARD_MOUNT_POINT/ $BACKUP_PATH
  # Turn off the ACT LED to indicate that the backup is completed
  sudo sh -c "echo mmc0 > /sys/class/leds/led0/trigger"
  # Shutdown
  sync
  #shutdown -h now
}

checkBackupDiskMounted
findAllUsbCards
selectUsbCard
echo "---------------------------------------------------------"
echo "USB Card found"
echo "---------------------------------------------------------"
getUsbDeviceInfos
mountCard
echo "---------------------------------------------------------"
echo "Backup path = $BACKUP_PATH"
echo "---------------------------------------------------------"
continueOrExit
backup
unmountCard

read -p "Press a key " key
