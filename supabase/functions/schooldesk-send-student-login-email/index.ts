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
    const appsScriptUrl = Deno.env.get("SCHOOLDESK_APPS_SCRIPT_URL");
    const webhookSecret = Deno.env.get("SCHOOLDESK_WEBHOOK_SECRET");

    if (!url || !anonKey || !serviceRoleKey || !appsScriptUrl || !webhookSecret) {
      return reply(500, {
        error: "Email service is not configured. Add SCHOOLDESK_APPS_SCRIPT_URL and SCHOOLDESK_WEBHOOK_SECRET to Supabase Edge Function secrets.",
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

    const response = await fetch(appsScriptUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        secret: webhookSecret,
        to: email,
        studentName: String(student.student_name || "Student"),
        loginId: String(student.student_login_id),
        setupLink: actionLink,
      }),
      redirect: "follow",
    });

    const responseText = await response.text();
    let mailResult: Record<string, unknown> = {};
    try {
      mailResult = JSON.parse(responseText);
    } catch {
      return reply(502, { error: "Google email service returned an unreadable response." });
    }

    if (!response.ok || mailResult.success !== true) {
      return reply(502, {
        error: "Google email service could not send the message.",
        detail: typeof mailResult.error === "string" ? mailResult.error : "Unknown email service error.",
      });
    }

    return reply(200, { ok: true, email, loginId: student.student_login_id });
  } catch (_error) {
    return reply(500, { error: "Unable to send the SchoolDesk student login email." });
  }
});
