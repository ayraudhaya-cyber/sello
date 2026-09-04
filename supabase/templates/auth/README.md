## Variables preserved

All action links use `{{ .ConfirmationURL }}` only. Do not replace this with a hardcoded URL.

Personalized greeting + optional company/role badge use Auth `user_metadata` via `{{ .Data.* }}`:

| Template field | Source |
| --- | --- |
| `greeting_name` / `full_name` | Owner name at signup, or employee name on invite |
| `email_local` | Part before `@` (e.g. `velvetkutty`) — set in app / Edge Function because templates cannot split `{{ .Email }}` |
| `company_name` | Business name when known |
| `role_label` | `Owner`, `Sales Rep`, `Manager`, … |

Greeting renders as: **Hi {name or email_local or there},**

Badge (lavender pill) only when `company_name` is present:
`{company_name}` or `{company_name} — {role_label}`.

Signup writes these flat fields next to `pending_business` (trigger still only reads `pending_business`). Team invites write them in `invite-employee-login` before the recovery email is sent.

## Deploy checklist

1. Paste updated HTML into Dashboard Auth templates (see table above).
2. Redeploy Edge Function after invite metadata changes:

```bash
npx supabase functions deploy invite-employee-login --no-verify-jwt --project-ref pohfozsptcrnitbxgaep
```

## Do not put in templates
