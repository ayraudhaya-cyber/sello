# Sello Auth email templates

Supabase Auth emails are **not applied from this folder automatically**. Paste each HTML file into the matching template in:

**Supabase Dashboard → Authentication → Email Templates**

Project: `pohfozsptcrnitbxgaep` (Sello)

Sender (SMTP / Resend, already configured — do not change SMTP here):

```
Sello <sello@cashro.pro>
```

If the From name still shows Supabase, set it in Dashboard → Authentication → Emails (or the Resend domain “From” used by Auth).

## Files

| File | Dashboard template | Subject |
| --- | --- | --- |
| `confirm.html` | Confirm signup | Confirm your Sello email |
| `recovery.html` | Reset password | Reset your Sello password |
| `invite.html` | Invite user **and** Reset password (see below) | You've been invited to Sello |

`_shell.html` is the shared layout reference only — do not paste it into Dashboard.

Header logo uses the existing Sello mark (`assets/brand/logo.png`), copied to `web/email/sello-mark.png` so it can be served at:

`https://sello.cashro.pro/email/sello-mark.png`

Deploy the Flutter web build (or that file) before sending live mail, or the mark will not load. The wordmark “Sello” still appears if the image is blocked.

## Sales Rep invitation vs Forgot password

Sales Rep login invites still use `resetPasswordForEmail` (unchanged). Supabase therefore sends the **Reset password** template, not Invite user.

There is only one Recovery template. For V1 invitation copy:

1. Paste `invite.html` into **Reset password**.
2. Also paste `invite.html` into **Invite user** (so the slot is ready if Auth later uses it).
3. Keep `recovery.html` in this folder for when Forgot password needs distinct copy.

Until Recovery is split, Forgot password users will receive the invitation-style email. The link still completes the existing recovery flow.

## Variables preserved

All action links use `{{ .ConfirmationURL }}` only. Do not replace this with a hardcoded URL.

## Do not put in templates

- Supabase product branding
- Cashro header/branding
- Text.lk or other provider names
- Real social profile URLs (footer icons are non-linked placeholders)
