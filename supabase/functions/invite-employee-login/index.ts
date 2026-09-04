import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

/**
 * invite-employee-login
 *
 * Creates / links a Sales Rep (or other Hub team) Auth user using the service
 * role, then sends a password-recovery email so they can set credentials.
 *
 * Must never run Auth Admin from the Owner's browser client — that path used
 * a second GoTrue client whose signOut() BroadcastChannel clears the Owner
 * session on web.
 *
 * Authorization: caller's JWT → prepare_employee_login_invite (company + role).
 * Privileged work: SUPABASE_SERVICE_ROLE_KEY (never exposed to Flutter).
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ ok: false, reason: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json({ ok: false, reason: "unauthorized" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, reason: "invalid_json" }, 400);
  }

  const employeeId = str(body.employee_id);
  if (!employeeId) {
    return json({ ok: false, reason: "invalid_request" }, 400);
  }

  const redirectTo = sanitizeRedirect(str(body.redirect_to));

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";

  if (!supabaseUrl || !supabaseAnon || !serviceKey) {
    return json({ ok: false, reason: "server_misconfigured" }, 500);
  }

  const userClient = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: claim, error: claimError } = await userClient.rpc(
    "prepare_employee_login_invite",
    { p_employee_id: employeeId },
  );

  if (claimError) {
    return json({ ok: false, reason: "claim_failed" }, 200);
  }

  const prep = asObject(claim);
  if (prep.ok !== true) {
    const reason = str(prep.reason) || "forbidden";
    const status = reason === "unauthorized"
      ? 401
      : reason === "forbidden"
      ? 403
      : 200;
    return json({ ok: false, reason }, status);
  }

  const companyId = str(prep.company_id);
  const actorEmployeeId = str(prep.actor_employee_id);
  const email = str(prep.email).toLowerCase();
  const fullName = str(prep.full_name);
  let authUserId = str(prep.auth_user_id);

  if (!companyId || !actorEmployeeId || !email) {
    return json({ ok: false, reason: "claim_incomplete" }, 200);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const emailMeta = await buildInviteEmailMetadata(admin, {
      employeeId,
      companyId,
      email,
      fullName,
    });

    if (!authUserId) {
      const ensured = await ensureAuthUser(admin, email, emailMeta);
      authUserId = ensured.userId;

      const { data: linkRaw, error: linkError } = await admin.rpc(
        "link_employee_auth_user",
        {
          p_company_id: companyId,
          p_employee_id: employeeId,
          p_auth_user_id: authUserId,
          p_actor_employee_id: actorEmployeeId,
        },
      );

      if (linkError) {
        await recordInvite(admin, {
          companyId,
          employeeId,
          email,
          invitedBy: actorEmployeeId,
          status: "failed",
          authUserId,
        });
        return json({
          ok: false,
          reason: "link_failed",
          account_ready: false,
          email_delivered: false,
        }, 200);
      }

      const link = asObject(linkRaw);
      if (link.ok !== true) {
        await recordInvite(admin, {
          companyId,
          employeeId,
          email,
          invitedBy: actorEmployeeId,
          status: "failed",
          authUserId,
        });
        return json({
          ok: false,
          reason: str(link.reason) || "link_failed",
          account_ready: false,
          email_delivered: false,
        }, 200);
      }
    } else {
      await admin.auth.admin.updateUserById(authUserId, {
        user_metadata: emailMeta,
      });
    }

    let emailDelivered = false;
    try {
      const recoverOpts: { redirectTo?: string } = {};
      if (redirectTo) recoverOpts.redirectTo = redirectTo;
      const { error: recoverError } = await admin.auth.resetPasswordForEmail(
        email,
        recoverOpts,
      );
      emailDelivered = recoverError == null;
    } catch {
      emailDelivered = false;
    }

    await recordInvite(admin, {
      companyId,
      employeeId,
      email,
      invitedBy: actorEmployeeId,
      status: emailDelivered ? "sent" : "failed",
      authUserId,
    });

    return json({
      ok: true,
      account_ready: true,
      email_delivered: emailDelivered,
      employee_id: employeeId,
      full_name: fullName || undefined,
    }, 200);
  } catch (error) {
    const reason = error instanceof InviteError
      ? error.reason
      : "invite_failed";
    await recordInvite(admin, {
      companyId,
      employeeId,
      email,
      invitedBy: actorEmployeeId,
      status: "failed",
      authUserId: authUserId || null,
    }).catch(() => {});
    return json({
      ok: false,
      reason,
      account_ready: Boolean(authUserId),
      email_delivered: false,
    }, 200);
  }
});

class InviteError extends Error {
  constructor(readonly reason: string) {
    super(reason);
  }
}

async function buildInviteEmailMetadata(
  admin: ReturnType<typeof createClient>,
  args: {
    employeeId: string;
    companyId: string;
    email: string;
    fullName: string;
  },
): Promise<Record<string, unknown>> {
  const { data } = await admin
    .from("employees")
    .select("full_name, roles(code, name), companies(name)")
    .eq("id", args.employeeId)
    .eq("company_id", args.companyId)
    .maybeSingle();

  const row = asObject(data);
  const role = asObject(row.roles);
  const company = asObject(row.companies);
  const name = str(row.full_name) || args.fullName;
  const companyName = str(company.name);
  const roleLabel = roleLabelFor(str(role.code), str(role.name));
  const local = emailLocal(args.email);

  return {
    sello_team_invite: true,
    ...(name ? { full_name: name, greeting_name: name } : {}),
    ...(local ? { email_local: local } : {}),
    ...(companyName ? { company_name: companyName } : {}),
    ...(roleLabel ? { role_label: roleLabel } : {}),
  };
}

function roleLabelFor(code: string, name: string): string {
  switch (code.toLowerCase()) {
    case "owner":
      return "Owner";
    case "manager":
      return "Manager";
    case "administrator":
      return "Administrator";
    case "sales_representative":
      return "Sales Rep";
    default:
      return name || code;
  }
}

function emailLocal(email: string): string {
  const at = email.indexOf("@");
  if (at <= 0) return email;
  return email.slice(0, at);
}

async function ensureAuthUser(
  admin: ReturnType<typeof createClient>,
  email: string,
  emailMeta: Record<string, unknown>,
): Promise<{ userId: string; created: boolean }> {
  const password = `${crypto.randomUUID()}Aa1!`;
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: emailMeta,
  });

  if (!error && data.user?.id) {
    return { userId: data.user.id, created: true };
  }

  const message = (error?.message ?? "").toLowerCase();
  const already = message.includes("already") ||
    message.includes("registered") ||
    message.includes("exists") ||
    error?.status === 422;

  if (!already) {
    throw new InviteError("auth_create_failed");
  }

  const { data: linkData, error: linkError } = await admin.auth.admin
    .generateLink({
      type: "recovery",
      email,
    });

  const userId = linkData?.user?.id;
  if (linkError || !userId) {
    throw new InviteError("auth_lookup_failed");
  }

  await admin.auth.admin.updateUserById(userId, {
    user_metadata: emailMeta,
  });

  return { userId, created: false };
}

async function recordInvite(
  admin: ReturnType<typeof createClient>,
  args: {
    companyId: string;
    employeeId: string;
    email: string;
    invitedBy: string;
    status: string;
    authUserId: string | null;
  },
) {
  await admin.from("employee_invites").insert({
    company_id: args.companyId,
    employee_id: args.employeeId,
    email: args.email,
    invited_by: args.invitedBy,
    status: args.status,
    auth_user_id: args.authUserId,
  });
}

function sanitizeRedirect(value: string): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    // Path must be login (recovery completion lands on /login).
    if (url.pathname !== "/login" && !url.pathname.endsWith("/login")) {
      return null;
    }
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

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
