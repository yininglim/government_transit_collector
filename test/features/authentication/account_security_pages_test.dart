import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/authentication/presentation/change_password_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/forgot_password_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/register_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/reset_password_page.dart';
import 'auth_pages_test.dart' show PageAuth;
import 'package:government_transit_collector/features/authentication/presentation/login_page.dart';

void main() {
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'forgot success returns to sign in and prevents duplicate pending sends',
    (tester) async {
      final repository = PageAuth();
      final pending = Completer<void>();
      repository.pendingEmail = pending.future;
      await tester.pumpWidget(
        MaterialApp(home: LoginPage(repository: repository)),
      );
      await tap(tester, find.text('Forgot Password?'));
      await tester.enterText(find.byType(TextFormField), ' user@example.com ');
      await tester.tap(find.text('Send Reset Link'));
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();
      expect(repository.resetEmailCalls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordPage), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        find.text(
          'If an account exists for this email, a password reset link has been sent.',
        ),
        findsOneWidget,
      );
      expect(find.text('Resend Reset Email'), findsNothing);
    },
  );

  testWidgets(
    'Google email-password reset returns to Account Security after sending',
    (tester) async {
      final repository = PageAuth()
        ..googleIdentity = true
        ..sessionMethod = 'oauth';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChangePasswordPage(repository: repository),
                  ),
                ),
                child: const Text('Account Security'),
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.text('Account Security'));
      expect(find.text('You signed in with Google.'), findsOneWidget);
      expect(
        find.text('Your Google password will not be changed.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Send Password Reset Email'));
      expect(repository.sentEmail, 'rider@example.test');
      expect(repository.resetEmailCalls, 1);
      expect(find.byType(ForgotPasswordPage), findsNothing);
      expect(find.text('Account Security'), findsOneWidget);
      expect(repository.changeCalls, 0);
    },
  );

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
      for (var index = 0; index < 3; index++) {
        final editable = find.descendant(
          of: fields.at(index),
          matching: find.byType(EditableText),
        );
        expect(tester.widget<EditableText>(editable).obscureText, isTrue);
        final eye = find.descendant(
          of: fields.at(index),
          matching: find.byType(IconButton),
        );
        await tap(tester, eye);
        expect(tester.widget<EditableText>(editable).obscureText, isFalse);
        await tap(tester, eye);
        expect(tester.widget<EditableText>(editable).obscureText, isTrue);
      }
      await tap(tester, button);
      expect(find.text('Current password is required.'), findsOneWidget);
      expect(find.text('Password is required.'), findsOneWidget);
      await tester.enterText(fields.at(0), 'Password123!');
      await tester.enterText(fields.at(1), 'short');
      await tap(tester, button);
      expect(
        find.text(
          'Password must be at least 8 characters and include uppercase, lowercase, number, and special character.',
        ),
        findsOneWidget,
      );
      await tester.enterText(fields.at(1), 'Password123!');
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
      await tester.enterText(fields.at(1), 'New-password123!');
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
      'New-password123!',
      'New-password123!',
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
