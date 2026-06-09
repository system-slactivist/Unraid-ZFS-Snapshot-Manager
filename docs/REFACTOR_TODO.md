# Refactor TODO — Unraid ZFS Snapshot Manager

> Working note for current refactoring tasks. Canonical rules: `GUIDE_developer.md`.

---

## ✅ Phase [N]: [Phase Title] (Done)
- [x] [Task description] (Done)

---

## 🚀 Phase 1: Shared Code Extraction (In Progress)

Objective: Eliminate code duplication between scripts.

- [ ] **1. Extract Shared Functions**
  - [ ] Extract `unraid_notify` helper function into a shared utility library.

---

## 🧊 On Hold / Backlog
- [ ] [Deferred task with reason]

---

## Safety & Verification
1. Zero-Loss Refactor Protocol: No behavioral changes allowed.
2. Test before and after every major edit.
3. Build must pass before commit.
