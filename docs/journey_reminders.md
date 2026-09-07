# Remind Me / Upcoming Journey

Implemented only journey reminders. Authentication and recommendation algorithms are unchanged.

## Deployment

Manually apply `supabase/migrations/20260907010000_journey_reminders.sql` through your normal Supabase migration workflow (or paste that complete file into the intended project's SQL editor). It has not been applied by this task. Do not rerun or edit earlier migrations. Rebuild/install the Android app after fetching dependencies with `flutter pub get`.

The new table stores owner, stable journey identity, route/trip IDs and display label, overall stops, original GTFS service date/seconds, absolute departure/reminder timestamps, offset, and creation timestamp. Identity includes route/trip IDs, stop sequences, overall stop IDs, service date, departure seconds, and second departure for transfers. The unique `(user_id, journey_key)` constraint handles concurrent duplicate inserts. RLS permits only the authenticated owner's SELECT/INSERT/DELETE; UPDATE has no policy. There is no admin read exception. Existing tables and migration files are untouched.

## Behavior and architecture

`ReminderJourney` snapshots the selected recommendation; direct and transfer reminders both use `departureSeconds` (first boarding for transfers). Both transfer route labels and the overall destination remain intact. There is one notification per journey. Time conversion reuses `transitServiceLocation` (`Asia/Singapore`), with midnight plus GTFS seconds, including values above 86400. Offsets are 5/10/15/30 minutes, default 10. Validation runs before permission requests and again before persistence/scheduling. Past departures, elapsed reminder times, and departures five minutes or less away are rejected.

`ReminderRepository` abstracts persistence; `SupabaseReminderRepository` scopes all reads/deletes to the current Supabase user, paginates, and resolves database unique conflicts to the existing record. `ReminderNotifications` abstracts permissions, scheduling and cancellation. `ReminderController` serializes operations, exposes observable reminder state, reconciles on login/app resume, and clears in-memory state on account changes. A one-shot UI expiry timer removes departed journeys; there is no polling or added background service.

Home shows all upcoming records chronologically. View Journey opens a read-only stored summary with dates and no realtime claims. Reminder Set opens a summary with Cancel Reminder. Cancellation cancels the local notification before deleting the record; failures remain visible and retryable. Logout cancels this device's notifications but preserves database records; signing in again restores future notification times when permission is available. Notifications whose reminder time has passed are not rescheduled, although their still-future departure remains visible on Home.

Scheduling failure triggers cancellation and database rollback. Network and OS scheduling are not an atomic transaction: if rollback fails, the record remains available for retry/cancellation. Existing device schedules survive an offline refresh. Supabase records synchronize on login/resume; this is a local notification feature, not a cross-device push synchronization service.

## Android

Added pinned `flutter_local_notifications` 21.0.0, compatible with Flutter 3.44.8/Dart 3.12.2 and the existing Java 17/AGP 9 setup. Existing `timezone` is reused. The package adds its platform dependencies and resolves transitive `xml` to 6.6.1. Generated macOS/Windows registration updates are dependency-generated.

- `POST_NOTIFICATIONS`: user-visible notification permission.
- `SCHEDULE_EXACT_ALARM`: user-granted exact departure reminder scheduling; no `USE_EXACT_ALARM` or full-screen permission.
- `RECEIVE_BOOT_COMPLETED` and the package scheduled/boot receivers: restore alarms after reboot/package replacement.
- Core library desugaring with `desugar_jdk_libs:2.1.4` supports package scheduling APIs.
- A dedicated white notification drawable and private lock-screen visibility are provided.

No permission prompt runs at startup. Set Reminder requests notification permission, then exact-alarm access when needed. Denial shows a message and creates no reminder. Restoration only checks existing permissions. Scheduling uses `exactAllowWhileIdle` with the database integer ID for stable replacement/cancellation.

Configuration follows the package's versioned setup documentation: https://pub.dev/packages/flutter_local_notifications/versions/21.0.0 . Android may suppress alarms after force-stop or under manufacturer restrictions; reopen the app to reconcile. Reboot restoration is handled by the package's persisted schedule/receivers.

## Manual acceptance after migration

1. Sign in with a valid passenger account; select future direct and transfer recommendations.
2. Set each offset, allow notification/alarm permissions, and verify actual delivery before departure on the device.
3. Deny each permission and verify the friendly error; enable permissions in Settings and retry.
4. Restart the app and reboot the device before reminder time; check delivery and stored Upcoming Journey cards.
5. Cancel from Home and Reminder Set; verify the OS notification is cancelled and the card/button updates.
6. Log out, sign in as a different user, and verify isolation; sign back in and verify restoration.
7. Validate database RLS using two actual authenticated accounts, including attempts to insert/read/delete another owner's row and update any reminder. Dart repository tests check request scoping and conflict handling but do not execute PostgreSQL RLS.

The Android APK was built and launched on API 36. End-to-end authenticated delivery and reboot/RLS verification require the unapplied migration and a valid passenger session; the emulator's pre-existing session reported an invalid refresh token. Unit/widget tests use fake notification services and do not require Android.

## Validation results

- Final `flutter test`: 613 passed (27 new reminder tests).
- `flutter analyze`: only three pre-existing `curly_braces_in_flow_control_structures` info notices in `cost_estimation_report_page.dart`, lines 132, 169, 600; command exits 1 because of these notices. No new reminder diagnostics.
- `git diff --check`: passed. Final diff reviewed for unrelated edits; existing migrations, bus feedback and recommendation algorithms unchanged.
- `flutter build apk --debug`: passed; `flutter run -d emulator-5554 --no-resident`: built, installed and launched on Android 16/API 36.
- A test run concurrent with the emulator exhausted host memory; after closing the emulator, the final ordinary `flutter test` passed.
- No commit, push or production migration execution.
