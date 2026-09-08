# Authentication implementation and deployment setup

## Existing architecture

`main.dart` loads `.env` and initializes `supabase_flutter` (locked at 2.16.0).
`App` hosts `AuthGate`. Email/password login and signup use `AuthRepository`;
the gate loads `profiles` with `user_id = currentUser.id` and routes the stored
`passenger` or `admin` role. Unknown roles and missing profiles block access.
Signup sends `full_name` metadata. The existing `on_auth_user_created` database
trigger creates a passenger profile. Profile identity and role updates are
protected by database triggers; controlled SQL functions administer roles.

The profile schema is `user_id` (primary key referencing `auth.users.id`),
`full_name`, `role`, `phone_number`, `created_at`, and `updated_at`. There is no
profile email column: the app reads the authenticated Supabase user's email.
Empty names already fall back to that email, then `User`, for display.

There was no configured authentication callback URL, Android VIEW intent filter,
custom scheme, app link, recovery screen, or app-level callback handler.
Android application ID and namespace are both
`com.example.government_transit_collector`. The Gradle file still identifies this
as a placeholder application ID and uses debug signing for release; this change
does not alter either setting. No production signing identity can be inferred.

## Implemented flows

- Login keeps email/password validation and submission and the existing signup
  page. It adds the requested heading, divider, Google button, Forgot Password,
  and Sign Up order. All three auth forms scroll within a width limit and respect
  the keyboard's available height.
- Google invokes `signInWithOAuth(OAuthProvider.google)` with the configured
  redirect and an external browser. Supabase generates and exchanges PKCE codes.
  Browser launch failure, provider denial, callback failure and profile failure
  have sanitized messages. An explicit **Cancel Google sign-in** action clears
  the SDK's pending verifier. External browser closure alone does not reliably
  report cancellation; users can return to the app and use this action.
- A Google session loads the existing profile by authenticated user ID. It does
  not query by email, manually link identities, copy data, or update an existing
  name or role. Supabase-managed identity linking is accepted as returned.
- If the Google profile is missing, the repository invokes
  `ensure_current_google_profile`, then re-reads the profile by the same ID.
  The function derives identity from `auth.uid()`, verifies the Google identity
  in `auth.identities`, and obtains metadata from that same `auth.users` row.
  `full_name`, then `name`, are used only if they are nonempty strings; otherwise
  the existing empty-name/email display fallback applies. New rows always use
  `passenger`. `ON CONFLICT (user_id) DO NOTHING` preserves existing profiles,
  including admins, during concurrent requests. Metadata cannot set roles.
- Forgot Password validates email, then calls `resetPasswordForEmail` through
  the repository. It reports: “If an account exists for this email, a password
  reset link has been sent.” Backend errors do not disclose registration status.
  This operation never calls `updateUser` or writes a password.
- `AuthRepository` owns app-link handling. Supabase's automatic URI detection
  is disabled to prevent duplicate exchanges and premature home routing. The
  repository processes the initial link before `runApp` and listens for warm
  links. Scheme, host, port and path must match `AUTH_REDIRECT_URL` exactly.
  Only PKCE code callbacks are accepted; implicit token callbacks are rejected.
  The code exchange and recovery classification use Supabase's SDK, including
  its stored PKCE recovery event, rather than trusting a URI's `type` parameter.
- Callback processing blocks profile routing and removes pushed pages. Verified
  recovery routes to Reset Password; normal Google auth uses the existing role
  gate. Duplicate delivery of the same callback is ignored during the process.
- Reset validates required fields, eight-character minimum and matching values.
  Only a verified, unexpired recovery session may invoke
  `updateUser(UserAttributes(password: ...))`. Success clears the local Supabase
  session and recovery state, displays “Password updated successfully.” and
  returns to Login. Cancellation also signs out before releasing the gate.
- Two non-secret booleans in SharedPreferences record pending recovery and the
  recovery routing barrier. The barrier is written before a callback can persist
  a session. After an interrupted recovery/process restart, home remains blocked
  and a fresh recovery link is required. A normal session is never enough to
  call the repository's reset method. Passwords, OAuth codes and tokens are not
  written to application tables or application preferences or logs. Supabase
  continues to manage its own session and PKCE persistence.

Saved journeys, recent searches, reports, reminders, Passenger Profile and the
other passenger features retain their existing authenticated-user-ID ownership.
No data migration, email matching, or modifications to those modules were made.

## Required database deployment

Apply the new migration
`supabase/migrations/20260908000000_ensure_current_google_profile.sql` through
your usual Supabase migration workflow. It has **not** been applied remotely.

It is necessary for the explicit missing-Google-profile requirement: the
existing schema grants only SELECT/UPDATE on profiles and has no INSERT policy.
The new function avoids granting general profile inserts. It adds no table,
does not rewrite old migrations or profiles, and preserves existing triggers,
RLS and role administration. The existing signup trigger remains the primary
creation path for new Google users as well as email users.

Database execution/RLS and concurrent-insert behavior still need verification
against a disposable Supabase environment. Repository tests mock the RPC and
do not claim to execute PostgreSQL security rules.

## Values verified from this repository

| Setting | Verified value |
| --- | --- |
| Supabase project URL (local `.env`) | `https://hmbkuofoxrmwopyuaqlx.supabase.co` |
| Supabase Google OAuth callback for that project | `https://hmbkuofoxrmwopyuaqlx.supabase.co/auth/v1/callback` |
| Android application ID / namespace | `com.example.government_transit_collector` |
| App's OAuth/recovery redirect URL | **Not present; cannot be determined** |
| Google OAuth client ID / secret | **Not present; cannot be determined** |
| Production app domain / signing fingerprints | **Not present; cannot be determined** |

The Supabase callback above is the Google-to-Supabase callback. It is distinct
from the app redirect. Confirm it matches the Google provider panel for the
project you actually deploy to, especially if using a different project or a
custom Auth domain.

## Supabase Dashboard manual configuration

1. **Authentication → Providers → Google**: enable Google. Enter the Web OAuth
   client ID and client secret from Google Cloud. Keep the secret in Supabase,
   never in Flutter, `.env` assets, Android resources or version control.
2. Choose/confirm your app's approved callback URL. The repository cannot decide
   your scheme or owned app-link domain. Set that exact value as
   `AUTH_REDIRECT_URL` in the local `.env`. It must include scheme and host, have
   no username, query or fragment, and use an app scheme or HTTPS (not HTTP).
   Until set, Google and reset-email requests fail safely with a configuration
   message; email/password login and signup remain available.
3. **Authentication → URL Configuration → Redirect URLs**: allowlist the exact
   same app URL. Preserve existing Site URL and redirects used for signup;
   no replacement Site URL can be determined from the repository.
4. **Authentication → Email Templates → Reset Password**: verify the recovery
   template uses Supabase's recovery confirmation link (`{{ .ConfirmationURL }}`)
   and does not replace it with an unverified direct app URL. Verify recovery
   mail delivery/SMTP and the password policy (at least eight characters).
5. Apply the missing-profile function migration and verify the existing signup
   trigger and controlled-role migration are deployed.

## Google Cloud Console manual configuration

1. Configure the Google Auth Platform consent screen/branding and audience for
   the app. If the app is in testing, add the intended Google test users.
2. Create or use an OAuth client of type **Web application** for the Supabase
   browser OAuth flow. In **Authorized redirect URIs**, add exactly
   `https://hmbkuofoxrmwopyuaqlx.supabase.co/auth/v1/callback` for the verified
   repository project (or the callback shown by your actual Supabase provider).
3. Copy its client ID and secret to the Supabase Google provider settings. The
   client ID/secret cannot be inferred here. The requested identity scopes are
   the standard email/profile/OpenID scopes; no offline Google API access is
   needed by this implementation.
4. This browser flow does not introduce `google_sign_in`, an Android OAuth
   client, `google-services.json`, SHA-1 settings, or embedded OAuth secrets.
   Do not use the app's custom callback URL as Google's authorized redirect.
   Web JavaScript origins, if needed for a separate web deployment, must use
   its actual owned origin; none is established by this repository.

## Android configuration still required

After choosing the approved URL, add a VIEW/BROWSABLE/DEFAULT intent filter to
the existing `.MainActivity` in `android/app/src/main/AndroidManifest.xml`.
Use the **actual scheme, host and exact path from that URL**, with `android:port`
if the chosen URL specifies a non-default port. Do not paste a fabricated sample
scheme. Ensure a trailing slash in the URL and manifest path agree.

For an HTTPS App Link, also configure Android domain verification and the owned
domain's `/.well-known/assetlinks.json` using the actual application ID and
signing certificate fingerprint. Those domain/fingerprint values are unknown.
For a custom scheme, configure the chosen scheme/host/path consistently; domain
verification is not applicable.

The repository adds `flutter_deeplinking_enabled=false` so Flutter's default
route handling does not compete with `app_links`. Existing `singleTop`,
`android:exported=true`, INTERNET permission and `adjustResize` remain in place.
No guessed intent filter or package/signing changes were added. Verify both
debug and release merged manifests and callback dispatch on device.

Other platform URL registrations (iOS/macOS/Windows or a web deployment) have
not been configured; supply their approved platform-specific settings if those
platforms are distributed.

## Manual verification after configuration

- Email login/signup, confirmation and logout; passenger and existing admin
  routing. Confirm signup/profile triggers run on the deployed database.
- Google: new passenger, existing passenger, existing admin, provider denial,
  browser back/closure then explicit cancel, network failure and successful
  retry. Test warm and cold starts, duplicate callback delivery and malformed
  or wrong-path links. Confirm profiles and user data remain tied to the actual
  authenticated Supabase ID, including Supabase-linked identities.
- Missing profile: repair creates exactly one passenger row; repeated/concurrent
  calls preserve its role/name; an existing admin is unchanged; anon and
  non-Google callers cannot create profiles or select another identity.
- Recovery: request mail, open it in the **same app installation** that sent the
  request (PKCE verifier requirement), change password, return to Login and sign
  in with the new password. Verify expired/reused links, a different device,
  offline update, cancellation, app termination during recovery and recovery
  opened over an existing authenticated subpage. Home must stay inaccessible
  until recovery is cancelled or completed and normal login occurs.
- At phone sizes, open the keyboard on every field and scroll to all actions.
  Check large text sizes and both debug and release Android builds.

## Official flow references

- [Supabase Flutter OAuth](https://supabase.com/docs/reference/dart/auth-signinwithoauth)
- [Supabase Flutter password recovery](https://supabase.com/docs/reference/dart/auth-resetpasswordforemail)
- [Supabase native mobile deep linking](https://supabase.com/docs/guides/auth/native-mobile-deep-linking?platform=flutter)
- [Supabase Google provider configuration](https://supabase.com/docs/guides/auth/social-login/auth-google)

## Changed files

- `.env.example`: documents the required, intentionally unset callback URL.
- `android/app/src/main/AndroidManifest.xml`: disables competing Flutter default
  deep-link routing and points to the required intent-filter setup.
- `lib/app/app.dart`: accepts the initialized authentication repository.
- `lib/main.dart`: initializes callback handling before constructing the UI.
- `lib/core/config/supabase_config.dart`: explicitly selects PKCE and disables
  duplicate automatic callback processing.
- `lib/features/authentication/data/auth_repository.dart`: Google, recovery,
  callback isolation, cancellation and missing-profile repair.
- `lib/features/authentication/presentation/auth_gate.dart`: prioritizes callback
  processing/recovery over role routing and clears pushed pages for callbacks.
- `lib/features/authentication/presentation/login_page.dart`: requested layout,
  Google launch/cancel and Forgot Password navigation.
- `lib/features/authentication/presentation/forgot_password_page.dart`: new form.
- `lib/features/authentication/presentation/reset_password_page.dart`: new form.
- `pubspec.yaml` and `pubspec.lock`: promote already installed `app_links` and
  `shared_preferences` to direct dependencies; no package versions changed.
- `supabase/migrations/20260908000000_ensure_current_google_profile.sql`:
  restricted, idempotent missing-profile creation function.
- `test/features/authentication/auth_repository_test.dart`: SDK/repository tests.
- `test/features/authentication/auth_pages_test.dart`: form/navigation/UI tests.
- `test/features/authentication/auth_test_support.dart`: isolated mock backend.
- `docs/authentication.md`: this implementation and configuration report.

## Validation on 2026-09-08

- Focused authentication and existing passenger-profile regressions:
  `flutter test --no-pub test/features/authentication test/features/passenger_profile`
  — **46 passed**.
- Full suite: `flutter test --no-pub` — **663 passed**. Local output is retained
  in ignored `build/auth-full-test.log`.
- `flutter analyze --no-pub` — no new issues; exit code 1 for three pre-existing
  `curly_braces_in_flow_control_structures` informational notices in
  `lib/features/ai_transit_recommendation/presentation/cost_estimation_report_page.dart`
  at lines 132, 169 and 600. That file was not modified.
- `git diff --check` — passed (Git emitted only line-ending conversion notices).
- No live Supabase or Google configuration was changed. No database migration
  was executed, and no emulator/device OAuth or recovery-mail test was performed.
- No commit or push was performed.
