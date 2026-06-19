# REF_developer-reference — Developer reference tables

> Reference only. Rules live in `GUIDE_developer.md`.

---

## Reference

### Naming Conventions

| Type | Rule | Do | Don't |
|------|------|----|-------|
| Functions | `camelCase`, verb + noun | `getItemById`, `fetchSchema` | `doStuff`, `thing` |
| Variables | intent first, avoid generic names | `itemList`, `configData` | `data`, `tmp` |
| Booleans | prefix `is` / `has` / `can` / `should` | `isValid`, `hasItems` | `flag`, `state` |
| Event handlers | prefix `handle` + target + event | `handleSubmitClick`, `handleFilterChange` | `onClick`, `clickHandler` |
| Async functions | action-oriented, name what is fetched or saved | `fetchItemList`, `saveUserSettings` | `getData`, `loadStuff` |
| Data objects | context + subject + type | `UserAuthInfo`, `systemStateMap` | `payload`, `thingObject` |
| Files (logic) | responsibility-first, use role suffix when useful | `storage-manager.ts`, `board-renderer.ts` | `utils.ts`, `misc.ts` |

### Commands

| Command | Purpose |
|---------|---------|
| `bash ZFS_Replication.sh` | Local execution (set dry_run="yes" to simulate) |
| `shellcheck ZFS_Replication.sh ZFS_Restore.sh` | Run static analysis syntax check |
| `N/A` | Production build |
| `N/A` | Sync version across files |

### Version

| Item | Detail |
|------|--------|
| Source of truth | `AGENTS.md` |
| Bump command | `N/A` |
| Files auto-updated | `AGENTS.md`, `docs/*.md` |

### Key Configuration Variables

| Variable | Default Value | Notes |
|----------|---------------|-------|
| `notification_type` | `"all"` | Can be `"all"`, `"error"`, or `"none"` |
| `dry_run` | `"no"` / `"yes"` | Safety check flag |
| `syncoid_mode` | `"strict-mirror"` | Can be `"strict-mirror"` or `"basic"` |
| `auto_snapshots` | `"yes"` | Enable automatic snapshot generation |
| `replication_log_file` | `"/var/log/zfs_replication.log"` | Path to the ZFS replication script log |
| `restore_log_file` | `"/var/log/zfs_restore.log"` | Path to the ZFS restore script log |
| `log_max_size_mb` | `"5"` | Max log file size in MB before rotation |
| `log_backups` | `"3"` | Number of rotated log backups to keep |
| `restore_source_datasets` | `("cache/appdata")` | Array of source datasets to restore |
| `restore_destination_dataset` | `"vault/replication"` | Parent backup dataset to restore from |
| `restore_destination_remote` | `"no"` / `"yes"` | Restoring from a remote server flag |
| `discord_notifications` | `"yes"` / `"no"` | Enable/disable Discord webhook alerts |
| `discord_webhook_url` | `"https://discord.com/..."` | Target Discord channel Webhook URL |

---

*v0.0.1 — 2026-06-08*
