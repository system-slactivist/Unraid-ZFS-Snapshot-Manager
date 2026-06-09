# LOGIC_restore — ZFS dataset restoration logic

> **Compact, not incomplete.** Remove sections with no content. Never remove rules, edge cases, or reference rows to save space.

---

## Rules
> Hard constraints. AI must follow these unconditionally.

| Rule | Detail |
|------|--------|
| Overwrite Confirmation | Must prompt user for confirmation before overwriting an existing destination dataset. |
| Progress Bar via PV | If `pv` is installed, display stream transfer progress using size estimate; fallback to direct pipe if missing. |
| Automatic Child Restore | Automatically detects and restores all child datasets under the backed up dataset path. |
| Backup Verification | Fails and terminates restore if backup dataset is not found at target backup path. |
| Self-Contained Log Rotation | Logs must be rotated using size checks and sequential backup index renames. |

---

## Reference
> Lookup tables. No prose.

| Item | Value | Notes |
|------|-------|-------|
| Size estimation command | `zfs send -nvP "${snapshot}"` | Extracts the `size` property for `pv` progress monitoring |
| Snapshot selection default | `tail -n1` of sorted snapshot list | Sorted by creation time, defaulting to the newest snapshot |
| Local receive command | `zfs receive -F "${dest}"` | Forces rollback/receive on target dataset |
| Remote receive command | `ssh "${remote_user}@${remote_server}" zfs receive -F "${dest}"` | Runs receive command over SSH |
| Logging Format | `[YYYY-MM-DD HH:MM:SS] [LEVEL] msg` | Prefix timestamp and level (INFO/WARN/ERROR) to all log lines |

---

## Edge Cases
> Only document cases that are non-obvious or have caused bugs.

- **Interactive Selection**: Selecting snapshots requires user input. This script is intended for interactive CLI usage.
- **Child Path Translation**: Slashes in child dataset paths are converted back and forth: `${destination_dataset}/${source_dataset//\//_}` holds child snapshots, and child relative paths are rebuilt using `child_relative="${child#${dest}/}"` and `child_source="${source_dataset}/${child_relative//_//}"`.
- **Log Directory Creation**: Automatically creates the parent directory of `$log_file` if it does not exist before writing any log messages.

---

*v0.0.1 — 2026-06-08*
