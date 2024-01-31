#!/bin/bash
SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
export SCRIPT_DIR

# shellcheck source=includes/stage
source "$SCRIPT_DIR/includes/stage"

# shellcheck source=includes/utils
source "$SCRIPT_DIR/includes/utils"

args=("$@")

stage=0
stage_arg=0
shared_boot=0
export shared_boot


function check_stage(){
  if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    return 1
  fi
}


for ((i=0; i<${#args[@]}; i++)); do
  arg="${args[$i]}"
  case "$arg" in
      --stage)
        i=$((i+1))
        stage="${args[$i]}"
        if ! check_stage "$stage"; then
          echo "Invalid stage specified. Please use --stage <0,1,2>"
          exit 1
        fi
        stage_arg=1
      ;;
      --shared_boot)
        shared_boot=1
        echo "Shared boot kernel enabled. GRUB and KERNEL will not be installed."
        sleep 5
      ;;
      --test_package_installer)
        i=$((i+1))
        stage_arg="${args[$i]}"
        i=$((i+1))
        package_manager="${args[$i]}"
        readarray -t package_list <<< "$(export_package_group "$stage_arg" "$package_manager")"
        printf "%s\n" "${package_list[@]}"
        exit 0
      ;;
      --best_display_config)
        if ! get_best_display_config > "$HOME"/.config/hypr/monitors.conf; then
          echo "Getting best display config failed" >&2
          sleep 2
        fi
        exit 0
      ;;
      --handle_internet_connection)
        if ! handle_internet_connection; then
          exit 1;
        fi
        exit 0
      ;;
      --add_hibernation)
        # The resume hook is used for hibernation
        add_initramfs_resume_hook
        if ! grep -qE '^HOOKS=.*resume' /etc/mkinitcpio.conf; then
          echo "Failed to add resume hook to mkinitcpio.conf" >&2
          exit 1
        fi

        # Tells the kernel which swap partition is used for hibernation
        add_resume_device_to_kernel
        exit 0
      ;;
      --help)
        echo "Usage: $0 [--stage <0,1,2>] [--shared_boot] [--best_display_config] [--handle_internet_connection]"
        exit 0
      ;;
      *)
        echo "Unknown option: $arg"
        exit 1
      ;;
  esac
done

# Check for --stage argument
if (( stage_arg == 0)); then
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
	*)
		echo "Invalid stage specified. Please use --stage <0,1,2>"
		exit 1
		;;
esac
