# Account Security update

This update preserves the existing Google OAuth, PKCE, `AUTH_REDIRECT_URL`,
Android callback, `app_links` handling, recovery routing barrier, AuthGate role
routing and `ensure_current_google_profile` function. No migration is needed.

Signup, recovery and Change Password share the pure `AuthValidation` utility.
Emails are trimmed; passwords are not trimmed for submission. New passwords
are compared with email after trimming/case folding solely for validation.
Current/new password comparison is exact. There are no SQL-injection heuristics
or SQL queries constructed from credentials.

Forgot Password always uses the existing Supabase recovery endpoint and its
configured redirect. Both normal success and `user_not_found` have the same
neutral first-request response. The resend acknowledgement is also independent
of account existence. A 60-second cooldown begins on each submitted attempt,
including failures, and a synchronous busy guard prevents duplicate requests.
The screen locks the requested email so resend cannot silently target another
address. The timer is disposed when the page closes. Supabase rate limits remain
authoritative; the local UI cooldown is not a replacement for server limits.

Account Security uses the current Supabase user's linked `email` and `google`
identities, not the presence of an email address or user-editable metadata.
Google-only users are never asked for a Google password. Accounts with an email
identity can change this app's password; linked Google login remains independent.
The public SDK does not expose a password hash or a definitive `hasPassword`
flag. An email identity can also support passwordless auth in Supabase; the
existing app offers email/password and Google. Password verification remains
required, so a passwordless email identity cannot bypass the current-password
check. If identities are unavailable, Change Password is hidden conservatively.

Change Password reauthenticates the current authenticated user's email with
`signInWithPassword` through the existing repository/SDK. Incorrect credentials
stop the update. The returned ID must equal the original authenticated ID;
an unexpected identity is signed out. The repository then updates only the
password using `updateUser`, leaving profile identity, name and role untouched.
No old password is retrieved or persisted. Input controllers are cleared after
requests and disposed with the page. Supabase manages its normal session state.

Supabase's supported Auth API accepts `current_password` when a project's
security configuration requires it. The installed Dart `UserAttributes` does
not yet expose that field, so a small private subclass adds it to `toJson()`
for this Auth update only. It is not written to any application table, file,
preferences or logs. No SDK/package upgrades or OAuth changes are introduced.

Recovery still requires the verified recovery session and signs out after a
successful reset. It now reports: “Password updated successfully. Please sign
in with your new password.”

## Secure password-reuse detection

Supabase documents `same_password` for attempts to set the existing password.
The Auth server checks that password against its stored credential securely.
Only that error code maps to “Your new password cannot be the same as your
previous password.” Other failures are not labelled password reuse.

This detects reuse of the current password when the deployed Supabase Auth
server reports it; it does not establish a history of all previous passwords.
No client password-history or recovery-password comparison is implemented.
The live project's Auth server/configuration has not been changed or tested
against real credentials here.

## Existing-account signup limitation

Explicit `user_already_exists`/`email_exists` errors map to the requested sign-in
message. The existing-confirmed-user obfuscated response (no session and an
explicitly empty identities array) is also handled without profile queries.
Supabase may treat an unconfirmed repeat signup as a confirmation resend and
return a normal user; the app cannot reliably label that case as duplicate
without defeating the Auth API's intentional account-disclosure behavior.
No public account lookup, manual identity linking or profile insertion is added.

## References and device checks

- [Supabase Auth error codes](https://supabase.com/docs/guides/auth/debugging/error-codes)
- [Flutter signup response behavior](https://supabase.com/docs/reference/dart/auth-signup)
- [Supabase Auth password update implementation](https://github.com/supabase/auth/blob/master/internal/api/user.go)
- [Supabase identities](https://supabase.com/docs/guides/auth/identities)

On device, verify reset email/resend delivery and configured rate limits,
recovery reset/sign-out, current-password rejection/success, and Google-only
and dual-identity profiles. Verify existing admin routing remains unchanged.
No Google password is entered in this app and app password changes do not alter
the user's Google Account password.

## Validation and changed files

Focused auth/profile tests: **84 passed** using
`flutter test --no-pub test/features/authentication test/features/passenger_profile`.
No live credentials or external configuration were used in the tests.
`flutter analyze --no-pub` reported only the three pre-existing informational
brace notices in `cost_estimation_report_page.dart` (132, 169, 600), exiting 1.
No new analyzer issues remain. `git diff --check` and whitespace checks on the
new files passed. Live reset-email delivery and device checks remain manual.

Files changed for this update:

- `lib/features/authentication/data/auth_repository.dart`
- `lib/features/authentication/presentation/auth_validation.dart`
- `lib/features/authentication/presentation/register_page.dart`
- `lib/features/authentication/presentation/forgot_password_page.dart`
- `lib/features/authentication/presentation/reset_password_page.dart`
- `lib/features/authentication/presentation/change_password_page.dart` (new)
- `lib/features/passenger_profile/presentation/passenger_profile_page.dart`
- `test/features/authentication/auth_validation_test.dart`
- `test/features/authentication/auth_pages_test.dart`
- `test/features/authentication/auth_test_support.dart`
- `test/features/authentication/account_security_repository_test.dart` (new)
- `test/features/authentication/account_security_pages_test.dart` (new)
- `test/features/passenger_profile/travel_profile_test.dart`
- `test/features/passenger_profile/account_security_test.dart` (new)
- `docs/account-security.md` (new)

The existing Google/PKCE/deep-link implementation, Android configuration,
AuthGate and database migrations have no changes. No commit or push was made.
