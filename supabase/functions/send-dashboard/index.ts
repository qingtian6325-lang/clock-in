// Supabase Edge Function: send-dashboard
// Receives a dashboard XLSX (base64) from the admin page, verifies the admin
// PIN, and emails it via SMTP (Gmail). Secrets required:
//   SB_URL, SB_SERVICE_KEY, SMTP_HOST, SMTP_USER, SMTP_PASS
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, msg: "POST only" }, 405);

  try {
    const { pin, to, month, filename, file_base64 } = await req.json();

    if (!pin || !to || !month || !filename || !file_base64) {
      return json({ ok: false, msg: "Missing fields" }, 400);
    }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(to)) {
      return json({ ok: false, msg: "Invalid email address" }, 400);
    }
    if (file_base64.length > 15 * 1024 * 1024) {
      return json({ ok: false, msg: "File too large" }, 400);
    }

    // verify admin PIN (service role bypasses RLS)
    const sb = createClient(
      Deno.env.get("SB_URL")!,
      Deno.env.get("SB_SERVICE_KEY")!,
    );
    const { data, error } = await sb.from("settings").select("value").eq("key", "admin_pin").single();
    if (error || !data || data.value !== pin) {
      return json({ ok: false, msg: "Incorrect PIN" }, 403);
    }

    const smtpUser = Deno.env.get("SMTP_USER")!;
    const client = new SMTPClient({
      connection: {
        hostname: Deno.env.get("SMTP_HOST") || "smtp.gmail.com",
        port: 465,
        tls: true,
        auth: { username: smtpUser, password: Deno.env.get("SMTP_PASS")! },
      },
    });

    await client.send({
      from: smtpUser,
      to,
      subject: `Attendance Dashboard - ${month}`,
      content: `Please find attached the attendance dashboard for ${month}.`,
      html: `<p>Please find attached the attendance dashboard for ${month}.</p>`,
      attachments: [
        {
          filename,
          contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          encoding: "base64",
          content: file_base64,
        },
      ],
    });
    await client.close();

    return json({ ok: true });
  } catch (e) {
    console.error(e);
    return json({ ok: false, msg: String((e as Error)?.message || e) }, 500);
  }
});
