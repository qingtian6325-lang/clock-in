# Implementation Plan - Attendance Admin Edit/Delete & 14-Hour Auto-Timeout

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide an "Edit and Delete Record" column in the admin portal to modify or delete punches, and implement a 14-hour auto-timeout in the database to prevent punch blocking when employees forget to clock out.

**Architecture:**
- **Database Layer (`supabase/schema.sql`)**: Add RPC functions `admin_delete_record` and `admin_update_record`. Enhance `clock` RPC to detect when previous clock-in was >14 hours ago, auto-close the expired shift, and record the new clock-in. Update `active_now` to exclude punches older than 14 hours.
- **Admin Frontend (`docs/admin.html`)**: Add a new column `Edit and Delete Record` to `#adminTable`. Implement edit modal dialog and delete confirmation invoking the corresponding Supabase RPCs, refreshing the records list upon completion.

**Tech Stack:** Vanilla JavaScript (ES6+), HTML5, CSS3, PostgreSQL (Supabase PL/pgSQL).

**Spec:** [`docs/superpowers/specs/2026-10-26-attendance-edit-and-autoclockout-design.md`](file:///c:/Users/hp/Documents/antigravity/optimistic-darwin/docs/superpowers/specs/2026-10-26-attendance-edit-and-autoclockout-design.md)

## Global Constraints
- Target timezone is `Asia/Kuala_Lumpur` (UTC+8).
- Admin functions must authenticate via `admin_pin` checked against `settings` table.
- HTML/JS must remain vanilla with zero external build step (GitHub Pages static host).
- Table column header name must be exactly `Edit and Delete Record` as requested by user.

## Review Focus
- Attempting to delete a non-existent record should return `{ ok: false, msg: 'Record not found' }`.
- Updating a record with invalid timestamp or action should be safely caught and rejected.
- Clocking in when last punch is >14 hours ago should auto-insert an `out` record at `v_last_ts + interval '14 hours'` and proceed with the new `in` punch.
- Editing a record's timestamp (e.g. from 20:05 to 18:05) should properly affect the dashboard calculations without corrupting the timeline.

---

### Task 1: Update Supabase Schema (`supabase/schema.sql`)

**Files:**
- Modify: `supabase/schema.sql`

**Steps:**
- [ ] Add `admin_delete_record(p_admin_pin text, p_record_id bigint)` RPC function with PIN check.
- [ ] Add `admin_update_record(p_admin_pin text, p_record_id bigint, p_action text, p_ts text)` RPC function with PIN check, timestamp parsing, and action check.
- [ ] Update `clock(...)` RPC function: when `p_action = 'in'` and last punch was `in`, check if `now() - v_last_ts > interval '14 hours'`. If so, auto-insert `out` at `v_last_ts + interval '14 hours'` with note `'auto clock-out (14h limit)'`, set `v_last := 'out'`, and proceed to insert the new `in`.
- [ ] Update `active_now()` RPC function: add condition `and (now() - r.ts) <= interval '14 hours'`.
- [ ] Grant `execute` on `admin_delete_record` and `admin_update_record` to `anon, authenticated`.

---

### Task 2: Add "Edit and Delete Record" Column & Modal in Admin Portal (`docs/admin.html`)

**Files:**
- Modify: `docs/admin.html`

**Steps:**
- [ ] Update table header in `#adminTable`: add `<th>Edit and Delete Record</th>`.
- [ ] Update table row rendering in `renderRecords()`: append a cell with `✏️ Edit` and `🗑️ Delete` buttons for each record.
- [ ] Add CSS styles for `.btn-edit`, `.btn-del`, and the Edit modal (`#editRecModal`).
- [ ] Add HTML structure for Edit Record modal (Employee name/ID, Action dropdown, Datetime-local picker, Save and Cancel buttons).
- [ ] Implement `openEditRecord(recordId)` and `closeEditModal()`: populates fields with current values.
- [ ] Implement `saveRecordEdit()`: calls `sb.rpc('admin_update_record', ...)` and handles response.
- [ ] Implement `deleteRecord(recordId, name, time)`: confirms with user, calls `sb.rpc('admin_delete_record', ...)`, and refreshes the table.

---

### Task 3: Verification & Manual Integration Walkthrough

**Files:**
- Inspect: `supabase/schema.sql`
- Inspect: `docs/admin.html`

**Steps:**
- [ ] Validate SQL syntax and logic flow in `supabase/schema.sql`.
- [ ] Validate HTML/JS syntax in `docs/admin.html` using Node/browser script check.
- [ ] Provide clear, step-by-step instructions for the user on how to run the updated SQL in the Supabase Dashboard SQL Editor.
