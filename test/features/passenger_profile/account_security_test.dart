import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/authentication/presentation/change_password_page.dart';
import 'package:government_transit_collector/features/passenger_profile/presentation/passenger_profile_page.dart';
import '../authentication/auth_pages_test.dart' show PageAuth;
import '../bus_feedback/report_form_test.dart' show ReportsFake;
import 'travel_profile_test.dart' as existing;

void main() {
  testWidgets(
    'Google-authenticated dual identity reuses recovery without password fields',
    (tester) async {
      final auth = PageAuth()
        ..googleIdentity = true
        ..sessionMethod = 'oauth';
      await tester.pumpWidget(
        MaterialApp(home: ChangePasswordPage(repository: auth)),
      );
      await tester.pumpAndSettle();
      expect(find.text('You signed in with Google.'), findsOneWidget);
      expect(find.text('Current Password'), findsNothing);
      expect(find.text('New Password'), findsNothing);
      await tester.ensureVisible(find.text('Send Reset Link'));
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();
      expect(auth.sentEmail, 'rider@example.test');
      expect(auth.resetEmailCalls, 1);
      expect(auth.changeCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  Future<void> show(WidgetTester tester, PageAuth auth) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PassengerProfilePage(
          profile: existing.profile,
          authRepository: auth,
          savedRepository: existing.SavedFake(),
          recentRepository: existing.RecentFake(),
          preferencesRepository: existing.PreferencesFake(),
          feedbackRepository: ReportsFake(),
          onProfileUpdated: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Account Security'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Google-only profile shows Google management and hides Change Email Password',
    (tester) async {
      final auth = PageAuth()
        ..emailPassword = false
        ..googleIdentity = true;
      await show(tester, auth);
      expect(find.text('Signed in with Google'), findsOneWidget);
      expect(
        find.text(
          'Your Google password is managed through your Google Account.',
        ),
        findsOneWidget,
      );
      expect(find.text('Change Email Password'), findsNothing);
    },
  );

  for (final google in [false, true]) {
    testWidgets(
      'profile password change succeeds for ${google ? 'dual-identity' : 'email'} account',
      (tester) async {
        final auth = PageAuth()..googleIdentity = google;
        await show(tester, auth);
        await tester.ensureVisible(find.text('Change Email Password'));
        await tester.tap(find.text('Change Email Password'));
        await tester.pumpAndSettle();
        expect(find.byType(ChangePasswordPage), findsOneWidget);
        if (google) {
          expect(
            find.text('This does not change your Google Account password.'),
            findsOneWidget,
          );
        }
        for (final entry in [
          'current-password123',
          'new-password123',
          'new-password123',
        ].asMap().entries) {
          await tester.enterText(
            find.byType(TextFormField).at(entry.key),
            entry.value,
          );
        }
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Change Email Password'),
        );
        await tester.tap(
          find.widgetWithText(FilledButton, 'Change Email Password'),
        );
        await tester.pumpAndSettle();
        expect(auth.changeCalls, 1);
        expect(find.byType(ChangePasswordPage), findsNothing);
        expect(find.byType(PassengerProfilePage), findsOneWidget);
        expect(find.text('Password updated successfully.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
