# STANDARDS_interface — CLI and Notification specifications for Unraid ZFS Snapshot Manager

---

## Rules

> Hard constraints for this domain. AI must follow unconditionally.

| Rule | Detail |
|------|--------|
| Severity Levels | Notifications must map success to `normal` and failures to `warning`. |
| Interactive Prompts | Prompts must expect explicit `yes`/`no` or enter-defaults. |

---

## Interface Reference

### Unraid Notification Schema

| Field | Value | Purpose |
|-------|-------|---------|
| `-s` | `"Backup Notification"` or `"Restore Notification"` | Subject header of notification |
| `-d` | Custom multi-line string containing status of datasets | Description details |
| `-i` | `"normal"` or `"warning"` | Notification severity/icon |

### Discord Embed Schema

| JSON Parameter | Value | Purpose |
|----------------|-------|---------|
| `title` | `"✅ ZFS Snapshot & Replication: Success"` or `"❌ ZFS Snapshot & Replication: Failed"` | Embed title header with status icon |
| `description` | String list of each dataset result | Embed body containing summary lines |
| `color` | `3066993` (Green) or `15158332` (Red) | Left side bar color indicator |
| `timestamp` | UTC ISO8601 string | Time of script completion |

### Output Layout

| Item | Example / Pattern |
|------|-------------------|
| Dry run prefix | `DRY RUN: <command>` or `[DRY-RUN] Would <action>` |
| Error output prefix | `ERROR: <reason>` |
| Progress display | `pv` progress bar when available |

---

## Edge Cases

> Only document cases that are non-obvious or have caused regressions.

- **Empty Dataset Notification**: Do not trigger full replication notifications if dataset is empty and gets skipped; print message to stdout only.

---

*v0.0.1 — 2026-06-08*
