SchoolDesk — Existing Project Update (8 November 2026)

WHAT WAS UPDATED
- This ZIP is based on the latest saved SchoolDesk project found in the Library:
  SchoolDesk_Login_ID_Automatic_Sequence_Fixed.zip.
- Preserves the existing SchoolDesk layout, Admin sidebar, student portal modules,
  admission gate, admit-card tools, recycle bin, and delete Edge Function.
- Student Sign Up now asks only for Student Name and Email. It does not ask the
  student to create or enter a password.
- Supabase Auth receives a cryptographically random initial password that is not
  shown or stored in the page. The student is taken directly to the Admission Form
  during the initial signed-in session.
- Student Login ID is stored in public.students.student_login_id using the format
  first two English letters + 281166 + one global increasing number, for example
  AB2811661, AK2811662. Existing IDs are retained.
- Existing student rows without a Login ID receive one when the SQL setup is run.
- Email is stored in public.students.email and tied to the Auth account.
- After Admin approves the Admission Form, Supabase sends a secure password setup /
  recovery link to that Auth email. The student opens the link and chooses a new
  password. Admin cannot read the password.
- Student Login uses Student Login ID + the password the student created from the
  email link. Pending/rejected students do not get the full portal.
- Admission Form email is locked to the Auth email so the password setup link is
  sent to the correct account.
- Admin Student Login Details now shows Student Name, Email, Student Login ID,
  account status, a secure/masked password status, and the reset-link action.

FILES
- index.html — updated website entry point at the deploy root (fixes Netlify root 404).
- setup_student_self_signup_approval.sql — complete, idempotent Supabase setup.
- setup_student_login_id_sequence.sql — same complete setup for convenience;
  run only one of these two SQL files, not both.
- setup_student_phone_login.sql — legacy optional phone-login SQL; not required
  for the email + Student Login ID flow.
- setup_student_admission_gate.sql — older separate admission-gate migration;
  the complete setup above already includes the gate and guard trigger.
- setup_student_recycle_bin.sql — recycle-bin policies/migration from the prior ZIP.
- setup_supabase_insert_policy.sql — legacy helper; do not run unless specifically
  instructed after checking current policies.
- supabase/functions/schooldesk-delete-student/index.ts — existing delete function.
- supabase/functions/schooldesk-student-login/index.ts — private Login ID/password
  authentication; it does not expose the student email through a public RPC.
- supabase/config.toml — disables JWT verification only for the login function;
  the function itself verifies the Student ID, approval status, and password.

SUPABASE SETUP (REQUIRED BEFORE TESTING)
1. Take a Supabase database backup first.
2. In Supabase Authentication > Providers > Email, turn OFF Confirm email for this
   specific direct-signup flow. The student needs an authenticated session to open
   the Admission Form immediately after sign-up. With Confirm email ON, Supabase
   does not return the required session for this flow.
3. Open Supabase SQL Editor and run the complete file:
   setup_student_self_signup_approval.sql
   It creates the sequence, ID trigger, RPC functions, RLS policies, and admission
   guard. It does not delete student rows or the Admin Auth user.
4. Verify the configured SchoolDesk Admin UID in index.html and SQL is still the
   actual Admin Auth UID in your Supabase project. Current value in this saved ZIP:
   03c894b6-90d7-480d-a3c0-7111b0c40c11
   Admin email in this saved ZIP: aksingh97979494@gmail.com
5. Deploy the included Edge Function `schooldesk-student-login` from the project
   root with Supabase CLI (`supabase functions deploy schooldesk-student-login`).
   Set the server-side secret `SUPABASE_SERVICE_ROLE_KEY` with
   `supabase secrets set SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY`.
   Supabase supplies SUPABASE_URL and SUPABASE_ANON_KEY to Edge Functions. Never
   put the service-role key in index.html or share it in chat.
6. Under Authentication > URL Configuration, add the eventual Netlify site URL to
   Site URL and Redirect URLs before testing password recovery emails.
7. For local testing, use VS Code Live Server or another localhost web server;
   opening the file as file:// can block Auth redirects/CORS. Add that localhost URL
   to Supabase Redirect URLs. Later add the Netlify URL too.
8. Test using a new test email address. Signup should show the Admission Form
   immediately and assign a Login ID. Submit the form, then approve it from Admin.
   Confirm the password setup email arrives. Open it, choose a password, and sign
   in with the generated Student Login ID and that password.

IMPORTANT SECURITY / LIMITATIONS
- Never put the Supabase service_role key in index.html. The saved website uses a
  public publishable/anon key only. The delete and student-login Edge Functions use the service-role
  secret server-side and must remain deployed with secrets configured.
- The student-login Edge Function must be deployed; without it, Login ID/password
  sign-in will not work. It checks that both account status and Admission Form are
  approved before creating an Auth session.
- Turning OFF Confirm email means the signup email is not verified at account
  creation. Admin should verify the email with the family before approving the
  Admission Form. The password setup link is delivered to the Auth email after
  approval.
- If a student closes the page before submitting the Admission Form, the browser's
  Supabase session can resume the unfinished form on refresh on the same browser.
  Clearing browser data or changing device before submitting may require Admin
  assistance because no password is created until approval.
- Existing student rows receive Login IDs. For a legacy row with Email = NULL,
  Admin can use Student Login Details > “Email जोड़ें” to save the correct email.
  When that student signs up with the exact same email, the SQL function links the
  Auth account to that existing row. It never guesses identity by name alone.
  School Left rows are not auto-reactivated.
- Several older academic modules still use browser localStorage and are not fully
  synchronized across devices. This ZIP fixes the Supabase signup/authentication,
  Login ID, and Admission Approval/password setup flow; it does not claim every
  legacy module is cloud-backed.
- Live Supabase RLS, email delivery, and Netlify-hosted testing must be completed
  in the school's own project before production use.
- The configured Admin UID/email are carried forward from the saved project. If
  your current Admin Auth UID differs, the app's Admin authorization will fail;
  update both index.html and SQL consistently before use.

PASSWORD RULE
- No student-entered password is accepted at sign-up.
- A random initial password is generated only for Supabase Auth account creation;
  it is never displayed to the student or Admin and is not saved in localStorage.
- Only after Admission Approval does the student receive the secure email link and
  choose their own password. Admin cannot view or retrieve plaintext passwords.

IMPORTANT — Admission Form save fix (8 Nov 2026)
1. In Supabase SQL Editor, run setup_student_admission_submit_rpc.sql once.
2. Replace the old website folder with this ZIP's SchoolDesk folder.
3. Open the new index.html and test Student Admission Form submission.
4. The form now reports an error if Supabase does not confirm that the row was saved.


ADMISSION SUBMIT DEBUG FIX (2026-11-09): Replaced the silent form submit handler with explicit Supabase/session checks and visible error reporting. If submission fails, the message will now show the actual Supabase error instead of appearing to do nothing. This does not prove live Supabase delivery; run the included SQL setup if the RPC is not installed.


PASSWORD SETUP EMAIL DELIVERY (IMPORTANT)
- The website now requests a Supabase Auth password-recovery email immediately after Admin clicks “Approve Admission”. The Student Login Details page also has “Reset Link भेजें” for approved students.
- This request is NOT proof that the email reached the inbox. Supabase's default email service is restricted for production use and may only deliver to project team addresses. To send to parents'/students' Gmail addresses, configure a custom SMTP provider in Supabase Dashboard > Project Settings > Authentication/SMTP (menu wording may vary). Use a verified sender/domain and provider credentials. Never put SMTP credentials in HTML or send them in chat.
- In Supabase Authentication > URL Configuration, set Site URL to the final HTTPS Netlify URL and add that exact URL (and localhost Live Server URL while testing) to Redirect URLs. Opening the site as Android content:// is not a valid password-recovery return URL. Test from VS Code Live Server/localhost after allowlisting it, then test again on Netlify HTTPS.
- When Admin approves Admission, the page reports that Supabase accepted the email request; actual delivery depends on SMTP. Check Inbox, Spam, Supabase Auth Logs, and SMTP provider logs.
- The email link opens Supabase's recovery flow. The page listens for PASSWORD_RECOVERY and lets the student choose a new password. Admin never sees or sets the password.
- Existing legacy student rows with no auth_user_id cannot receive a password setup email merely by adding an email address. They must first be securely linked to an Auth account through the approved signup/linking process.


NETLIFY ROOT 404 FIX (9 November 2026)
- This ZIP places index.html in the top-level folder, not inside a SchoolDesk subfolder.
- Extract the ZIP first. In Netlify, deploy the extracted folder whose first-level contents include index.html, scripts.js, netlify.toml, and supabase/. Do not upload only the inner supabase/ folder or only the SchoolDesk/ folder.
- netlify.toml sets publish = "." and _redirects provides the single-page fallback.
- This package has been checked for JavaScript syntax and archive layout. It has NOT been connected to your Netlify/Supabase accounts or live-tested against your database. Do not run SQL migrations again without checking current schema/state.


LATEST UPDATE — INDIA ADDRESS SELECTION (09-Nov-2026)
Student Admission Form now has cascading selectors for State/UT, District, Sub-district/Tehsil and optional Development Block using the public India LGD Index API (community mirror of Ministry of Panchayati Raj LGD data; attribution: Government Open Data License India). Students enter a six-digit PIN code and choose a matching Post Office/locality from the India Post lookup list. House number/street/locality remains a small optional field; the full address is assembled automatically and saved in admission_application.
The LGD mirror currently provides state, district, sub-district and block hierarchy; it does not provide a village-level endpoint. The PIN-code lookup therefore lists post offices/localities, which may not be a complete census/LGD village roster. Internet access is required for the live lists. The form blocks submission unless the required location selections, valid 10-digit mobile number and 12-digit Aadhaar format are present. This validates number format only; it does not verify Aadhaar with UIDAI or verify phone ownership by OTP.




STUDENT LOGIN ID EMAIL DELIVERY UPDATE (11-Nov-2026)
- After Admin approves an Admission Form, the website now invokes the secure
  Edge Function: schooldesk-send-student-login-email.
- The function verifies the signed-in Admin UID, checks that the student record is
  active and admission-approved, reads the Login ID and registered Auth email,
  creates a one-time Supabase password-recovery link, and emails both the Login ID
  and password setup link using Resend. It does not reveal or email any password.
- Deploy from the project root:
  supabase functions deploy schooldesk-send-student-login-email
- Configure these Edge Function secrets in Supabase (Project Settings > Edge
  Functions > Secrets, or with Supabase CLI):
  RESEND_API_KEY = the private API key from your Resend account
  SCHOOLDESK_FROM_EMAIL = a sender address on a domain verified with Resend
  SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are also required;
  Supabase normally provides the first two, and the service-role key must be set
  securely as a function secret. Never put any secret in index.html or GitHub.
- Add https://abhiparaur.netlify.app/ to Supabase Authentication > URL Configuration
  Redirect URLs. The Edge Function uses this HTTPS URL for the recovery link.
- Email delivery is not active until the function is deployed and Resend secrets
  plus a verified sender are configured. A GitHub commit alone cannot configure
  the school's Supabase project, create a Resend account, or verify a sending domain.
- Test only with a school-controlled test account first. Confirm the Login ID and
  password setup link arrive, the link returns to the Netlify site, and the student
  can set a password. Do not use real student data for the first test.
