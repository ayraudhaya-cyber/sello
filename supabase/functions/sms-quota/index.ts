import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const TEXTLK_BALANCE_URL = "https://app.text.lk/api/v3/balance";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST" && req.method !== "GET") {
    return json({ status: "unavailable" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json({ status: "unavailable" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  if (!supabaseUrl || !supabaseAnon || !serviceKey) {
    return json({ status: "unavailable" });
  }

  const userClient = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: session, error: sessionError } = await userClient.rpc(
    "sms_quota_session",
  );
  const row = asObject(session);
  const companyId = str(row.company_id);
  const role = str(row.role_code).toLowerCase();
  if (sessionError || !companyId || role === "sales_representative") {
    return json({ status: "hidden" });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: credentials, error: credentialsError } = await admin
    .from("company_sms_credentials")
    .select("textlk_api_token")
    .eq("company_id", companyId)
    .maybeSingle();

  const token = str(credentials?.textlk_api_token);
  if (credentialsError || !token) {
    return json({ status: "unconfigured" });
  }

  let body: unknown = null;
  try {
    const response = await fetch(TEXTLK_BALANCE_URL, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      },
    });
    body = await response.json().catch(() => null);
    if (!response.ok) {
      return json({ status: "unavailable" });
    }
  } catch {
    return json({ status: "unavailable" });
  }

  const payload = asObject(body);
  if (str(payload.status).toLowerCase() !== "success") {
    return json({ status: "unavailable" });
  }
  const data = asObject(payload.data);
  const remaining = asUnits(data.remaining_balance);
  if (remaining == null) {
    return json({ status: "unavailable" });
  }

  const { data: baselineRaw, error: baselineError } = await admin.rpc(
    "record_sms_balance_high_water",
    { p_company_id: companyId, p_remaining: remaining },
  );
  const baseline = asUnits(baselineRaw);
  if (baselineError || baseline == null) {
    return json({ status: "unavailable" });
  }

  const used = Math.max(0, baseline - remaining);
  const remainingPercent = baseline === 0
    ? 0
    : Math.round((remaining / baseline) * 1000) / 10;

  return json({
    status: "ok",
    remaining,
    baseline,
    used,
    remaining_percent: remainingPercent,
    expires_on: str(data.expired_on) || null,
  });
});

function json(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function str(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asObject(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function asUnits(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.round(value));
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value.trim());
    if (Number.isFinite(parsed)) return Math.max(0, Math.round(parsed));
  }
  return null;
}
