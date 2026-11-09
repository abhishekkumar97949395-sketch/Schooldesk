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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceRoleKey) {
      return reply(500, { error: "Student login service is not configured." });
    }

    const body = await req.json();
    const loginId = String(body?.student_login_id ?? "").trim().toUpperCase();
    const password = String(body?.password ?? "");
    if (!/^[A-Z0-9]{2}281166-?[0-9]+$/.test(loginId) || password.length < 6 || password.length > 256) {
      return reply(401, { error: "Invalid login." });
    }

    const admin = createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const authClient = createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: student, error: studentError } = await admin
      .from("students")
      .select("auth_user_id,status,admission_status,is_deleted")
      .eq("student_login_id", loginId)
      .maybeSingle();

    if (studentError || !student || student.is_deleted || !student.auth_user_id ||
        String(student.status).toLowerCase() !== "active" ||
        String(student.admission_status).toLowerCase() !== "approved") {
      return reply(401, { error: "Invalid login." });
    }

    const { data: userResult, error: userError } = await admin.auth.admin.getUserById(student.auth_user_id);
    const email = userResult?.user?.email;
    if (userError || !email) return reply(401, { error: "Invalid login." });

    const { data: signedIn, error: signInError } = await authClient.auth.signInWithPassword({
      email,
      password,
    });
    if (signInError || !signedIn.session) return reply(401, { error: "Invalid login." });

    // Return the Auth session only after ID, account status, admission approval,
    // and password have all been verified. The student's email is not returned
    // separately by this function.
    return reply(200, { session: signedIn.session });
  } catch (_error) {
    return reply(400, { error: "Unable to complete Student Login." });
  }
});
