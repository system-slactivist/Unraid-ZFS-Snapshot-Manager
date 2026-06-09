#!/bin/bash
#set -x  # Uncomment for debugging (enables trace mode for debugging each command execution)
set -euo pipefail
trap 'unraid_notify "Script terminated unexpectedly." "failure"' ERR

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Script for restoring replication of a ZFS dataset locally or remotely using ZFS                                                       # #
# #   (Requires Unraid 6.12 or above)                                                                                                       # #
# #   By SystemSlactivist                                                                                                                   # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

####################
# Configuration Loader
# ###################
config_file="$(dirname "$0")/zfs_manager.conf"
if [ ! -f "$config_file" ]; then
  echo "Error: Configuration file '$config_file' not found."
  echo "Please create it using zfs_manager.conf.example as a template."
  exit 1
fi
# shellcheck disable=SC1090
source "$config_file"

# Map unified config variables
log_file="$restore_log_file"
source_datasets=("${restore_source_datasets[@]}")
destination_dataset="$restore_destination_dataset"
destination_remote="$restore_destination_remote"

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

unraid_notify() {
    local message="$1"
    local flag="$2"
    local severity="normal"

    if [[ $flag == "success" ]]; then
        severity="normal"
        log_info "Notification: $message"
    elif [[ $flag == "failure" ]]; then
        severity="warning"
        log_error "Notification: $message"
    fi

    /usr/local/emhttp/webGui/scripts/notify -s "Restore Notification" -d "$message" -i "$severity"
}

####################
# Function: run_restore
# Executes a command or prints it for a dry run.
####################
run_restore() {
    if [ "$dry_run" = "yes" ]; then
        log_info "DRY RUN: $*"
    else
        eval "$*"
    fi
}

####################
# Function: send_with_progress
# Pipes zfs send to zfs receive, inserting pv if available.
####################
send_with_progress() {
    local snapshot="$1"
    local receive_cmd="$2"
    
    # Try to get the estimated stream size to display percentage and ETA
    local size=""
    if size=$(zfs send -nvP "${snapshot}" 2>/dev/null | awk '$1=="size"{print $2}'); then
        :
    fi
    
    # Check if pv is installed
    if ! command -v pv >/dev/null 2>&1; then
        log_warn "Note: 'pv' command not found. Installing 'pv' (e.g. via NerdTools plugin) will show a progress bar."
        eval "zfs send \"${snapshot}\" | ${receive_cmd}"
        return $?
    fi
    
    if [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
        eval "zfs send \"${snapshot}\" | pv -s \"${size}\" | ${receive_cmd}"
    else
        eval "zfs send \"${snapshot}\" | pv | ${receive_cmd}"
    fi
}

####################
# Function: select_snapshot
# Allows user to select a specific snapshot to restore.
####################
select_snapshot() {
    # 'dest' must be set in the caller (restore_snapshot)
    local snaps
    snaps=$(zfs list -t snapshot -o name -s creation -H "${dest}")
    echo "Available snapshots for ${source_dataset} (in ${dest}):"
    echo "$snaps"
    read -r -p "Enter the snapshot to restore (or press Enter to restore the latest): " selected_snapshot
    if [ -z "$selected_snapshot" ]; then
        selected_snapshot=$(echo "$snaps" | tail -n1)
        log_info "No snapshot selected. Defaulting to the latest snapshot: $selected_snapshot"
    fi
    log_info "Selected snapshot: $selected_snapshot"
    latest_snapshot="$selected_snapshot"
}

####################
# Function: check_existing_dataset
# Checks if the source dataset already exists before restoring.
####################
check_existing_dataset() {
    if zfs list -H "${source_dataset}" &>/dev/null; then
        log_warn "WARNING: The destination dataset ${source_dataset} already exists."
        read -r -p "Do you want to overwrite it? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            unraid_notify "Restoration aborted by user. ${source_dataset} already exists." "failure"
            exit 1
        fi
    fi
}

####################
# Function: restore_snapshot
# Restores the dataset from the selected snapshot, either locally or remotely.
####################
restore_snapshot() {
    # single base path for both local and remote
    local dest="${destination_dataset}/${source_dataset//\//_}"
    local remote_target="${remote_user}@${remote_server}:${dest}"

    # verify backup exists
    if ! zfs list -H "${dest}" &>/dev/null; then
        unraid_notify "Backup ${dest} not found." "failure"
        return 1
    fi

    select_snapshot
    check_existing_dataset

    # Local restore
    if [[ "$destination_remote" == "no" ]]; then
        local receive_cmd="zfs receive -F \"${dest}\" >> \"${log_file}\" 2>&1"
        if [[ "$dry_run" == "yes" ]]; then
            log_info "DRY RUN: zfs send \"${latest_snapshot}\" | pv | zfs receive -F \"${dest}\""
        else
            log_info "Restoring locally → ${dest}"
            if ! send_with_progress "${latest_snapshot}" "${receive_cmd}"; then
                unraid_notify "Local restore failed: ${source_dataset}" "failure"
                return 1
            fi
            unraid_notify "Local restore succeeded: ${source_dataset}" "success"
        fi
    fi

    # Remote restore
    if [[ "$destination_remote" == "yes" ]]; then
        local receive_cmd="ssh \"${remote_user}@${remote_server}\" zfs receive -F \"${dest}\" >> \"${log_file}\" 2>&1"
        if [[ "$dry_run" == "yes" ]]; then
            log_info "DRY RUN: zfs send \"${latest_snapshot}\" | pv | ssh \"${remote_user}@${remote_server}\" zfs receive -F \"${dest}\""
        else
            log_info "Restoring remotely → ${remote_target}"
            ssh "${remote_user}@${remote_server}" "zfs create -p \"${dest}\"" >> "$log_file" 2>&1 || true
            if ! send_with_progress "${latest_snapshot}" "${receive_cmd}"; then
                unraid_notify "Remote restore failed: ${source_dataset}" "failure"
                return 1
            fi
            unraid_notify "Remote restore succeeded: ${source_dataset}" "success"
        fi
    fi

    return 0
}

####################
# Function: run_for_each_dataset
# Iterates over each defined dataset, performing restoration tasks (including children).
####################
run_for_each_dataset() {
    rotate_logs
    log_info "Starting the restoration process for defined datasets."

    local final_status="success"
    local final_message="All datasets were restored successfully."

    for source_dataset in "${source_datasets[@]}"; do
        log_info "Processing dataset: ${source_dataset}"
        log_info "  backup location: ${destination_dataset}/${source_dataset//\//_}"

        if ! restore_snapshot; then
            final_status="failure"
            final_message="One or more datasets failed to restore."
        fi

        # if parent has children
        local dest="${destination_dataset}/${source_dataset//\//_}"
        if zfs list -H -r -o name "${dest}" | grep -q "^${dest}/"; then
            local child_list
            child_list=$(zfs list -H -r -o name "${dest}" | grep "^${dest}/")

            for child in $child_list; do
                local child_relative="${child#${dest}/}"
                local child_source="${source_dataset}/${child_relative//_//}"
                local child_snapshot
                child_snapshot=$(zfs list -t snapshot -o name -s creation -H "${child}" | tail -n1)
                local child_dest="${dest}/${child_relative}"
                local child_remote_target="${remote_user}@${remote_server}:${child_dest}"

                # LOCAL child
                if [[ "$destination_remote" == "no" ]]; then
                    local child_receive_cmd="zfs receive -F \"${child_dest}\" >> \"${log_file}\" 2>&1"
                    if [[ "$dry_run" == "yes" ]]; then
                        log_info "DRY RUN: zfs send \"${child_snapshot}\" | pv | zfs receive -F \"${child_dest}\""
                    else
                        send_with_progress "${child_snapshot}" "${child_receive_cmd}"
                        unraid_notify "Local child restore succeeded: ${child_source}" "success"
                    fi
                fi

                # REMOTE child
                if [[ "$destination_remote" == "yes" ]]; then
                    local child_receive_cmd="ssh \"${remote_user}@${remote_server}\" zfs receive -F \"${child_dest}\" >> \"${log_file}\" 2>&1"
                    if [[ "$dry_run" == "yes" ]]; then
                        log_info "DRY RUN: zfs send \"${child_snapshot}\" | pv | ssh \"${remote_user}@${remote_server}\" zfs receive -F \"${child_dest}\""
                    else
                        ssh "${remote_user}@${remote_server}" "zfs create -p \"${child_dest%/*}\"" >> "$log_file" 2>&1 || true
                        send_with_progress "${child_snapshot}" "${child_receive_cmd}"
                        unraid_notify "Remote child restore succeeded: ${child_source}" "success"
                    fi
                fi
            done
        fi
    done

    if [[ "$final_status" == "success" ]]; then
        unraid_notify "$final_message" "success"
        log_info "SUMMARY: $final_message"
    else
        unraid_notify "$final_message" "failure"
        log_info "SUMMARY: $final_message"
    fi
}

# Run restoration for each dataset
run_for_each_dataset