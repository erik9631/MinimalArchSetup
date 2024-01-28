#!/bin/bash
SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
export SCRIPT_DIR

# shellcheck source=includes/stage
source "$SCRIPT_DIR/includes/stage"

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
  test_package_installer)
    readarray -t package_list <<< "$(export_package_group "stage0" "pacman")"
    printf "%s\n" "${package_list[@]}"
    ;;
  test_best_display_config)
    get_best_display_config
    ;;
	*)
		echo "Invalid stage specified. Please use --stage <0,1,2>"
		exit 1
		;;
esac
