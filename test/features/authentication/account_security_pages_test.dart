import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/authentication/presentation/change_password_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/forgot_password_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/register_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/reset_password_page.dart';
import 'auth_pages_test.dart' show PageAuth;

void main() {
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('resend has 60 second cooldown and never submits twice', (
    tester,
  ) async {
    final repository = PageAuth();
    final pending = Completer<void>();
    repository.pendingEmail = pending.future;
    await tester.pumpWidget(
      MaterialApp(home: ForgotPasswordPage(repository: repository)),
    );
    await tester.enterText(find.byType(TextFormField), ' user@example.com ');
    await tester.tap(find.text('Send Reset Link'));
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();
    expect(repository.resetEmailCalls, 1);
    expect(repository.sentEmail, 'user@example.com');
    expect(find.text("Didn't receive the email?"), findsOneWidget);
    pending.complete();
    repository.pendingEmail = null;
    await tester.pumpAndSettle();
    expect(
      find.text(
        'If an account exists for this email, a password reset link has been sent.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Resend available in 45s'), findsOneWidget);
    await tap(tester, find.text('Resend Reset Email'));
    expect(repository.resetEmailCalls, 1);
    await tester.pump(const Duration(seconds: 45));
    await tester.tap(find.text('Resend Reset Email'));
    await tester.tap(find.text('Resend Reset Email'));
    await tester.pumpAndSettle();
    expect(repository.resetEmailCalls, 2);
    expect(
      find.text('A new password reset email has been sent.'),
      findsOneWidget,
    );
    expect(find.text('Resend available in 60s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // Timer disposed on navigation.
    expect(tester.takeException(), isNull);
  });

  testWidgets('signup blocks password equal to email at the form', (
    tester,
  ) async {
    final repository = PageAuth();
    await tester.pumpWidget(
      MaterialApp(home: RegisterPage(repository: repository)),
    );
    final fields = find.byType(TextFormField);
    final values = [
      'Rider',
      ' user@example.com ',
      'USER@example.com',
      'USER@example.com',
    ];
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(fields.at(i), values[i]);
    }
    await tap(tester, find.text('Register'));
    expect(
      find.text('Password cannot be the same as your email address.'),
      findsOneWidget,
    );
    expect(repository.registrationCalls, 0);
  });

  testWidgets('recovery form rejects authenticated email equality', (
    tester,
  ) async {
    final repository = PageAuth();
    await tester.pumpWidget(
      MaterialApp(home: ResetPasswordPage(repository: repository)),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'RIDER@example.test',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'RIDER@example.test',
    );
    await tap(tester, find.widgetWithText(FilledButton, 'Reset Password'));
    expect(
      find.text('Password cannot be the same as your email address.'),
      findsOneWidget,
    );
    expect(repository.updatedPassword, isNull);
  });

  testWidgets(
    'change form validates current, length, email equality and confirmation on phone with keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      final repository = PageAuth();
      await tester.pumpWidget(
        MaterialApp(home: ChangePasswordPage(repository: repository)),
      );
      final button = find.widgetWithText(FilledButton, 'Change Email Password');
      final fields = find.byType(TextFormField);
      await tap(tester, button);
      expect(find.text('Current password is required.'), findsOneWidget);
      expect(find.text('Password is required.'), findsOneWidget);
      await tester.enterText(fields.at(0), 'password123');
      await tester.enterText(fields.at(1), 'short');
      await tap(tester, button);
      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );
      await tester.enterText(fields.at(1), 'password123');
      await tap(tester, button);
      expect(
        find.text('New password must be different from your current password.'),
        findsOneWidget,
      );
      await tester.enterText(fields.at(1), 'rider@example.test');
      await tap(tester, button);
      expect(
        find.text('Password cannot be the same as your email address.'),
        findsOneWidget,
      );
      await tester.enterText(fields.at(1), 'new-password123');
      await tester.enterText(fields.at(2), 'different');
      await tap(tester, button);
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(repository.changeCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('incorrect current password is displayed and fields cleared', (
    tester,
  ) async {
    final repository = PageAuth()
      ..changeError = 'Current password is incorrect.';
    await tester.pumpWidget(
      MaterialApp(home: ChangePasswordPage(repository: repository)),
    );
    for (final entry in [
      'wrong-password',
      'new-password123',
      'new-password123',
    ].asMap().entries) {
      await tester.enterText(
        find.byType(TextFormField).at(entry.key),
        entry.value,
      );
    }
    await tap(
      tester,
      find.widgetWithText(FilledButton, 'Change Email Password'),
    );
    expect(find.text('Current password is incorrect.'), findsOneWidget);
    expect(repository.changeCalls, 1);
    for (final field in tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    )) {
      expect(field.controller!.text, isEmpty);
    }
  });

  testWidgets('Google-only direct change page never renders password fields', (
    tester,
  ) async {
    final repository = PageAuth()
      ..emailPassword = false
      ..googleIdentity = true;
    await tester.pumpWidget(
      MaterialApp(home: ChangePasswordPage(repository: repository)),
    );
    expect(find.byType(TextFormField), findsNothing);
    expect(
      find.text('Your Google password is managed through your Google Account.'),
      findsOneWidget,
    );
    expect(repository.changeCalls, 0);
  });
}
