-- SchoolDesk: Admin Student Recycle Bin + secure permanent deletion
-- Run this in Supabase SQL Editor before using the new Admin menu.

alter table public.students
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz;

create index if not exists students_is_deleted_idx
  on public.students (is_deleted);

-- Students can read their own row only while it is not in the Recycle Bin.
-- Admin can still read all rows, including deleted rows.
drop policy if exists "SchoolDesk student reads own linked row" on public.students;
create policy "SchoolDesk student reads own linked row"
on public.students for select to authenticated
using (
  (auth_user_id = auth.uid() and is_deleted = false)
  or auth.uid() = '03c894b6-90d7-480d-a3c0-7111b0c40c11'::uuid
);

-- The existing "SchoolDesk admin updates student approval" policy grants
-- the configured Admin permission to soft-delete and restore rows.
-- Do not create a browser-side Auth user deletion policy.

-- Student Login ID authentication is handled by the schooldesk-student-login
-- Edge Function, which checks is_deleted before authenticating. No public email
-- lookup RPC is created here.

-- Keep the global serial monotonic. Deleted rows remain in the table until
-- permanent deletion, so an old Login ID is not accidentally reused.
