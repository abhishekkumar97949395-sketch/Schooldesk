-- Review the Admin UID before running. This policy permits only that authenticated Admin
-- to INSERT into public.students. It does not grant SELECT/UPDATE/DELETE.
-- Change the UUID below if your configured SchoolDesk Admin UID is different.

DROP POLICY IF EXISTS "SchoolDesk admin can insert students" ON public.students;
CREATE POLICY "SchoolDesk admin can insert students"
ON public.students
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = '03c894b6-90d7-480d-a3c0-7111b0c40c11'::uuid);
