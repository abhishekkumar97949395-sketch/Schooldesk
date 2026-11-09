-- SchoolDesk: secure Student Admission Form submission RPC.
-- Run this once in Supabase SQL Editor.
-- It updates only the currently authenticated student's own row.
-- It does not change Admin accounts, existing student data, or RLS policies.

DROP FUNCTION IF EXISTS public.schooldesk_submit_admission_form(jsonb);

CREATE FUNCTION public.schooldesk_submit_admission_form(p_application jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  current_uid uuid := auth.uid();
  saved_id bigint;
BEGIN
  IF current_uid IS NULL THEN
    RAISE EXCEPTION 'Student session नहीं मिली। कृपया Student Login दोबारा करें।';
  END IF;

  IF p_application IS NULL OR jsonb_typeof(p_application) <> 'object' THEN
    RAISE EXCEPTION 'Admission Form का डेटा सही नहीं है।';
  END IF;

  IF COALESCE(NULLIF(BTRIM(p_application->>'fullName'), ''), '') = '' THEN
    RAISE EXCEPTION 'Student Name आवश्यक है।';
  END IF;

  IF COALESCE(NULLIF(BTRIM(p_application->>'studentClass'), ''), '') = '' THEN
    RAISE EXCEPTION 'Class / Section आवश्यक है।';
  END IF;

  IF COALESCE(NULLIF(BTRIM(p_application->>'fatherName'), ''), '') = '' THEN
    RAISE EXCEPTION 'Father Name आवश्यक है।';
  END IF;

  UPDATE public.students
     SET admission_application = p_application || jsonb_build_object(
           'submittedAt', COALESCE(p_application->>'submittedAt', now()::text),
           'status', 'Pending Admin Approval'
         ),
         admission_status = 'pending'
   WHERE auth_user_id = current_uid
     AND COALESCE(is_deleted, false) = false
     AND LOWER(COALESCE(status, '')) NOT IN ('rejected', 'left')
   RETURNING id INTO saved_id;

  IF saved_id IS NULL THEN
    RAISE EXCEPTION 'आपका Student Record नहीं मिला या आवेदन जमा करने की अनुमति नहीं है।';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'student_id', saved_id,
    'admission_status', 'pending'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.schooldesk_submit_admission_form(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schooldesk_submit_admission_form(jsonb) TO authenticated;
