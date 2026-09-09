# Passenger Home, journey planning and Account Security changes

## 1. Architecture inspected before editing

The current checkout was clean on branch `yien`. This Flutter/Supabase checkout, rather than any older version, was used as the baseline.

- Passenger Home used an AppBar with profile/sign-out actions and three navigation cards: Departure Recommendation, Realtime Journey Tracker, and Realtime Data Check.
- Departure Recommendation already used a constrained, responsive form with one vertical scroll parent. Stop selection used a fixed header above a scrolling result area.
- Direct routes were matched by GTFS trip and stop order. The existing transfer planner supported one transfer at a shared stop between different trips on different routes. Timetable recommendations used `gtfs_calendar`, trip services, ordered stop times, a five-minute minimum transfer, equivalent-result pruning, and a five-result limit.
- Planner results already supported saving, recent history, route maps, bus feedback, reminders, and selected-journey tracking. Home's reminder summary supported viewing and cancelling, with no existing live-tracking handoff.
- Email/password, Google OAuth, PKCE recovery, provider identity detection and current-password verification already existed. The current authentication method was not distinguished from linked account providers.
- Profiles, saved journeys, reports and reminders used authenticated Supabase user IDs. Recent history used a local SQLite database per user ID; nearby-radius preferences used SQLite rows keyed by user ID.

## 2. Home UI

Home now contains a time-based greeting, the existing profile display name, a short welcome line, one primary **Plan a Journey** action, and upcoming journeys or a clean empty state. It retains the existing theme. Personal-data sections remain in their existing pages.

## 3. Portrait and landscape

Home has a constrained scrolling body and horizontally scrollable top navigation. The planner retains its width-based side-by-side/vertical stop and date/time layouts. Travel-mode controls wrap. Journey actions retain two columns where space permits and stack on narrower cards. Stop selection scrolls its header and results together so a landscape keyboard cannot squeeze important controls into an overflowing fixed column.

Rotation tests exercise both orientations, scrolling to important controls and checking hit-test availability. Stop-selection coverage includes landscape keyboard insets and the last result in a 50-stop list.

## 4. Scroll behavior

Home, planner and stop selection explicitly use `ClampingScrollPhysics`. The planner has one vertical page scroll parent; stop selection now also has one. Home's horizontal navigation is independent of its vertical body. Existing scrolling dialogs remain separate routes/overlays.

## 5. Depart At / Arrive By

`TravelTimeMode` defaults to `departAt`, preserving existing callers and date/time picker styling. Depart At excludes departures before the selected time. Arrive By excludes arrivals after the selected time for both direct and transfer candidates, including exact-target arrivals. Filtering happens before selecting each trip/pair's candidate, pruning, sorting and applying the result limit.

Existing GTFS calendar/service-day interpretation and transfer candidate limits remain unchanged. No timetable values are invented.

## 6. Best Choice algorithm

The first ranked journey alone receives **BEST CHOICE**. Alternatives remain visible within the existing five-result limit.

- Depart At: earliest arrival, fewer transfers, less transfer waiting, earlier departure, stable trip/stop identifiers.
- Arrive By: latest valid arrival (closest to the target), fewer transfers, less transfer waiting, later departure, stable trip/stop identifiers.

The comparison is deterministic and uses no percentage or numeric recommendation score. Best Choice is selected from the existing planner's candidates, not a claim of global network optimization.

## 7. Recommendation reasons

Reasons show only facts supported by the recommendation: arrival at/before the requested target, the departure offset from the requested time, direct travel, or one transfer with its actual waiting duration. No walking or comparative waiting claim is fabricated.

## 8. Reachable destinations

The existing transfer repository now exposes structural reachability. It reuses its GTFS endpoint/stop loaders and shares the planner's different-trip/different-route transfer rule.

For direct travel it collects stops strictly downstream of the origin's earliest occurrence on each serving trip. It excludes the origin and deduplicates by stop ID. It also includes stops reachable downstream on a second trip boarded at a valid downstream transfer stop. An upstream stop is not included merely because it shares a trip; it can still be legitimately reachable through a separate supported transfer.

Destination selection is disabled until an origin exists. Its list and text search operate only on reachable stops. Origin changes, reversing, saved-pair initialization and restored searches refresh reachability and clear incompatible destinations. Request generations protect against stale responses. Failures expose retry instead of falling back to all stops. Actual service-date and timetable feasibility is still checked by Find Journey.

## 9. Current Location

The existing location service, permission handling, 500 m / 1 km / 2 km options, nearby results and explicit boarding-stop selection are preserved. The selected nearby stop returns through the same origin handler as manual selection and triggers identical destination filtering. No stop is automatically guessed.

## 10. Module 3 and navigation

The existing Real-time Journey Tracker remains accessible from Home's top navigation. Realtime Data Check is also retained. Profile/Reports and Plan remain accessible, along with the existing profile/sign-out icons. Planner results still open the existing selected-journey tracker. No Module 3 implementation file was modified. Home's saved reminder summary does not invent a Track Live action.

## 11. Email + Google identity findings

Application ownership remains based on authenticated user ID, not email. No ownership repository, record migration, identity merge, email-based sharing or account-linking operation was introduced. Tests demonstrate local recent-search reuse for the same user ID and identical saved-journey access under a changed provider context with the same ID. Existing report/reminder ownership coverage remains intact.

Recent searches and radius preferences remain device-local: linked logins on the same installation share them, but this change does not add cross-device synchronization.

## 12. Do the real login methods resolve to the same ID?

**Not verified from this repository.** Matching email addresses are insufficient evidence. No live authenticated account or dashboard identity inspection was performed.

## 13. Change Email Password

| Account / current session | Behavior |
| --- | --- |
| Google-only | Profile shows Google management information and no Change Email Password action. |
| Email-only, password session | Current Password, New Password and Confirm New Password. Existing Supabase reauthentication verifies the current credential and checks the user ID before updating. |
| Dual identity, password session | Both sign-in methods are listed; the email-password form explains that Google credentials are unaffected. |
| Dual identity, Google OAuth session | Existing reset-link page is reused with the account email prefilled and read-only, explanatory text and Send Reset Link. No current-password field. |
| Email-capable account, unknown/non-password session | Conservative reset-link flow rather than assuming password authentication. |

Session selection reads the current SDK session's `amr` claim, not the original provider metadata. This is a UI/flow decision; Supabase still performs credential verification and authorization. The existing recovery validation, PKCE handling, cooldown and reset implementation are reused. No plaintext password storage is added.

References: [Supabase authentication-method claims](https://supabase.com/docs/guides/auth/jwt-fields), [Supabase identity linking](https://supabase.com/docs/guides/auth/auth-identity-linking).

## 14. Exact existing files modified

```text
lib/features/authentication/data/auth_repository.dart
lib/features/authentication/presentation/change_password_page.dart
lib/features/authentication/presentation/forgot_password_page.dart
lib/features/departure_recommendation/data/timetable_recommendation_repository.dart
lib/features/departure_recommendation/data/transfer_journey_repository.dart
lib/features/departure_recommendation/presentation/departure_recommendation_page.dart
lib/features/departure_recommendation/presentation/stop_selection_page.dart
lib/features/journey_reminders/reminder_widgets.dart
lib/features/passenger_home/presentation/passenger_home_page.dart
lib/features/passenger_profile/presentation/passenger_profile_page.dart
test/features/authentication/account_security_pages_test.dart
test/features/authentication/account_security_repository_test.dart
test/features/authentication/auth_pages_test.dart
test/features/authentication/auth_test_support.dart
test/features/departure_recommendation/departure_recommendation_test.dart
test/features/departure_recommendation/planning_actions_test.dart
test/features/departure_recommendation/recent_search_repository_test.dart
test/features/departure_recommendation/saved_journey_repository_test.dart
test/features/departure_recommendation/stop_selection_page_test.dart
test/features/journey_reminders/journey_reminders_test.dart
test/features/passenger_profile/account_security_test.dart
test/features/passenger_profile/profile_reports_test.dart
```

## 15. Exact new files

```text
test/features/departure_recommendation/responsive_planning_test.dart
test/features/departure_recommendation/travel_time_reachability_test.dart
test/features/passenger_profile/home_rotation_test.dart
docs/passenger_planning_changes.md
```

## 16. Migrations

None required or modified. Dependencies, database ownership and RLS logic are unchanged.

## 17. Focused test results

Final focused run: **221 passed, zero failures**, covering departure recommendation, authentication, passenger profile/Home, reminders and departure-to-feedback compatibility. Earlier failures were corrected and affected tests rerun before the full suite.

## 18. Full Flutter test suite

`flutter test --reporter expanded` ran once after the implementation stabilized: **714 passed, zero failures**. The only subsequent Dart change was adding braces around an existing conditional in the new Home test; runtime behavior was unchanged.

## 19. Static analysis

`flutter analyze` ran once and exited 1 with six informational brace-style notices. One was in the new Home test and was fixed; `dart analyze test/features/passenger_profile/home_rotation_test.dart` then passed with **No issues found**. No second full analysis was run.

The other five notices predate these changes and remain untouched:

```text
lib/features/ai_transit_recommendation/presentation/cost_estimation_report_page.dart:132
lib/features/ai_transit_recommendation/presentation/cost_estimation_report_page.dart:169
lib/features/ai_transit_recommendation/presentation/cost_estimation_report_page.dart:600
test/features/ai_transit_recommendation/bus_frequency_recommendation_repository_test.dart:403
test/features/ai_transit_recommendation/bus_frequency_recommendation_repository_test.dart:419
```

## 20. Diff validation and scope review

Final diff reviewed against the clean initial branch. Changes retain existing profile, saved journeys, recent searches, reports, reminders, maps, feedback and tracker actions. Admin, Module 3 internals, dependencies and migrations were not changed. No unrelated teammate functionality was removed or overwritten. No commit or push was performed.

`git diff --check` ran once and passed (exit 0). Git emitted only its normal LF-to-CRLF conversion notices; no whitespace errors were reported.

## 21. Supabase/runtime checks still required

1. Sign in with Email & Password and inspect `Supabase.instance.client.auth.currentUser!.id` and the user's identity providers.
2. Sign out, sign in with Google, and inspect the same values. Confirm that the exact UUID is identical, not merely the email address.
3. In Supabase Authentication > Users, inspect that user's linked identities and confirm both email and Google belong to that user. Confirm the email credential is usable; an email identity alone is not proof that a password has been configured in every possible Supabase flow.
4. On the same app installation, compare profile/name, recent searches, saved journeys, reports, reminders/upcoming journeys and radius preferences across both sessions.
5. Exercise the configured reset email/deep link end-to-end for a Google-authenticated dual account, including invalid/expired links. These live email delivery and project redirect settings cannot be verified by the repository tests.
6. If the UUIDs differ, stop before any linking or data change and inspect the project's verified identities and supported authenticated linking flow. This implementation intentionally performs no email-based merge.

Device-level location permissions, notification delivery, physical rotation and live GTFS/Supabase query latency remain integration checks; widget tests use controlled fixtures.
