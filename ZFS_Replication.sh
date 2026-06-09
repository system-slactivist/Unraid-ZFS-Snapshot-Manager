#!/bin/bash
#set -x  # Uncomment for debugging (enables trace mode for debugging each command execution)
set -euo pipefail
trap 'unraid_notify "Script terminated unexpectedly." "failure"' ERR

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Script for snapshotting and/or replication of a ZFS dataset locally or remotely using ZFS                                             # #
# #   (Requires Unraid 6.12 or above)                                                                                                       # #
# #   Original by SpaceInvaderOne                                                                                                           # #
# #   Modified by SystemSlactivist                                                                                                          # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

####################
# Main Variables
####################

####################
# Logging Configuration
####################
log_file="/var/log/zfs_replication.log" # Path to the log file
log_max_size_mb="5"                     # Max size of log file before rotating
log_backups="3"                         # Number of rotated backups to keep

####################
# Dry-Run
# Enable simulation mode so the script reports intended actions without actually creating snapshots, pruning, or replicating.
####################
dry_run="no" # Set to "yes" to run in dry‑run mode, or "no" to perform real operations.

####################
# Unraid Notifications Configuration
# Configure how and when notifications are sent to the Unraid GUI.
####################
notification_type="all" # "all" for both success & failure, "error" for only failure, "none" for no notifications

####################
# ZFS Dataset Configuration
# Define the ZFS datasets (and their pools) that you want to process.
####################
source_datasets=("cache/appdata" "cache/unraid_scripts" "cache/compose") # Add all the pools/datasets you want to process here e.g. ("pool1/dataset1" "pool1/dataset2" "pool2/dataset3")

####################
# ZFS Snapshot Settings
# Enable having automatic snapshot capture and cleanup.
# Set the retention policy for ZFS snapshots.
####################
auto_snapshots="yes"      # Set to "yes" to automatically take snapshots when the script is ran or "no" to skip.
autoprune_snapshots="yes" # Set to "yes" to automatically remove snapshots beyond the retention policy set to "no" to disable retention and keep snapshots forever.

####################
# Retention policy
####################
snapshot_hours="0"  # Number of hourly snapshots to keep (0 = none)
snapshot_days="7"   # Number of daily snapshots to keep (0 = none)
snapshot_weeks="4"  # Number of weekly snapshots to keep (0 = none)
snapshot_months="3" # Number of monthly snapshots to keep (0 = none)
snapshot_years="0"  # Number of yearly snapshots to keep (0 = none)

####################
# Replication Settings
# Requires having a second ZFS pool that is either local or remote
####################
replication="yes" # Choose between "yes" for ZFS replication or "no" for just using snapshots.

####################
# Remote Server Configuration
# Configure settings if you plan to replicate data to a remote server.
####################
destination_remote="no"      # Set to "no" for local backup, "yes" for a remote backup or "both" to replicate locally and remotely.
remote_user="root"           # Remote server user (Unraid server typically uses "root")
remote_server="10.10.20.197" # Remote server's name or IP address

####################
# Replication Variables
# Remote or local variable will be ignored depending destination_remote value.
####################
destination_local_dataset="disk20/BACKUP_zfs"         # Local parent dataset under which the replicated data will reside (e.g. "pool/dataset")
destination_remote_dataset="vault/replication_remote" # Remote parent dataset under which the replicated data will reside (e.g. "pool/dataset")

####################
# Syncoid replication mode:
# "strict-mirror" - Mirrors the source dataset strictly, deleting snapshots in the destination that are not in the source.
# "basic" - Basic replication without extra flags; does not delete snapshots in the destination that are missing from the source.
####################
syncoid_mode="strict-mirror"

####################
# Advanced Variables
# These settings are typically set correctly by default and do not need to be changed.
####################
sanoid_config_dir="/mnt/user/system/sanoid/" # Location of the Sanoid configuration directory

####################
# Main Script
####################

log_message() {
  local level="$1"
  local msg="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local formatted="[$timestamp] [$level] $msg"
  echo "$formatted"
  
  local log_dir
  log_dir=$(dirname "$log_file")
  if [ ! -d "$log_dir" ]; then
    mkdir -p "$log_dir"
  fi
  echo "$formatted" >> "$log_file"
}

log_info() {
  log_message "INFO" "$1"
}

log_warn() {
  log_message "WARN" "$1"
}

log_error() {
  log_message "ERROR" "$1"
}

rotate_logs() {
  local max_size=$((log_max_size_mb * 1024 * 1024))
  if [ -f "$log_file" ]; then
    local size
    size=$(wc -c < "$log_file")
    if [ "$size" -ge "$max_size" ]; then
      log_info "Log file size exceeded threshold. Rotating logs..."
      for ((i=log_backups-1; i>=1; i--)); do
        if [ -f "${log_file}.${i}" ]; then
          mv "${log_file}.${i}" "${log_file}.$((i+1))"
        fi
      done
      mv "$log_file" "${log_file}.1"
      touch "$log_file"
      log_info "Log rotation complete."
    fi
  fi
}

####################
# Function: unraid_notify
# Sends notifications to the Unraid GUI based on the notification_type configuration.
# Usage: unraid_notify "<message>" "<success|failure>"
# ###################
unraid_notify() {
  local message="$1"
  local flag="$2"

  if [[ "$flag" == "success" ]]; then
    log_info "Notification: $message"
  else
    log_error "Notification: $message"
  fi

  # Exit if notifications are disabled
  if [[ "$notification_type" == "none" ]]; then
    return 0
  fi

  # Exit if only error notifications are enabled and the message is a success
  if [[ "$notification_type" == "error" && "$flag" == "success" ]]; then
    return 0
  fi

  # Determine notification severity based on the message type
  local severity="normal"
  if [[ "$flag" == "success" ]]; then
    severity="normal"
  else
    severity="warning"
  fi

  /usr/local/emhttp/webGui/scripts/notify -s "Backup Notification" -d "$message" -i "$severity"
}

####################
# Function: global_pre_run_checks
# Performs essential checks before processing any datasets.
####################
global_pre_run_checks() {
  # Ensure ZFS utilities are installed
  if ! command -v zfs &>/dev/null; then
    msg="ZFS utilities are not found. Ensure you are using Unraid 6.12 or above."
    unraid_notify "$msg" "failure"
    exit 1
  fi

  # Ensure Sanoid is installed
  if [ ! -x "/usr/local/sbin/sanoid" ]; then
    msg="Sanoid is not found or not executable. Please install Sanoid and try again."
    unraid_notify "$msg" "failure"
    exit 1
  fi

  # Validate boolean settings (replication, snapshots)
  for var in replication auto_snapshots autoprune_snapshots; do
    if [[ "${!var}" != "yes" && "${!var}" != "no" ]]; then
      msg="Invalid setting for $var: ${!var}. Must be 'yes' or 'no'."
      unraid_notify "$msg" "failure"
      exit 1
    fi
  done

  # Validate destination_remote can be "yes", "no", or "both"
  if [[ "$destination_remote" != "yes" && "$destination_remote" != "no" && "$destination_remote" != "both" ]]; then
    msg="Invalid setting for destination_remote: ${destination_remote}. Must be 'no', 'yes', or 'both'."
    unraid_notify "$msg" "failure"
    exit 1
  fi

  # Sanity‑check local & remote destination variables
  if [[ -z "$destination_local_dataset" ]]; then
    msg="You must set destination_local_dataset in the script."
    unraid_notify "$msg" "failure"
    exit 1
  fi
  if [[ ("$destination_remote" = "yes" || "$destination_remote" = "both") && -z "$destination_remote_dataset" ]]; then
    msg="You must set destination_remote_dataset when destination_remote is 'yes' or 'both'."
    unraid_notify "$msg" "failure"
    exit 1
  fi

  # Ensure at least one action is enabled
  if [[ "$replication" != "yes" && "$auto_snapshots" != "yes" ]]; then
    msg='Both replication and autosnap are disabled. Nothing to do.'
    unraid_notify "$msg" "failure"
    exit 1
  fi

  # If remote or both, validate SSH & syncoid
  if [[ "$destination_remote" = "yes" || "$destination_remote" = "both" ]]; then
    helper_check_remote
  fi
}

#####################
# Function: dataset_pre_run_checks
# Performs checks specific to each dataset, ensuring the dataset exists, is named correctly, and contains data.
# ###################
dataset_pre_run_checks() {
  # Verify the source dataset exists in the ZFS pool
  if ! zfs list -H "${source_dataset}" &>/dev/null; then
    msg="Error: The source dataset '${source_dataset}' does not exist."
    log_error "$msg"
    return 1
  fi

  # Ensure the dataset name does not contain spaces (required for autosnapshots)
  if [[ "${source_dataset}" == *" "* ]]; then
    msg="Error: The source dataset name '${source_dataset}' contains spaces. Rename the dataset and try again."
    log_error "$msg"
    return 1
  fi

  # Check if the dataset contains any data
  local used
  used=$(zfs get -H -o value used "${source_dataset}")
  if [[ ${used} == 0B ]]; then
    msg="The source dataset '${source_dataset}' is empty. Nothing to replicate."
    log_info "$msg"
    return 1
  fi
  
  return 0
}

####################
# Function: helper_check_remote
# Validates remote settings, SSH connectivity, and syncoid on the remote host.
####################
helper_check_remote() {
  # Only run when destination_remote is "yes" or "both"
  if [[ "$destination_remote" = "yes" || "$destination_remote" = "both" ]]; then
    # Ensure remote_user and remote_server are set
    if [ -z "$remote_user" ] || [ -z "$remote_server" ]; then
      msg="Remote user and server must be set when destination_remote is 'yes' or 'both'."
      unraid_notify "$msg" "failure"
      exit 1
    fi

    # Test SSH connection
    log_info "Checking remote server availability..."
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 \
      "${remote_user}@${remote_server}" \
      "echo 'SSH connection successful'" >> "$log_file" 2>&1; then
      msg="SSH connection failed. Verify remote details and SSH keys."
      unraid_notify "$msg" "failure"
      exit 1
    fi

    # Verify syncoid installation
    log_info "Verifying syncoid on remote..."
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 \
      "${remote_user}@${remote_server}" \
      "command -v syncoid >/dev/null 2>&1" >> "$log_file" 2>&1; then
      msg="Syncoid not found on ${remote_server}. Install it first."
      unraid_notify "$msg" "failure"
      exit 1
    fi
  else
    log_info "Replication target is local-only."
  fi
}

####################
# Function: helper_ensure_dataset_path
# Ensures the ZFS dataset hierarchy exists locally or remotely.
####################
helper_ensure_dataset_path() {
  local mode="$1"
  shift
  local path="$1"

  # Dry‑run: simulate creating dataset path
  if [ "$dry_run" = "yes" ]; then
    log_info "[DRY-RUN] Would ensure ${mode} dataset path exists: ${path}"
    return 0
  fi

  if [ "$mode" = "remote" ]; then
    # Create remote dataset path if missing
    if ! ssh "${remote_user}@${remote_server}" \
      "if ! zfs list -H \"${path}\" &>/dev/null; then zfs create -p \"${path}\"; fi" >> "$log_file" 2>&1; then
      log_error "Failed to create remote dataset ${path}"
      return 1
    fi
  else
    # Create local dataset path if missing
    if ! zfs list -H "${path}" &>/dev/null; then
      if ! zfs create -p "${path}" >> "$log_file" 2>&1; then
        log_error "Failed to create local dataset ${path}"
        return 1
      fi
    fi
  fi
}

####################
# Function: create_sanoid_config
# Generates a Sanoid configuration file for the dataset based on the snapshot retention policy.
####################
create_sanoid_config() {
  # Ensure the Sanoid config directory exists
  if [ ! -d "${sanoid_config_complete_path}" ]; then
    mkdir -p "${sanoid_config_complete_path}"
  fi

  # Symlink the global sanoid.defaults.conf if not already present
  if [ ! -e "${sanoid_config_complete_path}sanoid.defaults.conf" ]; then
    ln -s /etc/sanoid/sanoid.defaults.conf "${sanoid_config_complete_path}sanoid.defaults.conf"
  fi

  # Build the new Sanoid configuration content
  new_content="[${source_dataset}]
use_template = production
recursive = yes

[template_production]
hourly = ${snapshot_hours}
daily = ${snapshot_days}
weekly = ${snapshot_weeks}
monthly = ${snapshot_months}
yearly = ${snapshot_years}
autosnap = ${auto_snapshots}
autoprune = ${autoprune_snapshots}"

  # Update the Sanoid configuration file if there are changes
  if [ -f "${sanoid_config_complete_path}sanoid.conf" ]; then
    existing_content=$(cat "${sanoid_config_complete_path}sanoid.conf")
    if [ "$new_content" != "$existing_content" ]; then
      log_info "Differences found in Sanoid config, updating the config file."
      echo "$new_content" >"${sanoid_config_complete_path}sanoid.conf"
    else
      log_info "No differences found in Sanoid config, keeping the existing config."
    fi
  else
    log_info "Sanoid config file not found, creating a new one."
    echo "$new_content" >"${sanoid_config_complete_path}sanoid.conf"
  fi
}

####################
# Function: autosnap
# Creates automatic snapshots of the source dataset using Sanoid based on the retention policy.
####################
autosnap() {
  # Dry‑run: just simulate
  if [ "$dry_run" = "yes" ]; then
    log_info "[DRY-RUN] Would create snapshots for ${source_dataset}"
    return 0
  fi

  log_info "Creating automatic snapshots for ${source_dataset} and its children using Sanoid."
  if /usr/local/sbin/sanoid --configdir="${sanoid_config_complete_path}" --take-snapshots >> "$log_file" 2>&1; then
    return 0
  else
    log_error "Snapshot creation failed for ${source_dataset}."
    return 1
  fi
}

####################
# Function: autoprune
# Prunes old snapshots of the source dataset using Sanoid based on the retention policy.
####################
autoprune() {
  # Dry‑run: just simulate
  if [ "$dry_run" = "yes" ]; then
    log_info "[DRY-RUN] Would prune snapshots for ${source_dataset}"
    return 0
  fi

  log_info "Pruning snapshots for ${source_dataset} and its children using Sanoid."
  if /usr/local/sbin/sanoid --configdir="${sanoid_config_complete_path}" --prune-snapshots >> "$log_file" 2>&1; then
    return 0
  else
    log_error "Snapshot removal failed for ${source_dataset} and its children."
    return 1
  fi
}

####################
# Function: zfs_replication
# Uses ZFS (via syncoid) to replicate the source dataset locally, remotely, or both.
####################
zfs_replication() {
  local local_base="${destination_local_dataset}/${source_dataset//\//_}"
  local remote_base="${destination_remote_dataset}/${source_dataset//\//_}"
  local flags=(-r --no-sync-snap)

  case "${syncoid_mode}" in
  strict-mirror)
    flags+=(--delete-target-snapshots --force-delete)
    ;;
  basic) ;;
  *)
    log_error "Invalid syncoid_mode: ${syncoid_mode}"
    exit 1
    ;;
  esac

  local rep_success=true

  # Local replication
  if [[ "$destination_remote" = "no" || "$destination_remote" = "both" ]]; then
    if [[ "$dry_run" = "yes" ]]; then
      log_info "[DRY-RUN] Would ensure local dataset path: ${local_base}"
      log_info "[DRY-RUN] Would run: syncoid ${flags[*]} \"${source_dataset}\" \"${local_base}\""
    else
      if ! helper_ensure_dataset_path local "${local_base}"; then
        rep_success=false
      else
        log_info "Running local replication: syncoid ${flags[*]} \"${source_dataset}\" \"${local_base}\""
        if /usr/local/sbin/syncoid "${flags[@]}" "${source_dataset}" "${local_base}" >> "$log_file" 2>&1; then
          log_info "Local replication succeeded: ${source_dataset} → ${local_base}"
        else
          log_error "Local replication FAILED: ${source_dataset} → ${local_base}"
          rep_success=false
        fi
      fi
    fi
  fi

  # Remote replication
  if [[ "$destination_remote" = "yes" || "$destination_remote" = "both" ]]; then
    local remote_dest="${remote_user}@${remote_server}:${remote_base}"

    if [[ "$dry_run" = "yes" ]]; then
      log_info "[DRY-RUN] Would ensure remote dataset path: ${remote_base}"
      log_info "[DRY-RUN] Would run: syncoid ${flags[*]} \"${source_dataset}\" \"${remote_dest}\""
    else
      if ! helper_ensure_dataset_path remote "${remote_base}"; then
        rep_success=false
      else
        log_info "Running remote replication: syncoid ${flags[*]} \"${source_dataset}\" \"${remote_dest}\""
        if /usr/local/sbin/syncoid "${flags[@]}" "${source_dataset}" "${remote_dest}" >> "$log_file" 2>&1; then
          log_info "Remote replication succeeded: ${source_dataset} → ${remote_dest}"
        else
          log_error "Remote replication FAILED: ${source_dataset} → ${remote_dest}"
          rep_success=false
        fi
      fi
    fi
  fi

  if [ "$rep_success" = true ]; then
    return 0
  else
    return 1
  fi
}

####################
# Function: cleanup_unwanted_sanoid_configs
# Removes Sanoid configuration files for datasets that have been removed.
####################
cleanup_unwanted_sanoid_configs() {
  local sanoid_state_file="${sanoid_config_dir}sanoid_state.txt"
  local found_unwanted=false
  local dataset_trimmed

  log_info "Cleaning up stale Sanoid configs…"

  if [ -f "${sanoid_state_file}" ]; then
    mapfile -t previous_datasets < <(
      grep "^datasets:" "${sanoid_state_file}" |
        sed 's/datasets: //' |
        tr ' ' '\n'
    )
  else
    previous_datasets=()
  fi

  for dataset in "${previous_datasets[@]}"; do
    dataset_trimmed="$(echo "${dataset}" | xargs)"
    if [[ ! " ${source_datasets[*]} " =~ " ${dataset_trimmed} " ]]; then
      log_info "Removing config for ${dataset_trimmed}"
      local config_dir="${sanoid_config_dir}${dataset_trimmed//\//_}/"
      if [ -d "${config_dir}" ]; then
        if rm -rf "${config_dir}"; then
          log_info "Deleted ${config_dir}"
        else
          log_error "Failed to delete ${config_dir}"
        fi
        found_unwanted=true
      fi
    fi
  done

  if [ "${found_unwanted}" = false ]; then
    log_info "No stale configs found."
  fi

  log_info "Saving new state."
  echo "datasets: ${source_datasets[*]}" >"${sanoid_state_file}"
}

####################
# Function: run_for_each_dataset
# Iterates over each selected dataset, performing snapshotting and replication tasks sequentially.
####################
run_for_each_dataset() {
  rotate_logs
  log_info "=== Replicating to: local=${destination_local_dataset}, remote=${destination_remote_dataset} (mode=${destination_remote}) ==="
  log_info "Starting the processing of defined datasets."

  log_info "Performing global pre-run checks"
  global_pre_run_checks

  if [ "${#source_datasets[@]}" -eq 0 ]; then
    msg="No source datasets configured. Please set source_datasets in the script."
    unraid_notify "$msg" "failure"
    exit 1
  fi

  # Send initial summary notification
  local start_msg="ZFS Manager script is starting.
Operations: "
  if [ "$auto_snapshots" = "yes" ]; then start_msg+="Snapshots "; fi
  if [ "$replication" = "yes" ]; then start_msg+="Replication"; fi
  start_msg+="
Datasets:
"
  for ds in "${source_datasets[@]}"; do
    start_msg+=" - ${ds}
"
  done
  unraid_notify "${start_msg}" "success"

  declare -A snap_status
  declare -A rep_status

  for dataset in "${source_datasets[@]}"; do
    source_dataset="$dataset"
    
    if ! dataset_pre_run_checks; then
      snap_status["$dataset"]="Skipped (Pre-run failed)"
      rep_status["$dataset"]="Skipped (Pre-run failed)"
      continue
    fi

    sanoid_config_complete_path="${sanoid_config_dir}${dataset//\//_}/"

    snap_status["$dataset"]="Skipped"
    rep_status["$dataset"]="Skipped"

    log_info "Processing dataset: ${dataset}"
    if [ "$auto_snapshots" = "yes" ]; then
      log_info "Creating sanoid config for ${dataset}"
      create_sanoid_config
      log_info "Taking snapshots for ${dataset}"
      
      if autosnap; then
        snap_status["$dataset"]="Success"
        if [ "$autoprune_snapshots" = "yes" ]; then
          log_info "Pruning old snapshots for ${dataset}"
          if ! autoprune; then
            snap_status["$dataset"]="Success (Prune Failed)"
          fi
        fi
      else
        snap_status["$dataset"]="Failed"
      fi
    fi
  done

  if [ "$auto_snapshots" = "yes" ]; then
    cleanup_unwanted_sanoid_configs
  fi

  if [ "$replication" = "yes" ]; then
    log_info "Performing ZFS replication"
    for dataset in "${source_datasets[@]}"; do
      source_dataset="$dataset"
      if [[ "${rep_status["$dataset"]}" == *"Skipped (Pre-run failed)"* ]]; then
        continue
      fi
      if zfs_replication; then
        rep_status["$dataset"]="Success"
      else
        rep_status["$dataset"]="Failed"
      fi
    done
  fi

  # Send final summary notification
  local end_msg="ZFS Manager script completed.
Operations: "
  if [ "$auto_snapshots" = "yes" ]; then end_msg+="Snapshots "; fi
  if [ "$replication" = "yes" ]; then end_msg+="Replication"; fi
  end_msg+="
Dataset Results:
"
  
  local overall_status="success"
  for ds in "${source_datasets[@]}"; do
    local s_stat="${snap_status["$ds"]}"
    local r_stat="${rep_status["$ds"]}"
    
    end_msg+=" - ${ds}: "
    if [ "$auto_snapshots" = "yes" ]; then
      end_msg+="Snapshots: ${s_stat}"
    fi
    if [ "$auto_snapshots" = "yes" ] && [ "$replication" = "yes" ]; then
      end_msg+=" | "
    fi
    if [ "$replication" = "yes" ]; then
      end_msg+="Replication: ${r_stat}"
    fi
    end_msg+="
"
    
    if [[ "$s_stat" == *"Failed"* || "$r_stat" == *"Failed"* ]]; then
      overall_status="failure"
    fi
  done
  
  unraid_notify "${end_msg}" "${overall_status}"
}

####################
# Main Script Execution
####################
run_for_each_dataset
