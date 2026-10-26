# Design Document: Attendance Admin Edit/Delete & 14-Hour Auto-Timeout

## 1. Intent & Context
In the current attendance cloud system:
- Admins can backfill (`admin_add_record`), but cannot modify or delete erroneous punches (e.g., if an employee clocks out late at 20:05 instead of 18:05, backfilling 18:05 is ignored because monthly reports pick `max(out_ts)`).
- When employees forget to clock out, they remain in the `in` state. The next morning at 07:50 AM, clicking "Clock In" fails with `❌ You have already clocked in`, which frequently confuses staff.

This design introduces:
1. **Admin Records Edit & Delete**: Full control over individual punch records (edit time/action, delete incorrect records) directly in `docs/admin.html` and Supabase SQL.
2. **14-Hour Auto-Timeout & Anti-Block Mechanism**: When an employee was clocked in >14 hours ago (or on a prior day without clocking out), attempting to clock in the next day will not be blocked; the system auto-settles the expired shift and admits the new clock-in. Furthermore, employees drop off "On-site now" if clocked in >14 hours.

---

## 2. Goals & Non-Goals

### Goals
- Allow admins to edit the timestamp and action of any record in `admin.html`.
- Allow admins to delete any record in `admin.html`.
- Prevent employees from being locked out on the next morning if they forgot to clock out yesterday (if last punch was `in` > 14 hours ago).
- Keep `active_now` ("On-site now") clean by automatically excluding punches older than 14 hours.
- Maintain full compatibility with `scripts/monthly_report.py` and `send-dashboard`.

### Non-Goals
- Real-time background daemon (no 24/7 dedicated server; operations remain serverless via PostgreSQL functions and client-side triggers).

---

## 3. Detailed Architecture & Changes

### A. Database Layer (`supabase/schema.sql`)
1. **`admin_delete_record(p_admin_pin text, p_record_id bigint)`**:
   - Validates admin PIN against `settings`.
   - Deletes the specified row from `records`.
   - Grants execute permission to `anon, authenticated`.

2. **`admin_update_record(p_admin_pin text, p_record_id bigint, p_action text, p_ts text)`**:
   - Validates admin PIN against `settings`.
   - Validates `p_action in ('in', 'out')`.
   - Validates timestamp parsing.
   - Updates `records` setting `action = p_action, ts = v_ts, note = 'edited by admin' where id = p_record_id`.
   - Grants execute permission to `anon, authenticated`.

3. **`clock(p_emp_id bigint, p_action text, p_lat float, p_lng float)` update**:
   - If `p_action = 'in'` and last punch `v_last = 'in'`:
     - If `(now() - v_last_ts) > interval '14 hours'`:
       - Automatically insert an `out` record at `v_last_ts + interval '14 hours'` (with `note = 'auto clock-out (14h limit)'`).
       - Proceed to insert the new `in` record for today without blocking the employee.
     - Else: return `❌ You have already clocked in`.
   - If `p_action = 'out'` and `v_last = 'out'`:
     - Return `❌ You have already clocked out`.

4. **`active_now()` update**:
   - Add condition: `and (now() - r.ts) <= interval '14 hours'` so employees clocked in yesterday don't linger on today's on-site list.

---

### B. Admin Console UI (`docs/admin.html`)
1. **Records Table Actions Column**:
   - Add an `Actions` column to `#adminTable`.
   - For each record row, render:
     - ✏️ **Edit** button
     - 🗑️ **Delete** button
2. **Edit Record Modal**:
   - Modal pop-up showing:
     - Staff ID & Name (read-only)
     - Action type dropdown (`Clock In` / `Clock Out`)
     - Date & Time input (`datetime-local`)
     - Save and Cancel buttons.
   - On Save: calls `admin_update_record`, refreshes table and displays success message.
3. **Delete Record Confirmation**:
   - Clicking Delete prompts `confirm("Are you sure you want to delete this punch record?")`.
   - On Confirm: calls `admin_delete_record`, refreshes table and displays success message.

---

## 4. Verification & Testing Plan
- Test SQL functions in Supabase:
  - Add test record -> update timestamp -> verify updated.
  - Delete test record -> verify removed.
  - Test `clock` function with simulated >14h gap -> verify auto-out record inserted and new `in` recorded.
- Test `admin.html`:
  - Search records by staff/date.
  - Click Edit, modify time from 20:05 to 18:05, verify report and table display 18:05.
  - Click Delete, verify record removed.
