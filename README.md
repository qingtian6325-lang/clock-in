# 📋 Company Attendance System (Cloud) / 考勤系统（云端版）

🌐 **Live demo / 在线演示:** https://qingtian6325-lang.github.io/clock-in/

[English](#english) | [中文](#中文)

Everyone clocks in/out via a URL. All data is stored centrally in the cloud.
Admins can view all records, backfill missed clock-ins, and the system
automatically generates and emails a monthly attendance report.

---

<a id="english"></a>
## English

### Architecture (all free tiers)

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

### Features

- ✅ Clock In / Clock Out (type staff ID, name appears automatically)
- ✅ 🟢 **On-site now** panel — shows who is currently clocked in (names only,
  auto-refreshes every minute), so everyone can see who is around
- ✅ Admin page: view all records, add/edit employees, **backfill missed clock-ins**, export Excel
- ✅ Night-shift support (e.g. 8 PM in → 5 AM out counts as the same day)
- ✅ On the 1st of each month at 08:30 (MYT), auto-generates the attendance dashboard
  (days present + daily in/out times, working hours & OT hours in Excel) and emails it
- ✅ Admin can email the dashboard for any month to any address from the admin page
- ⏸️ Location tracking (**currently disabled**): when enabled, every clock-in/out
  records the employee's GPS coordinates; the admin page flags check-ins made
  outside the 5 km radius around the company location, showing staff details,
  time, distance and coordinates (click a coordinate to open Google Maps),
  with Excel export; the admin can correct an out-of-range record's GPS location

---

### Attendance & Working Hours Rules

#### 1. Clock In/Out Interlock & 15-second Debounce Protection
- **Alternating Interlock**: Staff must Clock In before Clocking Out. Double-clocking the same action is prevented.
- **15-second Debounce Protection**: Once clocked in, clocking out is disabled for 15 seconds to prevent accidental double-clicks or lag-induced early exits.

#### 2. 14-Hour Auto Clock-Out & Employee Alert
- **Auto Clock-out**: If an employee forgets to clock out, the system automatically inserts a clock-out record after 14 hours.
- **Recorded Time**: Clock-out time is recorded as `Clock-In Time + 14 hours`.
- **Note**: Tagged with `auto clock-out (14h limit)`.
- **Next-day Alert**: When entering their Staff ID next day, a prominent yellow warning banner (`⚠️ Attendance Alert`) appears, reminding them to contact an admin to update their exact leaving time. Clock In is allowed and not blocked.
- **Alert Dismissal**: Once an admin edits the record, the warning banner disappears.

#### 3. Working Hours & OT Calculation (with OT Freeze Protection)
- **Rest Time Deduction**: Shifts lasting 5 hours or more have 1 hour deducted for meals/rest; shifts under 5 hours have no deduction.
- **Working Hours (WH)**: Up to 8.0 hours of net time.
- **Overtime (OT)**: Beyond 8 hours, rounded down in 30-minute (0.5h) units.
- **OT Freeze Protection**: For unverified 14h auto clock-outs, **OT is frozen to 0.0 hours** to prevent accidental excess overtime payout. Actual OT is only calculated after an admin verifies and edits the record.

#### 4. Night Shift Pairing & Midnight Cutoff
- **Attribution Day**: Clocking in before 23:59 belongs to the current calendar day.
- **Overnight Pairing**: A clock-out occurring within 16 hours of an open clock-in from the previous day is paired with that night shift, even if auto clock-out triggers the next afternoon (e.g. 12:30 PM). Missing punches (NA) are completely eliminated.

---

### Deployment (about 20 minutes, follow along)

#### Step 1: Create a Supabase database (free)

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

#### Step 2: Push the code to GitHub

1. Create a new repository on https://github.com (e.g. `clock-in`), choose **Public**
   (GitHub Pages on the free plan requires a public repo).
2. Upload all project files to the repo (web upload or `git push`), make sure the branch is `main`.

#### Step 3: Fill in Secrets

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

#### Step 4: Get a Gmail app password

1. Go to https://myaccount.google.com/security and turn on **2-Step Verification**.
2. Search "App passwords", create one, name it anything (e.g. `attendance`).
3. Put the generated 16-character password into `SMTP_PASS` above.

#### Step 5: Enable GitHub Pages

1. Go to **Settings → Pages**, set **Build and deployment** Source to **GitHub Actions**.
2. Push any small change (or manually run Deploy website in Actions),
   wait about 1 minute. The site will be at: `https://<username>.github.io/<repo>/`

#### Step 6: Test the monthly report (without waiting for month-end)

1. Go to **Actions → Monthly Attendance Dashboard → Run workflow**,
   enter last month in the month box, e.g. `2026-09`, and run it.
2. A few minutes later the `REPORT_TO` inbox receives the report email (with Excel attachment).

---

### How to use

#### For employees — clock in / out

1. Open the site URL on your phone or computer.
2. Type your **Staff ID** — your name appears automatically underneath.
3. Tap **Clock In** when you arrive, **Clock Out** when you leave.
   The page shows your current status (e.g. "🟢 Clocked in at 09:02").
4. The **🟢 On-site now** panel below shows who is currently clocked in —
   useful for seeing who is around and who to look for.
5. No account or password needed.

#### For admins

1. Open the site, click the small **admin** link at the bottom of the page,
   and enter your admin PIN.
2. **➕ Add Employee** — enter staff ID, name and labor type (DL/IDL),
   then give the staff ID to the employee. An employee must be added first,
   otherwise they cannot clock in.
3. **✏️ Edit Employee** — update a name, staff ID or labor type, or deactivate
   someone who has left.
4. **🕐 Backfill Record** — employee forgot to clock in? Select the employee,
   the type (in/out), the date and the time to add the record manually.
5. **📋 Check All Records** — search by name/staff ID or filter by date.
   Pick a date range and **⬇ Export** to download the raw records as Excel.
6. **📊 Monthly dashboard** (inside Check All Records) — pick a month and
   **⬇ Export Dashboard (Excel)** for the attendance summary (days present,
   daily in/out times, working hours & OT hours), or type any email address
   and **✉ Send** to email it.
7. **📍 Out-of-Range Check-ins** (currently disabled) — when location tracking
   is enabled, lists every check-in made outside the 5 km radius around the
   company location, with Excel export and per-record GPS correction
   (**📍 Use company location** fills in the company coordinates in one tap).
8. On the **1st of each month at 08:30 (MYT)** the monthly report is generated
   and emailed automatically — no action needed.

#### One-time setup (admin)

- **Company location** is set once and treated as fixed — the admin page shows
  it but has no button to change it. Set it in the Supabase SQL Editor:
  ```sql
  select admin_set_location('YOUR_ADMIN_PIN', 1.6183056, 103.52175, 'Company');
  ```
  (Only used when location tracking is enabled.)
- **Admin PIN** is set in Step 1 of Deployment above; change it any time with:
  ```sql
  update settings set value = 'new-pin' where key = 'admin_pin';
  ```

### Security notes

- The site URL is public — anyone with the link can open it, but clock-ins go through
  server-side checks and every admin action requires the admin PIN, verified server-side.
- The `service_role` key lives only in GitHub Secrets for the report script,
  never in frontend code.

### FAQ

- **Scheduled job didn't run?** GitHub Actions schedules only work on the default branch
  (`main`); on the free plan they can be a few minutes late — that's normal.
- **Supabase project paused?** Free projects pause after 7 days of inactivity;
  click Resume in Supabase. Daily clock-ins normally keep it awake.
- **Preview locally?** `cp docs/config.example.js docs/config.js`, fill it in,
  then open `docs/index.html` in a browser (clock-in only).
- **Upgrading from an older version?** Paste the full `supabase/schema.sql` into the
  SQL Editor and run it again — the file is idempotent, so re-running it is safe —
  then redeploy the site.

### File structure

```
clock-in-cloud/
├── docs/
│   ├── index.html          Clock-in page (includes On-site now panel)
│   ├── admin.html          Admin page
│   └── config.example.js   Frontend config sample (CI generates the real one)
├── supabase/
│   ├── schema.sql              DB schema (final version; idempotent — re-run it for upgrades;
│                               includes active_now() for the On-site now panel)
│   └── functions/
│       └── send-dashboard/     Edge function: email dashboard on demand
├── scripts/
│   └── monthly_report.py   Monthly report generation + email script
├── .github/workflows/
│   ├── deploy.yml          Website auto-deploy
│   └── monthly-report.yml  Monthly scheduled report
└── README.md               This file
```

---

<a id="中文"></a>
## 中文

### 架构（全部免费）

| 部分 | 服务 | 费用 |
|---|---|---|
| 网站（所有人用） | GitHub Pages | 免费 |
| 云数据库 | Supabase（免费版） | 免费 |
| 每月自动报表 | GitHub Actions 定时任务 | 免费 |
| 邮件 | Gmail SMTP | 免费 |

```
员工手机/电脑 → GitHub Pages 网站 → Supabase 云数据库
每月 1 号 → GitHub Actions → 生成报表 → Gmail 发到指定邮箱
```

### 功能

- ✅ 打卡 / 下班打卡（输入工号，名字自动显示）
- ✅ 🟢 **On-site now 在岗看板** —— 显示当前谁已打卡在岗（只显示名字，每分钟自动刷新），方便知道谁在、找谁
- ✅ 管理页：查看全部记录、加 / 改员工、**补打卡**、导出 Excel
- ✅ 支持夜班（比如晚上 8 点上班 → 凌晨 5 点下班，算同一天）
- ✅ 每月 1 号早上 08:30（马来西亚时间）自动生成考勤报表（出勤天数 + 每天上下班时间、工作小时和 OT 小时 Excel）并发邮件
- ✅ 管理员可以在管理页把任意月份的报表用邮件发到任意邮箱
- ⏸️ 位置追踪（**目前已停用**）：开启时，每次打卡记录员工 GPS 坐标；管理页标出公司位置 5km 半径外的打卡，显示员工资料、时间、距离和坐标（点坐标进 Google Maps），可导出 Excel；管理员可修正超范围记录的 GPS 位置

---

### 部署（约 20 分钟，跟着做）

#### 第 1 步：建 Supabase 数据库（免费）

1. 打开 https://supabase.com 注册登录，点 **New project**，随便起个名字，设数据库密码，创建。
2. 等约 1 分钟，进 **Project Settings → API**，记下：
   - `Project URL`（这就是 SUPABASE_URL）
   - `anon public` key（这就是 SUPABASE_ANON_KEY）
   - `service_role` key（这就是 SUPABASE_SERVICE_KEY —— ⚠️ 只放 GitHub，绝不进前端代码）
3. 进 **SQL Editor → New query**，把 `supabase/schema.sql` 的全部内容粘贴进去，点 **Run**。
4. 新开一个 query，设置**管理员 PIN**（把 `123456` 换成你自己的）：
   ```sql
   insert into settings(key, value) values ('admin_pin', '123456')
     on conflict (key) do update set value = excluded.value;
   ```
   点 **Run**。

#### 第 2 步：推代码到 GitHub

1. 在 https://github.com 建新仓库（比如 `clock-in`），选 **Public**
   （免费版 GitHub Pages 要求公开仓库）。
2. 把项目文件传上去（网页上传或 `git push`），确认分支是 `main`。

#### 第 3 步：填 Secrets

进 **Settings → Secrets and variables → Actions → New repository secret**，
逐个添加（名字必须一字不差）：

| Secret 名 | 内容 |
|---|---|
| `SUPABASE_URL` | 第 1 步的 Project URL |
| `SUPABASE_ANON_KEY` | 第 1 步的 anon key |
| `SUPABASE_SERVICE_KEY` | 第 1 步的 service_role key |
| `SMTP_USER` | 发件 Gmail 地址（你的邮箱） |
| `SMTP_PASS` | Gmail 应用密码（看第 4 步） |
| `REPORT_TO` | 报表收件人（To） |
| `REPORT_CC` | 报表抄送，逗号分隔（可选） |
| `APP_TZ` | 时区，`Asia/Kuala_Lumpur`（可选，默认就是它） |
| `SMTP_HOST` | 可选，默认 `smtp.gmail.com` |

#### 第 4 步：拿 Gmail 应用密码

1. 打开 https://myaccount.google.com/security，开 **2-Step Verification**（两步验证）。
2. 搜 "App passwords"，建一个，名字随便（比如 `attendance`）。
3. 把生成的 16 位密码填进上面的 `SMTP_PASS`。

#### 第 5 步：开 GitHub Pages

1. 进 **Settings → Pages**，**Build and deployment** 的 Source 选 **GitHub Actions**。
2. 推个小改动（或去 Actions 手动跑 Deploy website），等约 1 分钟。
   网址是：`https://<用户名>.github.io/<仓库名>/`

#### 第 6 步：测试月报（不用等到月底）

1. 进 **Actions → Monthly Attendance Dashboard → Run workflow**，
   月份框填上个月，比如 `2026-09`，运行。
2. 几分钟后 `REPORT_TO` 邮箱会收到报表邮件（含 Excel 附件）。

---

### 使用方法

#### 员工打卡

1. 在手机或电脑上打开网址。
2. 输入 **Staff ID**（工号），名字会自动显示在下面。
3. 上班按 **Clock In**，下班按 **Clock Out**。
   页面会显示你当前状态（比如 "🟢 Clocked in at 09:02"）。
4. 下面的 **🟢 On-site now** 显示现在谁已打卡在岗，方便知道谁在、找谁。
5. 不需要账号密码。

#### 管理员

1. 打开网站，点页面底部小小的 **admin** 链接，输入管理员 PIN。
2. **➕ Add Employee** —— 填工号、名字、labor type（DL/IDL），
   然后把工号告诉员工。**一定要先加员工**，不然他没法打卡。
3. **✏️ Edit Employee** —— 改名字、工号、labor type，或停用离职员工。
4. **🕐 Backfill Record** —— 员工忘记打卡？选员工、选 in/out、设日期时间，手动补一条。
5. **📋 Check All Records** —— 按名字/工号搜，按日期筛。
   选起止日期按 **⬇ Export**，下载原始记录 Excel。
6. **📊 Monthly dashboard**（在 Check All Records 里面）—— 选月份，
   按 **⬇ Export Dashboard (Excel)** 下载考勤汇总（出勤天数、每天上下班时间、工作小时和 OT 小时），
   或输入任意邮箱按 **✉ Send** 发邮件。
7. **📍 Out-of-Range Check-ins**（目前已停用）—— 开启位置追踪后，
   列出公司位置 5km 半径外的打卡，可导出 Excel，可逐条修正 GPS 位置
   （**📍 Use company location** 一键填入公司坐标）。
8. **每月 1 号早上 08:30（马来西亚时间）**自动生成并发月报邮件，不用管。

#### 一次性设置（管理员）

- **公司位置**只设一次，视为固定 —— 管理页只显示，没有改的按钮。
  在 Supabase SQL Editor 里设：
  ```sql
  select admin_set_location('YOUR_ADMIN_PIN', 1.6183056, 103.52175, 'Company');
  ```
  （只在开启位置追踪时用。）
- **管理员 PIN** 在部署第 1 步设；随时改：
  ```sql
  update settings set value = 'new-pin' where key = 'admin_pin';
  ```

### 安全说明

- 网址是公开的 —— 有链接就能打开，但打卡有服务端校验，所有管理操作都要管理员 PIN（服务端验证）。
- `service_role` key 只放在 GitHub Secrets 给报表脚本用，绝不进前端代码。

### 常见问题

- **定时任务没跑？** GitHub Actions 定时只在默认分支（`main`）生效；免费版晚几分钟正常。
- **Supabase 项目 paused？** 免费项目 7 天没动静会暂停，去 Supabase 点 Resume。每天有人打卡一般不会停。
- **本地预览？** `cp docs/config.example.js docs/config.js`，填好后浏览器打开 `docs/index.html`（只能试打卡）。
- **从旧版升级？** 把完整 `supabase/schema.sql` 粘进 SQL Editor 再跑一遍 —— 文件是幂等的，重跑安全 —— 然后重新部署网站。

### 文件结构

```
clock-in-cloud/
├── docs/
│   ├── index.html          打卡页（含 On-site now 在岗看板）
│   ├── admin.html          管理页
│   └── config.example.js   前端配置示例（CI 会生成真正的）
├── supabase/
│   ├── schema.sql              数据库结构（最终版；幂等，升级重跑即可；
│                               含 active_now() 给在岗看板用）
│   └── functions/
│       └── send-dashboard/     Edge function：按需邮件发送报表
├── scripts/
│   └── monthly_report.py   月报生成 + 发邮件脚本
├── .github/workflows/
│   ├── deploy.yml          网站自动部署
│   └── monthly-report.yml  每月定时报表
└── README.md               本文件
```

---

### 考勤打卡与工时业务规则（Attendance Rules & Calculation Policy）

#### 1. 打卡交替互锁与防连击保护 (Interlock & Debounce Protection)
- **交替互锁**：员工必须先 Clock In 才能 Clock Out。处于已上班状态无法再次点 In，处于已下班状态无法再次点 Out。
- **15 秒防连击保护**：员工打上班卡后，15 秒内不允许点击下班打卡，避免因网络卡顿或手抖连击导致秒退。

#### 2. 14 小时超时自动下班机制 (14h Auto Clock-out)
- **触发条件**：员工打上班卡后忘记下班，当跨度超过 14 小时，系统自动插入下班卡。
- **记录时间**：严格记录为 `上班时间 + 14小时`。
- **备注标记**：自动写入备注 `auto clock-out (14h limit)`。
- **次日打卡提醒**：员工第二天输入工号时，前端弹出醒目英文警告横幅（`Attendance Alert`），提醒联系管理员核实离开时间；员工点击 Clock In 正常放行，绝不卡死。
- **警告解除**：管理员在后台核实并点击 Edit 修改实际时间后，员工打卡界面的警告横幅自动消失。

#### 3. 工时与加班计算（含 Auto 14h OT 冻结保护）
- **休息扣除**：班次总跨度（Span）满 5 小时扣除 1 小时用餐休息；不满 5 小时不扣除休息时间。
- **正常出勤工时（WH）**：净工时前 8 小时为正常工时（上限 8.0 小时）。
- **加班工时（OT）**：超出 8 小时的部分，以 30 分钟（0.5 小时）为最小单位向下取整（不足 30 分钟不计加班）。
- **OT 冻结保护**：凡属于未核实的 14 小时自动下班记录，**加班工时强制冻结为 0.0 小时**（防错算多发加班费）；待管理员在后台核实修改后方可释放真实加班工时。

#### 4. 夜班跨午夜与稳固归并规则 (Night Shift Pairing)
- **归属日判定**：员工在当天 23:59 之前打卡上班，均归入当天考勤。
- **跨日成对归并**：下班卡与前一天未结清的上班卡若间隔在 16 小时以内，无论次日何时打卡（包括次日 12:30 触发的自动下班），均稳固归属于前一天的夜班，绝不割裂成两天碎卡，彻底消除 Missing Punch (NA)。
