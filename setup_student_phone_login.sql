-- SchoolDesk student self-sign-up + Admin approval
-- Run this complete script in Supabase SQL Editor.
alter table public.students
  add column if not exists auth_user_id uuid unique references auth.users(id) on delete set null;

alter table public.students enable row level security;

drop policy if exists "SchoolDesk student signup inserts own pending row" on public.students;
create policy "SchoolDesk student signup inserts own pending row"
on public.students for insert to authenticated
with check (auth_user_id = auth.uid() and lower(coalesce(status,'')) = 'pending');

drop policy if exists "SchoolDesk admin updates student approval" on public.students;
create policy "SchoolDesk admin updates student approval"
on public.students for update to authenticated
using (auth.uid() = '03c894b6-90d7-480d-a3c0-7111b0c40c11'::uuid)
with check (auth.uid() = '03c894b6-90d7-480d-a3c0-7111b0c40c11'::uuid);

-- Student Login ID authentication is handled by the schooldesk-student-login
-- Edge Function. Do not expose the Auth email through a public RPC.

-- Keep the existing restricted SELECT policy:
-- a student can read only their own linked row; the SchoolDesk admin can read all rows.
