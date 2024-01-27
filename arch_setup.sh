#!/bin/bash
SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)

#TODO
# Add nvidia drivers script
# Add script that installs firmware based on the laptop model

# shellcheck source=includes/network
source "$SCRIPT_DIR/includes/network"

# shellcheck source=includes/utils
source "$SCRIPT_DIR/includes/utils"

# shellcheck source=includes/package_installer
source "$SCRIPT_DIR/includes/package_installer"

# shellcheck source=includes/bootloader
source "$SCRIPT_DIR/includes/bootloader"

# clone github.com/catppuccin/Kvantum and install the theme

stage_zero(){
  # Check if the script is running as root
  local is_wireless
  local connection_state
  check_root_user
  if ! connection_state=$(handle_internet_connection); then
    exit 1
  fi
  is_wireless=$(echo "$connection_state" | grep -i -c 'wireless')

  if (( is_wireless )); then
    echo "Wireless connection detected."
  else
    echo "Wired connection detected."
  fi

  if ! is_time_synced; then
    echo "Time synchronization failed."
    exit 1
  fi

  
  if findmnt -M "/mnt" > /dev/null; then
    echo "/mnt is mounted. Installing kernel..."
  else
    echo "/mnt is not mounted."
	exit 1
  fi

  
  # Install the linux zen-kernel with firmware
  if ! pacstrap -K /mnt base linux-zen linux-firmware; then
    echo "Failed to install linux-zen and linux-firmware." >&2
    exit 1
  fi
  
  echo "Generating file system table..."
  genfstab -U /mnt >> /mnt/etc/fstab
  
  echo "Moving script to /mnt/opt/"
  cp -r "$SCRIPT_DIR"/. /mnt/opt/install/
  sudo chmod -R 777 /mnt/opt/install/

  echo "Copying network configuration..."
  if (( is_wireless )); then
    mkdir -p /mnt/var/lib/iwd && sudo cp -r /var/lib/iwd /mnt/var/lib/
  fi

  local hostname
  local username
  local password

  read -p 'Set your hostname: ' hostname
  read -p 'Set your username: ' username
  read -sp 'Set your root password: ' password
  
  export hostname
  export password
  export username
  
  echo "Changing rootdir"
  arch-chroot /mnt /bin/bash -c "
  

  # Sync pacman database
  pacman -Syy

  # Install basic packages
  install_pacman_packages \"stage0\"
  
  # Setup etc/host
  echo \"\$hostname\" > /etc/hostname
  echo \"root:\$password\" | chpasswd

  echo \"Setting up new user...\"
  useradd -m \$username
  echo \"\$username:\$password\" | chpasswd
  usermod -aG wheel \"\$username\"
  usermod -aG lp \"\$username\"
  usermod -aG dbus \"\$username\"
  sed -i '/^#\s*%wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^# //' /etc/sudoers


  
  # Uncomment en_US
  if ! sed -i '/^#.*en_US.UTF-8/s/^#//' /etc/locale.gen; then
    echo 'Uncomment failed'
    exit 1
  fi
  locale-gen
  
  if ! enable_network; then
    echo 'Enable network failed'
    exit 1
  fi
  systemctl enable systemd-timesyncd.service

  if ! install_and_configure_grub; then
    echo 'Grub installation failed'
    exit 1
  fi
  
  echo 'Preparing for stage 1...'
  mkdir /var/install/
  touch /var/install/stage1
  
  echo 'Stage 0 complete, rebooting into the system to run stage 1...'
  "
  sleep 5
  reboot
}

stage_one(){

  if ! is_internet_connected; then
    if ! handle_internet_connection; then
      echo "Internet is not connected. Please connect to the internet and run this script again with --stage 1."
      exit 1
    fi
  fi

  sudo pacman -Syy
  # Install file manager
  if ! install_pacman_packages "stage1"; then
    echo "Failed to install pacman packages"
    exit 1
  fi

  if ! install_yay_for_all; then
    echo "yay installation failed"
    exit 1
  fi

  echo "Updating stage file..."
  sudo mv /var/install/stage1 /var/install/stage2

  echo "All stage1 installations are complete."
  echo "Proceeding to stage2..."
  stage_two
}

# User specific services
stage_two(){
  if ! install_yay_packages "stage2"; then
    echo "installing yay packages failed"
    exit 1
  fi

  echo "Performing cleanup..."
  sudo rm -rf /opt/install
  sudo rm -rf /var/install
  exit 0
}

stage=0

# Check for --stage argument
if [[ "$1" == "--stage" ]]; then
	stage=$2
else
	potential_stage=$(get_current_stage_from_var)
	if (( $? == 0 )); then
    echo "Setting potential stage"
	  stage=$potential_stage
	fi
fi

echo "Stage is: $stage"

case $stage in
	0)
		stage_zero
		;;
	1)
		stage_one
		;;
  2)
    stage_two
    ;;
  test_package_installer)
    readarray -t package_list <<< "$(export_package_group "stage2" "yay")"
    printf "%s\n" "${package_list[@]}"
    ;;
	*)
		echo "Invalid stage specified. Please use --stage <0,1,2>"
		exit 1
		;;
esac
