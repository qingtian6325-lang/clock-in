# 📋 Company Attendance System (Cloud)

🌐 **Live demo:** https://qingtian6325-lang.github.io/clock-in/

Everyone clocks in/out via a URL. All data is stored centrally in the cloud.
Admins can view all records, backfill missed clock-ins, and the system
automatically generates and emails a monthly attendance report.

## Architecture (all free tiers)

| Part | Service | Cost |
|---|---|---|
| Website (for everyone) | GitHub Pages | Free |
| Cloud database | Supabase (free tier) | Free |
| Monthly auto report | GitHub Actions scheduled job | Free |
| Email | Gmail SMTP | Free |

```
Staff phone/PC → GitHub Pages site → Supabase cloud database
Start of month → GitHub Actions → generate report → Gmail to designated inbox
```

## Features

- ✅ Clock In / Clock Out (type staff ID, name appears automatically)
- ✅ Admin page: view all records, add/edit employees, **backfill missed clock-ins**, export Excel
- ✅ Night-shift support (e.g. 8 PM in → 5 AM out counts as the same day)
- ✅ On the 1st of each month at 08:30 (MYT), auto-generates the attendance dashboard
  (days present + daily in/out details in Excel) and emails it
- ✅ Admin can email the dashboard for any month to any address from the admin page
- ✅ Location tracking: every clock-in/out records the employee's GPS coordinates;
  the admin page flags check-ins made outside the 5 km radius around the company
  location, showing staff details, time, distance and coordinates (click a
  coordinate to open Google Maps), with Excel export; the admin can correct an
  out-of-range record's GPS location (e.g. GPS drift); Check All Records also
  shows a Location column per record

---

## Deployment (about 20 minutes, follow along)

### Step 1: Create a Supabase database (free)

1. Go to https://supabase.com, sign up and log in, click **New project**, give it any name,
   set a database password, and create it.
2. Wait about 1 minute, then go to **Project Settings → API** and save:
   - `Project URL` (this is SUPABASE_URL)
   - `anon public` key (this is SUPABASE_ANON_KEY)
   - `service_role` key (this is SUPABASE_SERVICE_KEY — ⚠️ GitHub only, never in frontend code)
3. Go to **SQL Editor → New query**, paste the entire contents of `supabase/schema.sql`, click **Run**.
4. New query — set your **admin PIN** (replace `123456` with your own):
   ```sql
   insert into settings(key, value) values ('admin_pin', '123456')
     on conflict (key) do update set value = excluded.value;
   ```
   Click **Run**.

### Step 2: Push the code to GitHub

1. Create a new repository on https://github.com (e.g. `clock-in`), choose **Public**
   (GitHub Pages on the free plan requires a public repo).
2. Upload all project files to the repo (web upload or `git push`), make sure the branch is `main`.

### Step 3: Fill in Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret**,
add each one (names must match exactly):

| Secret name | Content |
|---|---|
| `SUPABASE_URL` | Project URL from Step 1 |
| `SUPABASE_ANON_KEY` | anon key from Step 1 |
| `SUPABASE_SERVICE_KEY` | service_role key from Step 1 |
| `SMTP_USER` | Sender Gmail address (your email) |
| `SMTP_PASS` | Gmail app password (see Step 4) |
| `REPORT_TO` | Report recipient (To) |
| `REPORT_CC` | Report CC recipients, comma-separated (optional) |
| `APP_TZ` | Timezone, `Asia/Kuala_Lumpur` (optional, this is the default) |
| `SMTP_HOST` | Optional, defaults to `smtp.gmail.com` |

### Step 4: Get a Gmail app password

1. Go to https://myaccount.google.com/security and turn on **2-Step Verification**.
2. Search "App passwords", create one, name it anything (e.g. `attendance`).
3. Put the generated 16-character password into `SMTP_PASS` above.

### Step 5: Enable GitHub Pages

1. Go to **Settings → Pages**, set **Build and deployment** Source to **GitHub Actions**.
2. Push any small change (or manually run Deploy website in Actions),
   wait about 1 minute. The site will be at: `https://<username>.github.io/<repo>/`

### Step 6: Test the monthly report (without waiting for month-end)

1. Go to **Actions → Monthly Attendance Dashboard → Run workflow**,
   enter last month in the month box, e.g. `2026-09`, and run it.
2. A few minutes later the `REPORT_TO` inbox receives the report email (with Excel attachment).

---

## How to use

### For employees — clock in / out

1. Open the site URL on your phone or computer.
2. Type your **Staff ID** — your name appears automatically underneath.
3. Tap **Clock In** when you arrive, **Clock Out** when you leave.
   The page shows your current status (e.g. "🟢 Clocked in at 09:02").
4. When the browser asks for location, tap **Allow** so the record includes your
   GPS coordinates. If you deny it, the record is flagged as out-of-range on
   the admin page.
5. No account or password needed.

### For admins

1. Open the site, click the small **admin** link at the bottom of the page,
   and enter your admin PIN.
2. **➕ Add Employee** — enter staff ID, name and labor type (DL/IDL),
   then give the staff ID to the employee.
3. **✏️ Edit Employee** — update a name or staff ID, or deactivate someone
   who has left.
4. **🕐 Backfill Record** — employee forgot to clock in? Select the employee,
   the type (in/out) and the time to add the record manually.
5. **📋 Check All Records** — search by name/staff ID or filter by date;
   every record shows its GPS location (click the coordinates to open
   Google Maps). Pick a date range and **⬇ Export** to download the list
   as Excel.
6. **📊 Monthly dashboard** (inside Check All Records) — pick a month and
   **⬇ Export Dashboard (Excel)** for the attendance summary (days present and
   daily in/out details), or type any email address and **✉ Send** to email it.
7. **📍 Out-of-Range Check-ins** — lists every check-in made outside the 5 km
   radius around the company location. Records with no GPS (e.g. location
   permission denied) appear here as "no location"; backfilled records are
   not listed.
   - Click a coordinate to open it in Google Maps.
   - **⬇ Export Out-of-Range (Excel)** downloads the whole list.
   - **✏️ Edit** on a row corrects its GPS location (e.g. GPS drift):
     **📍 Use company location** fills in the company coordinates in one tap;
     after saving, a record inside the radius disappears from the list.
8. On the **1st of each month at 08:30 (MYT)** the monthly report is generated
   and emailed automatically — no action needed.

### One-time setup (admin)

- **Company location** is set once and treated as fixed — the admin page shows
  it but has no button to change it. Set it in the Supabase SQL Editor:
  ```sql
  select admin_set_location('YOUR_ADMIN_PIN', 1.6183056, 103.52175, 'Company');
  ```
  Check-ins are flagged when they fall outside the 5 km radius around it.
- **Admin PIN** is set in Step 1 of Deployment above; change it any time with:
  ```sql
  update settings set value = 'new-pin' where key = 'admin_pin';
  ```

## Security notes

- The site URL is public — anyone with the link can open it, but clock-ins go through
  server-side checks and every admin action requires the admin PIN, verified server-side.
- The `service_role` key lives only in GitHub Secrets for the report script,
  never in frontend code.

## FAQ

- **Scheduled job didn't run?** GitHub Actions schedules only work on the default branch
  (`main`); on the free plan they can be a few minutes late — that's normal.
- **Supabase project paused?** Free projects pause after 7 days of inactivity;
  click Resume in Supabase. Daily clock-ins normally keep it awake.
- **Preview locally?** `cp docs/config.example.js docs/config.js`, fill it in,
  then open `docs/index.html` in a browser (clock-in only).
- **Upgrading from an older version?** Paste the full `supabase/schema.sql` into the
  SQL Editor and run it again — the file is idempotent, so re-running it is safe —
  then redeploy the site.

## File structure

```
clock-in-cloud/
├── docs/
│   ├── index.html          Clock-in page
│   ├── admin.html          Admin page
│   └── config.example.js   Frontend config sample (CI generates the real one)
├── supabase/
│   ├── schema.sql              DB schema (final version; idempotent — re-run it for upgrades)
│   └── functions/
│       └── send-dashboard/     Edge function: email dashboard on demand
├── scripts/
│   └── monthly_report.py   Monthly report generation + email script
├── .github/workflows/
│   ├── deploy.yml          Website auto-deploy
│   └── monthly-report.yml  Monthly scheduled report
└── README.md               This file
```
