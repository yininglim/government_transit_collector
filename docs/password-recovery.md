# Cross-device password recovery deployment

Deploy `docs/reset-password.html` as `reset-password.html` in the **existing**
`looyien/government-transit-collector-site` GitHub Pages publishing directory.
Its final URL must be:

`https://looyien.github.io/government-transit-collector-site/reset-password.html`

The file contains only this app's Supabase project URL and public client key.
No service-role key, SMTP credential, or other private configuration belongs here.
No server, database migration, package installation, or new site is required.
This workspace change does not deploy the separate Pages site.

## Required Supabase Dashboard changes

1. **Authentication → URL Configuration → Redirect URLs:** add exactly
   `https://looyien.github.io/government-transit-collector-site/reset-password.html`.
   Keep both existing entries unchanged:
   - `governmenttransit://auth/callback` (Google/app flows)
   - `https://looyien.github.io/government-transit-collector-site/` (signup verification)
   No Site URL change is needed.
2. **Authentication → Email Templates → Reset Password:** replace only the reset
   link with this exact HTML. Do not modify Confirm Signup or other templates:

   ```html
   <a href="https://looyien.github.io/government-transit-collector-site/reset-password.html#token_hash={{ .TokenHash }}&amp;type=recovery">Reset Password</a>
   ```

   Using the old `{{ .ConfirmationURL }}` link would consume the token at Supabase
   and redirect with an app-bound PKCE code. The recovery page intentionally does
   not accept that code or borrow the requesting device's verifier.
3. Keep custom SMTP configured. If the mail provider rewrites/tracks links,
   disable click tracking for this auth email so the fragment is preserved.

Deploy the page and save the template before testing. Request a **fresh** reset
email from the updated app; old emails retain their old links.

## Flow and security

Both Forgot Password and the Google-session email-password reset action request
the same HTTPS destination. Successful requests show a neutral acknowledgement
and pop back to their caller (Sign In or Account Security). Errors stay on the
form; the existing cooldown and server rate limits remain in effect.

The browser removes the recovery fragment immediately and makes no Auth request
until the user chooses **Continue to password reset**. It sends the one-time
token hash to Supabase Auth `POST /auth/v1/verify` with `type: recovery`, then
checks the verified user's `identities` for an `email` identity before showing
password fields. Google-only users receive Google Sign-In guidance and their
recovery session is released without updating a password. Email-only and linked
Email+Google users can submit a valid matching password using the returned
access token for `PUT /auth/v1/user`. Supabase validates the token,
expiry, password rules, and account ownership. Email/password equality is checked
against the verified session's email before the update. The page never performs
database/profile writes and does not change Google passwords.

The signed-out request form stays neutral for all addresses, including unknown
and Google-only addresses: it cannot safely discover account providers from an
email address. Provider-specific rejection is limited to an authenticated user's
own email or a verified recovery link. The app also checks identity eligibility
before completing any app-based recovery. No identity is linked or created by
this flow. Publish the updated HTML to the existing Pages site for the web guard
to take effect; changing this workspace alone does not update the hosted page.

Recovery credentials stay in memory only: no cookies, local/session storage,
logs, or displayed tokens. The page has no external scripts or assets and sends
no referrer. After success it discards the session and attempts local-scope Auth
sign-out. Back to Sign In gives instructions to return to the original app,
without trying to launch an Android-only deep link on an iPhone or computer.

Sources: [Supabase email templates](https://supabase.com/docs/guides/auth/auth-email-templates),
[verifyOtp](https://supabase.com/docs/reference/javascript/auth-verifyotp),
[password recovery](https://supabase.com/docs/guides/auth/passwords).

## Focused verification

Run `node --test test/features/authentication/web_password_recovery_test.cjs`
for mocked web validation/recovery/error handling. Flutter tests cover the shared
HTTPS destination, neutral errors, request cooldown and return navigation.
These checks do not replace the final fresh-email test after Pages/template deployment.
