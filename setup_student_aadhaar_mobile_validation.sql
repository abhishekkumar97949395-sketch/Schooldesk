-- SchoolDesk: Aadhaar + student mobile are mandatory before Admission reaches Admin.
-- Run once in Supabase SQL Editor. Does not delete or reset any existing data/accounts.

CREATE OR REPLACE FUNCTION public.schooldesk_submit_admission_form(p_application jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  current_uid uuid := auth.uid();
  saved_id bigint;
  aadhaar_value text;
  mobile_value text;
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

  aadhaar_value := regexp_replace(COALESCE(p_application->>'aadhaar', ''), '\D', '', 'g');
  mobile_value := regexp_replace(COALESCE(p_application->>'studentPhone', ''), '\D', '', 'g');
  IF aadhaar_value !~ '^[0-9]{12}$' THEN
    RAISE EXCEPTION 'Invalid Aadhaar: सही 12 अंकों का आधार नंबर आवश्यक है।';
  END IF;
  IF mobile_value !~ '^[6-9][0-9]{9}$' THEN
    RAISE EXCEPTION 'Invalid Mobile: विद्यार्थी का 6 से 9 से शुरू होने वाला सही 10 अंकों का मोबाइल नंबर आवश्यक है।';
  END IF;

  UPDATE public.students
     SET admission_application = p_application || jsonb_build_object(
           'aadhaar', aadhaar_value,
           'studentPhone', mobile_value,
           'submittedAt', COALESCE(p_application->>'submittedAt', now()::text),
           'status', 'Pending Admin Approval'
         ),
         aadhaar_number = aadhaar_value,
         phone = mobile_value,
         admission_status = 'pending'
   WHERE auth_user_id = current_uid
     AND COALESCE(is_deleted, false) = false
     AND LOWER(COALESCE(status, '')) NOT IN ('rejected', 'left')
   RETURNING id INTO saved_id;

  IF saved_id IS NULL THEN
    RAISE EXCEPTION 'आपका Student Record नहीं मिला या आवेदन जमा करने की अनुमति नहीं है।';
  END IF;

  RETURN jsonb_build_object('success', true, 'student_id', saved_id, 'admission_status', 'pending');
END;
$$;

REVOKE ALL ON FUNCTION public.schooldesk_submit_admission_form(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schooldesk_submit_admission_form(jsonb) TO authenticated;
