-- SchoolDesk complete Student Signup + Login ID + Admission Approval + Password Setup
-- Designed for the current public.students columns:
-- id, admission_no, student_name, student_name_hi, father_name, father_name_hi,
-- mother_name, mother_name_hi, class_name, date_of_birth, gender, aadhaar_number,
-- village, address, phone, admission_date, status, created_at, auth_user_id,
-- admission_application, admission_status, is_deleted, deleted_at, deleted_by,
-- student_login_id, email.
-- Run this complete script once in Supabase SQL Editor. It is safe to re-run.

-- 1) Ensure the required columns exist (existing data is not deleted).
alter table public.students
  add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null,
  add column if not exists is_deleted boolean not null default false,
  add column if not exists student_login_id text,
  add column if not exists email text,
  add column if not exists admission_status text not null default 'not_submitted',
  add column if not exists admission_application jsonb;

alter table public.students alter column admission_status set default 'not_submitted';
create unique index if not exists students_student_login_id_unique_idx
  on public.students(student_login_id) where student_login_id is not null;

-- Keep legacy IDs that were previously stored in admission_no.
update public.students
set student_login_id = admission_no
where student_login_id is null
  and admission_no ~ '^[A-Z0-9]{2}281166-?[0-9]+$';

-- Old rows that have no submitted Admission Form must start at not_submitted.
update public.students
set admission_status = 'not_submitted'
where admission_application is null
  and lower(coalesce(admission_status, '')) = 'pending';

-- 2) One global counter. It never goes backwards when a student is deleted.
create sequence if not exists public.student_login_sequence
  start with 1 increment by 1 minvalue 1 no cycle;

do $$
declare
  max_serial bigint;
  seq_last bigint;
  seq_called boolean;
  next_value bigint;
begin
  select coalesce(max(substring(student_login_id from '^[A-Z0-9]{2}281166-?([0-9]+)$')::bigint), 0)
    into max_serial
  from public.students
  where student_login_id ~ '^[A-Z0-9]{2}281166-?[0-9]+$';

  select last_value, is_called into seq_last, seq_called
  from public.student_login_sequence;

  next_value := greatest(max_serial + 1, seq_last + case when seq_called then 1 else 0 end);
  perform setval('public.student_login_sequence'::regclass, next_value, false);
end $$;

-- 3) Auto-generate IDs for any existing student rows that do not have one yet.
-- Existing IDs are never overwritten; admission_no remains the school's separate admission number.
with missing as (
  select id,
         case
           when length(regexp_replace(upper(coalesce(student_name, '')), '[^A-Z0-9]', '', 'g')) >= 2
             then left(regexp_replace(upper(coalesce(student_name, '')), '[^A-Z0-9]', '', 'g'), 2)
           else 'ST'
         end as initials
  from public.students
  where student_login_id is null and coalesce(is_deleted, false) = false
  order by id
)
update public.students s
set student_login_id = m.initials || '281166' || nextval('public.student_login_sequence')::text
from missing m
where s.id = m.id;

-- 4) Keep a trigger for records created from the Admin New Admission form too.
create or replace function public.generate_student_login_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text;
  initials text;
begin
  if new.student_login_id is null or btrim(new.student_login_id) = '' then
    clean_name := regexp_replace(upper(coalesce(new.student_name, '')), '[^A-Z0-9]', '', 'g');
    initials := case when length(clean_name) >= 2 then left(clean_name, 2) else 'ST' end;
    new.student_login_id := initials || '281166' || nextval('public.student_login_sequence')::text;
  end if;
  return new;
end;
$$;

drop trigger if exists student_login_id_trigger on public.students;
create trigger student_login_id_trigger
before insert on public.students
for each row execute function public.generate_student_login_id();

-- 5) RLS: students can read/update only their linked row; configured Admin can manage all.
alter table public.students enable row level security;
drop policy if exists "Authenticated users can read students" on public.students;
drop policy if exists "SchoolDesk student signup inserts own pending row" on public.students;
create policy "SchoolDesk student signup inserts own pending row"
on public.students for insert to authenticated
with check (auth_user_id = auth.uid() and lower(coalesce(status, '')) = 'pending' and is_deleted = false);

drop policy if exists "SchoolDesk student reads own linked row" on public.students;
create policy "SchoolDesk student reads own linked row"
on public.students for select to authenticated
using ((auth_user_id = auth.uid() and is_deleted = false)
  or auth.uid() = '03c894b6-90d7-480d-a3c0-7111b0c40c11'::uuid);

drop policy if exists "SchoolDesk admin updates student approval" on public.students;
create policy "SchoolDesk admin updates student approval"
on public.students for update to authenticated
using (auth.uid() = '03c894b6-90d7-480d-a3c0-7111b0c40c11'::uuid)
with check (auth.uid() = '03c894b6-90d7-480d-a3c0-7111b0c40c11'::uuid);

drop policy if exists "SchoolDesk admin inserts student rows" on public.students;
create policy "SchoolDesk admin inserts student rows"
on public.students for insert to authenticated
with check (auth.uid() = '03c894b6-90d7-480d-a3c0-7111b0c40c11'::uuid);

drop policy if exists "SchoolDesk admin deletes student rows" on public.students;
create policy "SchoolDesk admin deletes student rows"
on public.students for delete to authenticated
using (auth.uid() = '03c894b6-90d7-480d-a3c0-7111b0c40c11'::uuid);

drop policy if exists "SchoolDesk student updates own admission form" on public.students;
create policy "SchoolDesk student updates own admission form"
on public.students for update to authenticated
using (auth_user_id = auth.uid() and is_deleted = false)
with check (auth_user_id = auth.uid() and is_deleted = false);

-- Students cannot approve themselves or change account status/admission status.
create or replace function public.schooldesk_guard_student_admission_update()
returns trigger
language plpgsql
set search_path = public, auth
as $$
begin
  if auth.uid() = '03c894b6-90d7-480d-a3c0-7111b0c40c11'::uuid then
    return new;
  end if;
  if auth.uid() is distinct from old.auth_user_id then
    raise exception 'Not allowed to edit this student record';
  end if;
  if new.status is distinct from old.status then
    raise exception 'Only SchoolDesk Admin can change account status';
  end if;
  if lower(coalesce(new.admission_status, 'not_submitted'))
       not in (lower(coalesce(old.admission_status, 'not_submitted')), 'pending') then
    raise exception 'Only SchoolDesk Admin can approve or reject an admission form';
  end if;
  if new.admission_application is null then
    raise exception 'Admission form data is required';
  end if;
  return new;
end;
$$;

drop trigger if exists schooldesk_guard_student_admission_update on public.students;
create trigger schooldesk_guard_student_admission_update
before update on public.students
for each row execute function public.schooldesk_guard_student_admission_update();

-- 6) Signup RPC. The browser creates an Auth user with a random, undisclosed
-- initial password. This function stores its email and generated Student Login ID.
-- Student immediately gets only the Admission Form. No chosen password is used.
-- Drop the exact old signature first so an old return type cannot block setup.
drop function if exists public.schooldesk_create_pending_student(text);
create function public.schooldesk_create_pending_student(student_name text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  clean_name text := btrim(coalesce(student_name, ''));
  clean_email text;
  clean_letters text;
  initials text;
  candidate text;
  existing_login_id text;
  matching_email_rows integer := 0;
  current_uid uuid := auth.uid();
begin
  if current_uid is null then
    raise exception 'Supabase session is missing. Please sign up again.';
  end if;
  if clean_name = '' then
    raise exception 'Student name is required';
  end if;

  select lower(u.email) into clean_email from auth.users u where u.id = current_uid;
  if clean_email is null or clean_email = '' then
    raise exception 'Email was not found in Supabase Authentication.';
  end if;

  select s.student_login_id
    into existing_login_id
  from public.students s
  where s.auth_user_id = current_uid
  limit 1;

  if found then
    if existing_login_id is null or btrim(existing_login_id) = '' then
      clean_letters := regexp_replace(upper(clean_name), '[^A-Z0-9]', '', 'g');
      initials := case when length(clean_letters) >= 2 then left(clean_letters, 2) else 'ST' end;
      candidate := initials || '281166' || nextval('public.student_login_sequence')::text;
      update public.students s
      set student_login_id = candidate,
          email = coalesce(nullif(s.email, ''), clean_email),
          student_name = coalesce(nullif(s.student_name, ''), clean_name)
      where s.auth_user_id = current_uid;
      return candidate;
    end if;
    update public.students s set email = coalesce(nullif(s.email, ''), clean_email)
    where s.auth_user_id = current_uid;
    return existing_login_id;
  end if;

  -- If Admin previously entered this exact email on one unlinked legacy row,
  -- attach the Auth account to that row. Never guess by student name alone.
  select count(*) into matching_email_rows
  from public.students s
  where lower(coalesce(s.email, '')) = clean_email
    and s.auth_user_id is null
    and coalesce(s.is_deleted, false) = false
    and lower(coalesce(s.status, '')) <> 'left';

  if matching_email_rows > 1 then
    raise exception 'More than one unlinked student record has this email. Ask Admin to correct duplicate emails first.';
  elsif matching_email_rows = 1 then
    select s.student_login_id into existing_login_id
    from public.students s
    where lower(coalesce(s.email, '')) = clean_email
      and s.auth_user_id is null
      and coalesce(s.is_deleted, false) = false
      and lower(coalesce(s.status, '')) <> 'left'
    limit 1;
    if existing_login_id is null or btrim(existing_login_id) = '' then
      clean_letters := regexp_replace(upper(clean_name), '[^A-Z0-9]', '', 'g');
      initials := case when length(clean_letters) >= 2 then left(clean_letters, 2) else 'ST' end;
      existing_login_id := initials || '281166' || nextval('public.student_login_sequence')::text;
    end if;
    update public.students
    set auth_user_id = current_uid,
        email = clean_email,
        student_login_id = existing_login_id,
        status = 'pending',
        admission_status = 'not_submitted'
    where lower(coalesce(email, '')) = clean_email
      and auth_user_id is null
      and coalesce(is_deleted, false) = false
      and lower(coalesce(status, '')) <> 'left';
    return existing_login_id;
  end if;

  clean_letters := regexp_replace(upper(clean_name), '[^A-Z0-9]', '', 'g');
  initials := case when length(clean_letters) >= 2 then left(clean_letters, 2) else 'ST' end;
  candidate := initials || '281166' || nextval('public.student_login_sequence')::text;

  insert into public.students
    (student_name, student_login_id, email, status, admission_status, auth_user_id, is_deleted)
  values
    (clean_name, candidate, clean_email, 'pending', 'not_submitted', current_uid, false);

  return candidate;
end;
$$;

revoke all on function public.schooldesk_create_pending_student(text) from public;
grant execute on function public.schooldesk_create_pending_student(text) to authenticated;

-- 7) Remove the old public Login-ID-to-email lookup. Student login is now
-- handled by the schooldesk-student-login Edge Function so emails are not exposed.
drop function if exists public.schooldesk_student_email_by_id(text);

-- 8) Backfill email for already-linked Auth accounts without changing their passwords.
update public.students s
set email = u.email
from auth.users u
where s.auth_user_id = u.id
  and (s.email is null or btrim(s.email) = '');

-- NOTE: Existing records with NULL email receive a Login ID but cannot be linked
-- until Admin enters the correct email in the Student Login Details panel. Signup
-- with that exact email links the Auth user. The script never matches by name alone.
