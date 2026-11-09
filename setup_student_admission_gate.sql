-- SchoolDesk: Student Login -> Admission Form only -> Admin approval -> Full portal
-- Run this AFTER setup_student_self_signup_approval.sql in Supabase SQL Editor.

alter table public.students
  add column if not exists admission_status text not null default 'not_submitted',
  add column if not exists admission_application jsonb;

-- Keep the student's own admission form editable while preventing students from
-- approving themselves or changing the account's active/rejected status.
 drop policy if exists "SchoolDesk student updates own admission form" on public.students;
create policy "SchoolDesk student updates own admission form"
on public.students for update to authenticated
using (auth_user_id = auth.uid())
with check (auth_user_id = auth.uid());

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

-- Admin can read all rows through the existing Admin SELECT policy and can approve
-- by setting admission_status='approved', status='active'. Students can read only
-- their own linked row through the existing self-read policy.
