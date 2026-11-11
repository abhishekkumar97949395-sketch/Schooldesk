import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};

const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const escapeHtml = (value: string) => value.replace(/[&<>"']/g, (ch) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
}[ch] ?? ch));

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const resendKey = Deno.env.get("RESEND_API_KEY");
    const fromEmail = Deno.env.get("SCHOOLDESK_FROM_EMAIL");
    if (!url || !anonKey || !serviceRoleKey || !resendKey || !fromEmail) {
      return reply(500, {
        error: "Email service is not configured. Set RESEND_API_KEY and SCHOOLDESK_FROM_EMAIL in Supabase secrets.",
      });
    }

    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return reply(401, { error: "Admin sign-in required." });

    const authClient = createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser(token);
    if (authError || authData.user?.id !== "03c894b6-90d7-480d-a3c0-7111b0c40c11") {
      return reply(403, { error: "Only SchoolDesk Admin can send student login emails." });
    }

    const body = await req.json();
    const studentId = Number(body?.studentId);
    if (!Number.isSafeInteger(studentId) || studentId <= 0) {
      return reply(400, { error: "Invalid student record." });
    }

    const admin = createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: student, error: studentError } = await admin
      .from("students")
      .select("id,student_name,student_login_id,status,admission_status,is_deleted,auth_user_id")
      .eq("id", studentId)
      .maybeSingle();

    if (studentError || !student || student.is_deleted || !student.auth_user_id ||
        String(student.status).toLowerCase() !== "active" ||
        String(student.admission_status).toLowerCase() !== "approved" ||
        !student.student_login_id) {
      return reply(409, { error: "Student must have an active account, Login ID, and approved Admission Form." });
    }

    const { data: userData, error: userError } = await admin.auth.admin.getUserById(student.auth_user_id);
    const email = String(userData.user?.email || "").trim().toLowerCase();
    if (userError || !email) return reply(409, { error: "Student's registered Auth email is missing." });

    const redirectTo = "https://abhiparaur.netlify.app/";
    const { data: linkData, error: linkError } = await admin.auth.admin.generateLink({
      type: "recovery",
      email,
      options: { redirectTo },
    });
    const actionLink = linkData?.properties?.action_link;
    if (linkError || !actionLink) {
      return reply(502, { error: "Could not create the secure password setup link. Check Supabase Auth URL settings." });
    }

    const name = escapeHtml(String(student.student_name || "Student"));
    const loginId = escapeHtml(String(student.student_login_id));
    const safeLink = escapeHtml(actionLink);
    const html = `<!doctype html><html><body style="font-family:Arial,sans-serif;color:#123;line-height:1.6">
      <div style="max-width:600px;margin:auto;padding:24px;border:1px solid #d6e6f7;border-radius:12px">
      <h2 style="color:#07509b">SchoolDesk Student Login</h2>
      <p>नमस्ते ${name},</p>
      <p>आपका Admission Form स्कूल द्वारा Approve कर दिया गया है। आपकी Student Login ID:</p>
      <p style="font-size:24px;font-weight:bold;letter-spacing:1px;background:#eef6ff;padding:14px;border-radius:8px">${loginId}</p>
      <p>पहली बार लॉगिन करने से पहले अपना पासवर्ड सुरक्षित रूप से बनाएँ:</p>
      <p><a href="${safeLink}" style="display:inline-block;background:#075ee8;color:white;padding:12px 18px;border-radius:8px;text-decoration:none">Set Your Password</a></p>
      <p>यह लिंक सीमित समय के लिए है। इसे किसी अन्य व्यक्ति के साथ साझा न करें। Admin आपका पासवर्ड नहीं देख सकता।</p>
      <p>Student Login: <a href="https://abhiparaur.netlify.app/">abhiparaur.netlify.app</a></p>
      <p>धन्यवाद,<br>SchoolDesk</p></div></body></html>`;
    const textBody = `नमस्ते ${student.student_name || "Student"},\n\nआपका Admission Form Approve हो गया है। आपकी Student Login ID: ${student.student_login_id}\n\nअपना पासवर्ड सुरक्षित रूप से बनाने के लिए यह लिंक खोलें: ${actionLink}\n\nStudent Login: https://abhiparaur.netlify.app/\nयह लिंक सीमित समय के लिए है। Admin आपका पासवर्ड नहीं देख सकता।\n\nSchoolDesk`;

    const mailResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [email],
        subject: "SchoolDesk Student Login ID और Password Setup",
        html,
        text: textBody,
      }),
    });
    if (!mailResponse.ok) {
      const detail = await mailResponse.text();
      return reply(502, { error: "Email provider rejected the message.", detail: detail.slice(0, 500) });
    }

    return reply(200, { ok: true, email, loginId: student.student_login_id });
  } catch (_error) {
    return reply(500, { error: "Unable to send the SchoolDesk student login email." });
  }
});
