-- ============================================================
-- Attendance system - Supabase schema
-- Usage: Supabase Dashboard -> SQL Editor -> New query -> paste this file -> Run
-- ============================================================

-- employees table
create table if not exists employees (
  id         bigint generated always as identity primary key,
  staff_id   text,
  name       text not null,
  pin        text,
  labor_type text,          -- IDL / DL
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists uq_employees_staff_id on employees(staff_id);
create unique index if not exists uq_employees_name on employees(name);

-- attendance records table
create table if not exists records (
  id          bigint generated always as identity primary key,
  employee_id bigint not null references employees(id) on delete cascade,
  action      text not null check (action in ('in','out')),
  ts          timestamptz not null default now(),
  ip          text,
  note        text not null default ''
);
create index if not exists idx_records_emp on records(employee_id, id desc);
create index if not exists idx_records_ts on records(ts desc);

-- clock-in/out GPS coordinates (nullable: older records have no location)
alter table records add column if not exists lat double precision;
alter table records add column if not exists lng double precision;

-- settings table (admin PIN etc.)
create table if not exists settings (
  key   text primary key,
  value text not null
);

alter table employees enable row level security;
alter table records enable row level security;
alter table settings enable row level security;

-- employee directory: publicly readable (PIN not included)
drop policy if exists "employees list readable" on employees;
create policy "employees list readable" on employees
  for select using (active = true);

-- clock in/out by employee id (no PIN; only checks the employee exists and is active)
-- optionally records GPS coordinates sent by the clock-in page
drop function if exists clock(bigint, text, text);
drop function if exists clock(bigint, text);
create or replace function clock(
  p_emp_id bigint, p_action text,
  p_lat double precision default null, p_lng double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_last  text;
  v_ts    timestamptz;
  v_label text;
  v_past  text;
begin
  if p_action not in ('in', 'out') then
    return jsonb_build_object('ok', false, 'msg', 'Invalid action');
  end if;

  if not exists (
    select 1 from employees where id = p_emp_id and active
  ) then
    return jsonb_build_object('ok', false, 'msg', 'Employee not found or inactive');
  end if;

  select r.action into v_last
  from records r
  where r.employee_id = p_emp_id
  order by r.id desc limit 1;

  v_label := case when p_action = 'in' then 'Clocked in' else 'Clocked out' end;
  v_past := case when p_action = 'in' then 'clocked in' else 'clocked out' end;

  if v_last = p_action then
    return jsonb_build_object('ok', false, 'msg', 'You have already ' || v_past);
  end if;

  v_ts := now();
  insert into records(employee_id, action, ts, lat, lng)
  values (p_emp_id, p_action, v_ts, p_lat, p_lng);
  return jsonb_build_object('ok', true, 'msg', v_label || ' successfully', 'ts', v_ts);
end;
$$;

-- look up name by staff ID (case-insensitive; PIN never exposed)
create or replace function lookup_employee(p_staff_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rec record;
begin
  select id, name into v_rec
  from employees
  where upper(staff_id) = upper(nullif(btrim(p_staff_id), ''))
    and active;

  if not found then
    return jsonb_build_object('ok', false, 'msg', 'Staff ID not found. Please check and try again.');
  end if;

  return jsonb_build_object('ok', true, 'id', v_rec.id, 'name', v_rec.name);
end;
$$;

-- clock history of a single employee
create or replace function my_records(p_emp_id bigint)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(jsonb_build_object('action', action, 'ts', ts) order by id desc),
    '[]'::jsonb
  )
  from records where employee_id = p_emp_id;
$$;

-- admin: view all records (admin PIN verified server-side)
create or replace function admin_records(p_admin_pin text, p_limit int default 500)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pin text;
begin
  select value into v_pin from settings where key = 'admin_pin';
  if v_pin is null or p_admin_pin is distinct from v_pin then
    return jsonb_build_object('ok', false, 'msg', 'Incorrect admin PIN');
  end if;

  return jsonb_build_object('ok', true, 'records', (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', r.id, 'staff_id', e.staff_id, 'name', e.name,
        'labor_type', e.labor_type,
        'action', r.action, 'ts', r.ts,
        'lat', r.lat, 'lng', r.lng
      ) order by r.id desc), '[]'::jsonb)
    from (select * from records order by id desc limit p_limit) r
    join employees e on e.id = r.employee_id
  ));
end;
$$;

-- admin: add employee (admin PIN verified server-side)
drop function if exists admin_add_employee(text, text, text, text);
create or replace function admin_add_employee(
  p_admin_pin text, p_staff_id text, p_name text, p_emp_pin text,
  p_labor_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pin   text;
  v_labor text;
begin
  select value into v_pin from settings where key = 'admin_pin';
  if v_pin is null or p_admin_pin is distinct from v_pin then
    return jsonb_build_object('ok', false, 'msg', 'Incorrect admin PIN');
  end if;

  if p_staff_id is null or btrim(p_staff_id) = '' then
    return jsonb_build_object('ok', false, 'msg', 'Staff ID is required');
  end if;

  if p_name is null or btrim(p_name) = '' then
    return jsonb_build_object('ok', false, 'msg', 'Name is required');
  end if;

  v_labor := nullif(upper(btrim(coalesce(p_labor_type, ''))), '');
  if v_labor is not null and v_labor not in ('IDL', 'DL') then
    return jsonb_build_object('ok', false, 'msg', 'Labor type must be IDL or DL');
  end if;

  begin
    insert into employees(staff_id, name, pin, labor_type)
    values (
      btrim(p_staff_id), btrim(p_name), nullif(btrim(p_emp_pin), ''),
      v_labor
    );
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg', 'This staff ID or name already exists');
  end;

  return jsonb_build_object(
    'ok', true,
    'msg', 'Employee added: ' || btrim(p_staff_id) || ' ' || btrim(p_name)
  );
end;
$$;

-- admin: backfill a record (admin PIN verified server-side)
create or replace function admin_add_record(
  p_admin_pin text, p_emp_id bigint, p_action text, p_ts text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pin text;
  v_ts  timestamptz;
begin
  select value into v_pin from settings where key = 'admin_pin';
  if v_pin is null or p_admin_pin is distinct from v_pin then
    return jsonb_build_object('ok', false, 'msg', 'Incorrect admin PIN');
  end if;

  if p_action not in ('in', 'out') then
    return jsonb_build_object('ok', false, 'msg', 'Invalid action');
  end if;

  if not exists (select 1 from employees where id = p_emp_id and active) then
    return jsonb_build_object('ok', false, 'msg', 'Employee not found');
  end if;

  begin
    v_ts := p_ts::timestamptz;
  exception when others then
    return jsonb_build_object('ok', false, 'msg', 'Invalid time format');
  end;

  insert into records(employee_id, action, ts, note)
  values (p_emp_id, p_action, v_ts, 'backfilled by admin');
  return jsonb_build_object('ok', true, 'msg', 'Backfill record added');
end;
$$;

-- admin: list all employees including inactive (admin PIN verified server-side)
create or replace function admin_list_employees(p_admin_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pin text;
begin
  select value into v_pin from settings where key = 'admin_pin';
  if v_pin is null or p_admin_pin is distinct from v_pin then
    return jsonb_build_object('ok', false, 'msg', 'Incorrect admin PIN');
  end if;

  return jsonb_build_object('ok', true, 'employees', (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', id, 'staff_id', staff_id, 'name', name,
        'labor_type', labor_type, 'active', active
      ) order by name), '[]'::jsonb)
    from employees
  ));
end;
$$;

-- admin: edit employee details (admin PIN verified server-side)
create or replace function admin_edit_employee(
  p_admin_pin text, p_emp_id bigint, p_staff_id text, p_name text,
  p_labor_type text, p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pin   text;
  v_labor text;
begin
  select value into v_pin from settings where key = 'admin_pin';
  if v_pin is null or p_admin_pin is distinct from v_pin then
    return jsonb_build_object('ok', false, 'msg', 'Incorrect admin PIN');
  end if;

  if not exists (select 1 from employees where id = p_emp_id) then
    return jsonb_build_object('ok', false, 'msg', 'Employee not found');
  end if;

  if p_staff_id is null or btrim(p_staff_id) = '' then
    return jsonb_build_object('ok', false, 'msg', 'Staff ID is required');
  end if;

  if p_name is null or btrim(p_name) = '' then
    return jsonb_build_object('ok', false, 'msg', 'Name is required');
  end if;

  v_labor := nullif(upper(btrim(coalesce(p_labor_type, ''))), '');
  if v_labor is not null and v_labor not in ('IDL', 'DL') then
    return jsonb_build_object('ok', false, 'msg', 'Labor type must be IDL or DL');
  end if;

  begin
    update employees
    set staff_id   = btrim(p_staff_id),
        name       = btrim(p_name),
        labor_type = v_labor,
        active     = coalesce(p_active, true)
    where id = p_emp_id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'msg', 'This staff ID or name already exists');
  end;

  return jsonb_build_object('ok', true, 'msg', 'Employee updated');
end;
$$;

-- admin: get company location used for the out-of-range check (admin PIN verified server-side)
create or replace function admin_get_location(p_admin_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pin   text;
  v_lat   text;
  v_lng   text;
  v_label text;
begin
  select value into v_pin from settings where key = 'admin_pin';
  if v_pin is null or p_admin_pin is distinct from v_pin then
    return jsonb_build_object('ok', false, 'msg', 'Incorrect admin PIN');
  end if;

  select value into v_lat from settings where key = 'company_lat';
  select value into v_lng from settings where key = 'company_lng';
  select value into v_label from settings where key = 'company_label';

  return jsonb_build_object(
    'ok', true,
    'lat', case when v_lat is null or v_lat = '' then null else v_lat::double precision end,
    'lng', case when v_lng is null or v_lng = '' then null else v_lng::double precision end,
    'label', coalesce(v_label, ''),
    'radius_km', 5
  );
end;
$$;

-- admin: set company location used for the out-of-range check (admin PIN verified server-side)
create or replace function admin_set_location(
  p_admin_pin text, p_lat double precision, p_lng double precision, p_label text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pin text;
begin
  select value into v_pin from settings where key = 'admin_pin';
  if v_pin is null or p_admin_pin is distinct from v_pin then
    return jsonb_build_object('ok', false, 'msg', 'Incorrect admin PIN');
  end if;

  if p_lat is null or p_lng is null
     or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    return jsonb_build_object('ok', false, 'msg', 'Invalid coordinates');
  end if;

  insert into settings(key, value) values
    ('company_lat', p_lat::text),
    ('company_lng', p_lng::text),
    ('company_label', coalesce(btrim(p_label), ''))
  on conflict (key) do update set value = excluded.value;

  return jsonb_build_object(
    'ok', true, 'msg', 'Company location updated',
    'lat', p_lat, 'lng', p_lng, 'label', coalesce(btrim(p_label), '')
  );
end;
$$;

-- admin: clock records outside the 5 km radius around the company location
-- records without GPS location (e.g. permission denied) are treated as out of range;
-- backfilled records are excluded
-- (admin PIN verified server-side; distance computed with the haversine formula)
create or replace function admin_out_of_range(p_admin_pin text, p_limit int default 500)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pin text;
  v_lat double precision;
  v_lng double precision;
begin
  select value into v_pin from settings where key = 'admin_pin';
  if v_pin is null or p_admin_pin is distinct from v_pin then
    return jsonb_build_object('ok', false, 'msg', 'Incorrect admin PIN');
  end if;

  select nullif(value, '')::double precision into v_lat from settings where key = 'company_lat';
  select nullif(value, '')::double precision into v_lng from settings where key = 'company_lng';
  if v_lat is null or v_lng is null then
    return jsonb_build_object('ok', false, 'msg', 'Company location not set');
  end if;

  return jsonb_build_object('ok', true, 'radius_km', 5, 'records', (
    select coalesce(jsonb_agg(t order by t.id desc), '[]'::jsonb)
    from (
      select r.id, e.staff_id, e.name, e.labor_type, r.action, r.ts,
             r.lat, r.lng,
             case
               when r.lat is null or r.lng is null then null
               else round((6371 * acos(least(1, greatest(-1,
                 sin(radians(v_lat)) * sin(radians(r.lat)) +
                 cos(radians(v_lat)) * cos(radians(r.lat)) * cos(radians(r.lng - v_lng))
               ))))::numeric, 2)
             end as distance_km
      from records r
      join employees e on e.id = r.employee_id
      where r.note is distinct from 'backfilled by admin'
    ) t
    where t.distance_km is null or t.distance_km > 5
    limit p_limit
  ));
end;
$$;

-- admin: correct the GPS location of a single clock record (admin PIN verified server-side)
create or replace function admin_update_record_location(
  p_admin_pin text, p_record_id bigint, p_lat double precision, p_lng double precision
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pin text;
begin
  select value into v_pin from settings where key = 'admin_pin';
  if v_pin is null or p_admin_pin is distinct from v_pin then
    return jsonb_build_object('ok', false, 'msg', 'Incorrect admin PIN');
  end if;

  if not exists (select 1 from records where id = p_record_id) then
    return jsonb_build_object('ok', false, 'msg', 'Record not found');
  end if;

  if p_lat is null or p_lng is null
     or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    return jsonb_build_object('ok', false, 'msg', 'Invalid coordinates');
  end if;

  update records set lat = p_lat, lng = p_lng where id = p_record_id;
  return jsonb_build_object('ok', true, 'msg', 'Record location updated');
end;
$$;

-- allow anonymous calls (each function verifies permissions internally)
grant execute on function clock(bigint, text, double precision, double precision) to anon, authenticated;
grant execute on function my_records(bigint) to anon, authenticated;
grant execute on function lookup_employee(text) to anon, authenticated;
grant execute on function admin_records(text, int) to anon, authenticated;
grant execute on function admin_add_employee(text, text, text, text, text) to anon, authenticated;
grant execute on function admin_add_record(text, bigint, text, text) to anon, authenticated;
grant execute on function admin_list_employees(text) to anon, authenticated;
grant execute on function admin_edit_employee(text, bigint, text, text, text, boolean) to anon, authenticated;
grant execute on function admin_get_location(text) to anon, authenticated;
grant execute on function admin_set_location(text, double precision, double precision, text) to anon, authenticated;
grant execute on function admin_out_of_range(text, int) to anon, authenticated;
grant execute on function admin_update_record_location(text, bigint, double precision, double precision) to anon, authenticated;

-- ============================================================
-- Last step: set your admin PIN (replace 123456 with your own),
-- run the line below separately in the SQL Editor:
--
-- insert into settings(key, value) values ('admin_pin', '123456')
--   on conflict (key) do update set value = excluded.value;
-- ============================================================
