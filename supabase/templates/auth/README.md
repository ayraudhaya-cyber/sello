## Variables preserved

All action links use `{{ .ConfirmationURL }}` only. Do not replace this with a hardcoded URL.

Personalized greeting + optional company/role badge use Auth `user_metadata` via `{{ .Data.* }}`:

| Template field | Source |
| --- | --- |
| `greeting_name` / `full_name` | Owner name at signup, or employee name on invite |
| `email_local` | Part before `@` (e.g. `velvetkutty`) — set in app / Edge Function because templates cannot split `{{ .Email }}` |
| `company_name` | Business name when known |
| `role_label` | `Owner`, `Sales Rep`, `Manager`, … |
| `sello_team_invite` | `true` on Hub team invites (cleared after they set a password) |

Greeting renders as: **Hi {name or email_local or there},**

Badge (lavender pill) only when `company_name` is present:
`{company_name}` or `{company_name} — {role_label}`.

### Reset password template (`recovery.html`)

Both Hub invites and Forgot Password use Supabase’s **Reset password** email (same `resetPasswordForEmail` path). Copy is branched in the template:

| Condition | Wording |
| --- | --- |
| `.Data.sello_team_invite` is true | Welcome / first-time invite — “Set your password” |
| otherwise | Forgot-password — “Reset password” |

Paste `recovery.html` into Dashboard → Authentication → Email Templates → **Reset password**.

`invite.html` stays in sync for the Dashboard **Invite user** template if you ever use Auth invites directly.

Signup writes flat personalization fields next to `pending_business` (trigger still only reads `pending_business`). Team invites write them in `invite-employee-login` before the recovery email is sent.

## Deploy checklist

1. Paste updated HTML into Dashboard Auth templates (Reset password ← `recovery.html`).
2. Redeploy Edge Function after invite metadata / mailer changes:

```bash
npx supabase functions deploy invite-employee-login --no-verify-jwt --project-ref pohfozsptcrnitbxgaep
```

## Do not put in templates
