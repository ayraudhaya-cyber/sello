import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const TEXTLK_URL = "https://app.text.lk/api/v3/sms/send";
const TEST_MESSAGE =
  "This is a test SMS from Sello. Your SMS configuration is working.";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ status: "failed", reason: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json({ status: "failed", reason: "unauthorized" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ status: "failed", reason: "invalid_json" }, 400);
  }

  const purpose = str(body.purpose).toLowerCase();
  const isTest = purpose === "test";
  const isVerify = purpose === "verify_sender";
  const recipient = str(body.recipient).replace(/^\+/, "");
  const eventId = str(body.event_id);
  const recipientKind = str(body.recipient_kind);
  const recipientKey = str(body.recipient_key);
  const message = isTest || isVerify ? TEST_MESSAGE : str(body.message);
  // body.sender_id is ignored for order/collection SMS and Settings Test SMS.
  // For purpose=verify_sender it is a candidate only — never persisted until
  // Text.lk accepts and activate_verified_sms_sender_id runs as service role.

  if (!recipient || !message) {
    return json({ status: "skipped", reason: "invalid_request" }, 200);
  }
  if (!isTest && !isVerify && (!eventId || !recipientKind || !recipientKey)) {
    return json({ status: "skipped", reason: "invalid_request" }, 200);
  }

  if (!/^[1-9][0-9]{8,14}$/.test(recipient)) {
    return json({ status: "skipped", reason: "invalid_recipient" }, 200);
  }

  const token = Deno.env.get("TEXTLK_API_TOKEN")?.trim() ?? "";
  if (!token) {
    return json({ status: "failed", reason: "sms_not_configured" }, 200);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  const supabase = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: authHeader } },
  });

  if (isVerify && !serviceKey) {
    return json({ status: "failed", reason: "activation_unavailable" }, 200);
  }

  const { data: claim, error: claimError } = isVerify
    ? await supabase.rpc("claim_verify_sms_sender_dispatch", {
      p_address: recipient,
      p_sender_id: str(body.sender_id),
      p_payload: { message, purpose: "verify_sender" },
    })
    : isTest
    ? await supabase.rpc("claim_test_outbound_sms_dispatch", {
      p_address: recipient,
      p_payload: { message, purpose: "test" },
    })
    : await supabase.rpc("claim_outbound_sms_dispatch", {
      p_event_id: eventId,
      p_recipient_kind: recipientKind,
      p_recipient_key: recipientKey,
      p_address: recipient,
      p_payload: { message },
    });

  if (claimError) {
    return json({ status: "failed", reason: "claim_failed" }, 200);
  }

  const claimed = asObject(claim);
  if (claimed.ok !== true) {
    const reason = str(claimed.reason) || "skipped";
    if (reason === "already_sent") {
      return json({ status: "already_sent" }, 200);
    }
    if (
      reason === "missing_sender_id" ||
      reason === "sms_disabled" ||
      reason === "forbidden" ||
      reason === "invalid_sender_id" ||
      reason === "sender_id_locked"
    ) {
      return json({ status: "skipped", reason }, 200);
    }
    return json({ status: "skipped", reason }, 200);
  }

  const dispatchId = str(claimed.dispatch_id);
  const senderId = str(claimed.sender_id);
  if (!dispatchId || !senderId) {
    return json({ status: "failed", reason: "claim_incomplete" }, 200);
  }

  let textlkStatus = 0;
  let textlkBody: unknown = null;
  try {
    const response = await fetch(TEXTLK_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        recipient,
        sender_id: senderId,
        type: "plain",
        message,
      }),
    });
    textlkStatus = response.status;
    textlkBody = await response.json().catch(() => null);
  } catch (error) {
    await supabase.rpc("finalize_outbound_sms_dispatch", {
      p_dispatch_id: dispatchId,
      p_status: "failed",
      p_payload: { error: String(error) },
    });
    return json({ status: "failed", reason: "network" }, 200);
  }

  const ok = isTextlkSuccess(textlkBody, textlkStatus);

  await supabase.rpc("finalize_outbound_sms_dispatch", {
    p_dispatch_id: dispatchId,
    p_status: ok ? "sent" : "failed",
    p_payload: {
      http_status: textlkStatus,
      provider: "text.lk",
      sender_id: senderId,
    },
  });

  if (!ok) {
    return json(
      {
        status: "failed",
        reason: isVerify ? "sender_id_rejected" : "provider_error",
      },
      200,
    );
  }

  let activated = false;
  if (isVerify) {
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: activation, error: activationError } = await admin.rpc(
      "activate_verified_sms_sender_id",
      { p_dispatch_id: dispatchId },
    );
    const row = asObject(activation);
    activated = !activationError && row.ok === true;
    if (!activated) {
      return json(
        {
          status: "failed",
          reason: str(row.reason) || "activation_failed",
          activated: false,
        },
        200,
      );
    }
  }

  return json(
    {
      status: "sent",
      activated: isVerify ? true : undefined,
    },
    200,
  );
});

function json(payload: Record<string, unknown>, status: number) {
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

function isTextlkSuccess(body: unknown, httpStatus: number): boolean {
  if (httpStatus < 200 || httpStatus >= 300) return false;
  const row = asObject(body);
  const raw = row.status;
  if (raw === true) return true;
  if (raw === false) return false;
  const status = str(raw).toLowerCase();
  if (status === "success" || status === "ok" || status === "true") {
    return true;
  }
  return false;
}
