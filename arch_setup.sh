#!/bin/bash
SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
echo "script dir is $SCRIPT_DIR"

#TODO
# copy vmstarthyprland to /bin/
# copy /etc/NetworkManager/wifi_backend.conf to /etc/NetworkManager/conf.d/wifi_backend.conf
# copy /etc/NetworkManager/dhcp-client.conf to /etc/NetworkManager/conf.d/wifi_backend.conf
# Install catpucino rofi theme --- also done manually
# Install kvantum theme --- Done mannually
# Autostart the polkit-kde-agent


# shellcheck source=includes/network
source "$SCRIPT_DIR/includes/network"
# shellcheck source=includes/common
source "$SCRIPT_DIR/includes/common"
# shellcheck source=includes/package_installer
source "$SCRIPT_DIR/includes/package_installer"


# Define the required packages
BASIC_PACKAGES="vim dhcpcd iwd iw sudo rtkit bluez bluez-utils networkmanager"
DISPLAY_SERVER_PACKAGES="wayland"
ARCHIVERS="zip unzip ark"
SYSTEM_TOOLS="htop grim slurp wl-clipboard"
DAEMONS="dunst pipewire pipewire-pulse pipewire-jack pipewire-alsa xdg-desktop-portal-hyprland polkit-kde-agent"
VISUAL="waybar qt5ct qt6ct qt4ct papirus-icon-theme kvantum nerd-fonts"
GUI_APPS="thunar thunar-archive-plugin kate pavucontrol blueman network-manager-applet"
YAY="hyprland Hyprpicker waypaper libfuse2 swww nwg-look nwg-displays wlr-randr google-chrome rofi-lbonn-wayland-git catppuccin-gtk-theme-mocha catppuccin-gtk-theme-macchiato catppuccin-gtk-theme-frappe catppuccin-gtk-theme-latte"
TERMINAL="kitty"
# wlr-randr depedency for nwg-displays

# clone github.com/catppuccin/Kvantum and install the theme

export BASIC_PACKAGES
export DISPLAY_SERVER_PACKAGES
export FILE_MANAGER
export WINDOW_MANAGER
export BASIC_PACKAGES
export ARCHIVERS
export SYSTEM_TOOLS
export TERMINAL
export THEME
export UTILITIES
export SCRIPT_DIR

get_boot_mode() {
    if [ -f "/sys/firmware/efi/fw_platform_size" ]; then
        echo "UEFI"
    else
        echo "BIOS"
    fi
}
export -f get_boot_mode

get_grub_target() {
    local architecture boot_mode target
    architecture=$(uname -m)
    boot_mode=$(get_boot_mode)

    case "$architecture" in
        # ARM architectures
        arm*)
            target="arm-uboot"
            ;;
        aarch64)
            target="arm64-efi"
            ;;
        # x86 architectures
        i*86)
            if [[ "$boot_mode" == "UEFI" ]]; then
                target="i386-efi"
            else
                target="i386-pc"
            fi
            ;;
        x86_64)
            if [[ "$boot_mode" == "UEFI" ]]; then
                target="x86_64-efi"
            else
                # Assuming BIOS mode
                target="i386-pc"
            fi
            ;;
        # Unknown architecture
        *)
            echo "Unknown architecture: $architecture" >&2
            return 1
            ;;
    esac

    echo "$target"
}
export -f get_grub_target

get_current_stage_from_var() {
    local stage
    stage=$(ls /var/install | grep -Eo 'stage[0-9]' | grep -Eo '[0-9]')
    
    if [[ -n $stage ]]; then
        echo "$stage"
    else
        >&2 echo "No stage found."
        return 1  # Return an error code if no stage is found.
    fi
}
export -f get_current_stage_from_var

# Function for checking if the user is root
check_root_user() {
  if [ "$(id -u)" != "0" ]; then
    echo "Error: This script must be run as root"
    exit 1
  fi
}
export -f check_root_user

install_and_configure_grub() {
  set -e
  echo "Installing GRUB bootloader..."
  pacman -S --noconfirm grub efibootmgr
  local target
  local confirmation
  target=$(get_grub_target)

  if [[ $? != 0 ]]; then
    echo "Unknown architecture"
    exit 1
  fi

  echo "grub target is: $target"

  if ! ask_for_confirmation "Is this the correct target?"; then
    exit 1
  fi

  if grub-install --target="$target" --efi-directory=/boot --bootloader-id=GRUB; then
    echo "GRUB installed successfully."
  else
    echo "GRUB installation failed." >&2
    exit 1
  fi

  if grub-mkconfig -o /boot/grub/grub.cfg; then
    echo "GRUB configuration generated successfully."
  else
    echo "GRUB configuration generation failed." >&2
    exit 1
  fi

  echo "GRUB installation and configuration complete."
}
export -f install_and_configure_grub

enable_network(){
  systemctl enable dhcpcd
  systemctl enable iwd
}
export -f enable_network

install_yay_for_all() {
  local yay_dir

  if [[ $EUID -eq 0 ]]; then
    echo "This script should not be run as root."
    return 1
  fi
  # Install required packages for building from AUR
  sudo pacman -Sy --noconfirm --needed base-devel git

  # Clone yay repository to a temporary directory
  yay_dir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay.git "$yay_dir"
  pushd "$yay_dir"
  makepkg -si --noconfirm --needed
  popd
  # Cleanup the source directory
  rm -rf "$yay_dir"

  echo "yay is now available for all users."
}

is_time_synced(){
  local sync_status
  # Parse synchronization status and return error if not synchronized
  sync_status=$(timedatectl show --property=NTPSynchronized --value)
  if [ "$sync_status" != "yes" ]; then
      echo "Error: Time synchronization failed, NTPSynchronized is set to $sync_status" >&2
      return 1
  fi
}

synchronize_time() {
    # Create the timesyncd configuration content
    local ntp_config="[Time]\nNTP=time.google.com"

    # Write the configuration to /etc/systemd/timesyncd.conf
    echo -e "$ntp_config" | tee /etc/systemd/timesyncd.conf > /dev/null

    # Check for errors during writing
    if [ $? -ne 0 ]; then
        echo "Error: Could not write to /etc/systemd/timesyncd.conf" >&2
        return 1
    fi

    # Restart the systemd-timesyncd service
    echo "Restarting systemd-timesyncd service to apply changes..." >&2
    sudo systemctl restart systemd-timesyncd.service

    # Wait for the service to be active
    while ! systemctl is-active --quiet systemd-timesyncd.service; do
        echo "Waiting for systemd-timesyncd service to start..." >&2
        sleep 1
    done

    # Check the status using timedatectl
    timedatectl status

    if ! is_time_synced; then
        echo "Error: Time synchronization failed." >&2
        return 1
    fi

    echo "Time synchronization completed successfully." >&2
    return 0
}

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
    echo "Time is not synchronized. Synchronizing time..."
    if ! synchronize_time; then
      echo "Time synchronization failed."
      exit 1
    fi
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
  pacman -S --noconfirm \$BASIC_PACKAGES
  
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
  sudo pacman -S --noconfirm $GUI_APPS $ARCHIVERS $SYSTEM_TOOLS $TERMINAL

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
  pacman -S --noconfirm $DAEMONS $VISUAL
  yay -S --noconfirm $YAY

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
		echo "Invalid stage specified. Please use --stage 0 or --stage 1."
		exit 1
		;;
esac
