# LOGIC_replication — ZFS dataset snapshotting and replication logic

> **Compact, not incomplete.** Remove sections with no content. Never remove rules, edge cases, or reference rows to save space.

---

## Rules
> Hard constraints. AI must follow these unconditionally.

| Rule | Detail |
|------|--------|
| No Spaces in Datasets | Source datasets must not contain space characters. Otherwise, the pre-run check fails. |
| Non-empty Datasets | The source dataset must contain data (used size > 0B) to be processed. |
| ZFS & Sanoid Dependency | Requires `zfs` utilities and `/usr/local/sbin/sanoid` to be available. |
| Syncoid Dependency | Remote replication requires `syncoid` on the remote host. |
| Configuration Symlink | Must symlink `/etc/sanoid/sanoid.defaults.conf` into the dataset-specific config directory. |
| Self-Contained Log Rotation | Logs must be rotated using size checks and sequential backup index renames. |

---

## Reference
> Lookup tables. No prose.

| Item | Value | Notes |
|------|-------|-------|
| Syncoid strict-mirror flags | `-r --no-sync-snap --delete-target-snapshots --force-delete` | Used when `syncoid_mode="strict-mirror"` |
| Syncoid basic flags | `-r --no-sync-snap` | Used when `syncoid_mode="basic"` |
| Local destination name | `${destination_local_dataset}/${source_dataset//\//_}` | Slashes in source dataset are replaced with underscores |
| Remote destination name | `${destination_remote_dataset}/${source_dataset//\//_}` | Slashes in source dataset are replaced with underscores |
| Sanoid State File | `${sanoid_config_dir}sanoid_state.txt` | Stores the list of datasets from the previous run to clean up stale configs |
| Logging Format | `[YYYY-MM-DD HH:MM:SS] [LEVEL] msg` | Prefix timestamp and level (INFO/WARN/ERROR) to all log lines |

---

## Edge Cases
> Only document cases that are non-obvious or have caused bugs.

- **Stale Sanoid Configurations**: If datasets are removed from `source_datasets`, their config directories under `sanoid_config_dir` are deleted during the cleanup step to prevent orphaned configuration files.
- **SSH BachMode Check**: Remote connection verification uses `ssh -o BatchMode=yes -o ConnectTimeout=5` to prevent hanging scripts when remote hosts are down.
- **Dry-run Mode**: If `dry_run="yes"`, ZFS dataset path creation, autosnap/autoprune actions, and syncoid commands are simulated via `echo` and not executed. This covers all destructive operations.
- **Log Directory Creation**: Automatically creates the parent directory of `$log_file` if it does not exist before writing any log messages.

---

*v0.0.1 — 2026-06-08*
