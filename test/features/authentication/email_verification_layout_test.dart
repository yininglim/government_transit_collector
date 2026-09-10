import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/core/theme/app_theme.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/authentication/presentation/register_page.dart';
import 'auth_pages_test.dart' show PageAuth;

const email = 'passenger.with.a.long.email.address@example.test';

void main() {
  for (final unverified in [false, true]) {
    for (final size in [const Size(320, 640), const Size(390, 844), const Size(844, 390)]) {
      testWidgets('verification layout for unverified=$unverified at $size', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final repository = VerificationAuth();
        await showVerification(tester, repository, unverified: unverified);
        expect(find.text(unverified ? 'Email Not Verified' : 'Verify Your Email'), findsOneWidget);
        expect(find.byType(BackButton), findsOneWidget);
        expect(find.byKey(const Key('app-header')), findsNothing);
        expect(find.byKey(const Key('app-bottom-navigation')), findsNothing);
        final header = tester.getRect(find.byType(AppBar));
        final titleText = find.text(unverified ? 'Email Not Verified' : 'Verify Your Email');
        expect(tester.renderObject<RenderParagraph>(titleText).didExceedMaxLines, isFalse);
        expect(header.contains(tester.getBottomRight(titleText) - const Offset(1, 1)), isTrue);
        final content = tester.getRect(find.byKey(const Key('email-verification-content')));
        expect(content.top - header.bottom, inInclusiveRange(16, 40));
        expect(content.width, lessThanOrEqualTo(440));
        expect(content.left, greaterThanOrEqualTo(24));
        final icon = find.byKey(const Key('email-verification-icon'));
        expect(tester.widget<Icon>(icon).size, 48);
        expect(tester.widget<Icon>(icon).color, AppTheme.contentBlue);
        final emailText = find.text(email);
        expect(emailText, findsOneWidget);
        expect(tester.renderObject<RenderParagraph>(emailText).didExceedMaxLines, isFalse);
        final emailCard = tester.getRect(find.byKey(const Key('verification-email-card')));
        expect(emailCard.contains(tester.getTopLeft(emailText)), isTrue);
        expect(emailCard.contains(tester.getBottomRight(emailText) - const Offset(1, 1)), isTrue);
        final resend = find.widgetWithText(FilledButton, 'Resend Verification Email');
        expect(tester.widget<FilledButton>(resend).onPressed, unverified ? isNotNull : isNull);
        await tester.ensureVisible(find.byKey(const Key('verification-spam-info')));
        await tester.pump();
        expect(find.text('Check your Spam/Junk folder if you cannot find the email.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(repository.verificationEmails, 0);
        await tester.ensureVisible(find.text('Back to Sign In'));
        await tester.tap(find.text('Back to Sign In'));
        await tester.pumpAndSettle();
        expect(find.text('Sign-in host'), findsOneWidget);
      });
    }
  }

  testWidgets('verification signup countdown and resend email source are unchanged', (tester) async {
    final repository = VerificationAuth();
    await showVerification(tester, repository);
    final resend = find.widgetWithText(FilledButton, 'Resend Verification Email');
    expect(find.text('Resend available in 60 seconds.'), findsOneWidget);
    expect(tester.widget<FilledButton>(resend).onPressed, isNull);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Resend available in 50 seconds.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 50));
    expect(tester.widget<FilledButton>(resend).onPressed, isNotNull);
    await tester.ensureVisible(resend);
    await tester.tap(resend);
    await tester.pump();
    expect(repository.verificationEmails, 1);
    expect(repository.sentVerificationEmail, email);
    expect(find.text('Verification email sent. Please check your inbox.'), findsOneWidget);
    expect(tester.widget<FilledButton>(resend).onPressed, isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Sign-in host'), findsOneWidget);
  });

  testWidgets('verification rate limit keeps cooldown and permits retry afterwards', (tester) async {
    final repository = VerificationAuth()..rateLimited = true;
    await showVerification(tester, repository, unverified: true);
    final resend = find.widgetWithText(FilledButton, 'Resend Verification Email');
    await tester.ensureVisible(resend);
    await tester.tap(resend);
    await tester.pump();
    expect(find.text('Please wait before requesting another verification email.'), findsOneWidget);
    expect(tester.widget<FilledButton>(resend).onPressed, isNull);
    await tester.tap(resend);
    await tester.pump();
    expect(repository.verificationEmails, 1);
    await tester.pump(const Duration(seconds: 60));
    repository.rateLimited = false;
    expect(tester.widget<FilledButton>(resend).onPressed, isNotNull);
    await tester.tap(resend);
    await tester.pump();
    expect(repository.verificationEmails, 2);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets('verification stays disabled while resend is pending after cooldown', (tester) async {
    final gate = Completer<void>();
    final repository = VerificationAuth()..pending = gate.future;
    await showVerification(tester, repository, unverified: true);
    final resend = find.widgetWithText(FilledButton, 'Resend Verification Email');
    await tester.ensureVisible(resend);
    await tester.tap(resend);
    await tester.pump(const Duration(seconds: 61));
    expect(tester.widget<FilledButton>(resend).onPressed, isNull);
    gate.complete();
    await tester.pump();
    expect(tester.widget<FilledButton>(resend).onPressed, isNotNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
}

Future<void> showVerification(WidgetTester tester, VerificationAuth repository, {bool unverified = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EmailVerificationPage(repository: repository, email: email, unverifiedSignIn: unverified),
      )),
      child: const Text('Sign-in host'),
    ))),
  ));
  await tester.tap(find.text('Sign-in host'));
  await tester.pumpAndSettle();
}

class VerificationAuth extends PageAuth {
  String? sentVerificationEmail;
  bool rateLimited = false;
  Future<void>? pending;

  @override
  Future<void> resendVerificationEmail(String email) async {
    verificationEmails++;
    sentVerificationEmail = email;
    await pending;
    if (rateLimited) {
      throw const AuthFlowException('Please wait before requesting another verification email.');
    }
  }
}
