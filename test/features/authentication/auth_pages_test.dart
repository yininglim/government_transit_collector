import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/authentication/presentation/auth_gate.dart';
import 'package:government_transit_collector/features/authentication/presentation/login_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/forgot_password_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/reset_password_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/register_page.dart';
import 'auth_test_support.dart';

class PageAuth extends AuthRepository {
  PageAuth()
    : super(
        client: SupabaseClient(
          'https://example.test',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  int googleCalls = 0;
  int loginCalls = 0;
  int verificationEmails = 0;
  bool unverified = false;
  @override
  Future<void> resendVerificationEmail(String email) async {
    verificationEmails++;
  }

  int registrationCalls = 0;
  String? sentEmail;
  String? updatedPassword;
  String? googleError;
  int resetEmailCalls = 0;
  Future<void>? pendingEmail;
  String? changeError;
  int changeCalls = 0;
  bool emailPassword = true;
  bool googleIdentity = false;
  String sessionMethod = 'password';
  @override
  String? get currentAuthenticationMethod => sessionMethod;
  @override
  String? get currentEmail => 'rider@example.test';
  @override
  bool get supportsEmailPassword => emailPassword;
  @override
  bool get hasGoogleIdentity => googleIdentity;
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changeCalls++;
    if (changeError != null) throw AuthFlowException(changeError!);
  }

  bool recovering = true;
  bool valid = true;
  @override
  Future<void> signInWithGoogle() async {
    googleCalls++;
    if (googleError != null) throw AuthFlowException(googleError!);
  }

  @override
  Future<void> cancelGoogleSignIn() async {}
  @override
  Future<void> login({required String email, required String password}) async {
    loginCalls++;
    if (unverified) throw const EmailNotVerifiedException();
  }

  @override
  Future<RegistrationResult> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    registrationCalls++;
    return const RegistrationResult(requiresEmailConfirmation: true);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    resetEmailCalls++;
    sentEmail = email;
    await pendingEmail;
  }

  @override
  bool get recoveryRequired => recovering;
  @override
  bool get hasValidRecoverySession => valid;
  @override
  Future<void> resetPassword(String password) async {
    updatedPassword = password;
    recovering = false;
    notifyListeners();
  }

  @override
  Future<void> cancelRecovery() async {
    recovering = false;
    notifyListeners();
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    Widget page, {
    bool keyboard = false,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard ? 280 : 0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'login order, Google abstraction, signup and phone keyboard layout',
    (tester) async {
      final repository = PageAuth();
      await show(tester, LoginPage(repository: repository), keyboard: true);
      expect(find.text('Welcome Back'), findsOneWidget);
      final ordered = [
        'Sign In',
        'OR',
        'Continue with Google',
        'Forgot Password?',
        "Don't have an account? Sign Up",
      ];
      for (var i = 1; i < ordered.length; i++) {
        expect(
          tester.getTopLeft(find.text(ordered[i])).dy,
          greaterThan(tester.getTopLeft(find.text(ordered[i - 1])).dy),
        );
      }
      await tap(tester, find.text('Continue with Google'));
      expect(repository.googleCalls, 1);
      expect(repository.loginCalls, 0);
      await tap(tester, find.text('Cancel Google sign-in'));
      expect(find.text('Google sign-in was cancelled.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tap(tester, find.text("Don't have an account? Sign Up"));
      expect(find.byType(RegisterPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final message in [
    'Google sign-in was cancelled.',
    'Unable to sign in with Google. Please try again.',
  ]) {
    testWidgets('Google displays $message', (tester) async {
      final repository = PageAuth()..googleError = message;
      await show(tester, LoginPage(repository: repository));
      await tap(tester, find.text('Continue with Google'));
      expect(find.text(message), findsOneWidget);
      expect(find.byType(LoginPage), findsOneWidget);
    });
  }

  testWidgets('email password login still calls existing abstraction', (
    tester,
  ) async {
    final repository = PageAuth();
    await show(tester, LoginPage(repository: repository));
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'rider@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(repository.loginCalls, 1);
    expect(repository.googleCalls, 0);
  });

  testWidgets('email verification screen handles unverified sign in', (
    tester,
  ) async {
    final repository = PageAuth()..unverified = true;
    await show(tester, LoginPage(repository: repository));
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'rider@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
    await tap(tester, find.text('Sign In'));
    expect(find.text('Email Not Verified'), findsOneWidget);
    await tap(tester, find.text('Resend Verification Email'));
    expect(repository.verificationEmails, 1);
    await tap(tester, find.text('Back to Sign In'));
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('signup remains usable and returns email confirmation message', (
    tester,
  ) async {
    final repository = PageAuth();
    await show(tester, LoginPage(repository: repository));
    await tap(tester, find.text("Don't have an account? Sign Up"));
    final fields = find.byType(TextFormField);
    for (final entry in [
      'Rider',
      'rider@example.test',
      'Password123!',
      'Password123!',
    ].asMap().entries) {
      await tester.enterText(fields.at(entry.key), entry.value);
    }
    await tap(tester, find.text('Register'));
    expect(repository.registrationCalls, 1);
    expect(find.text('Verify Your Email'), findsOneWidget);
    expect(find.text('rider@example.test'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Resend Verification Email'),
          )
          .onPressed,
      isNull,
    );
    await tester.pump(const Duration(seconds: 61));
    await tap(tester, find.text('Resend Verification Email'));
    expect(repository.verificationEmails, 1);
    await tap(tester, find.text('Back to Sign In'));
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets(
    'forgot validates email and displays neutral success without updating password',
    (tester) async {
      final repository = PageAuth();
      await show(tester, LoginPage(repository: repository), keyboard: true);
      await tap(tester, find.text('Forgot Password?'));
      await tap(tester, find.text('Send Reset Link'));
      expect(find.text('Email is required.'), findsOneWidget);
      expect(repository.sentEmail, isNull);
      await tester.enterText(find.byType(TextFormField), 'invalid');
      await tap(tester, find.text('Send Reset Link'));
      expect(find.text('Please enter a valid email address.'), findsOneWidget);
      expect(repository.sentEmail, isNull);
      await tester.enterText(find.byType(TextFormField), 'rider@example.test');
      await tap(tester, find.text('Send Reset Link'));
      expect(repository.sentEmail, 'rider@example.test');
      expect(
        find.text(
          'If an account exists for this email, a password reset link has been sent.',
        ),
        findsOneWidget,
      );
      expect(repository.updatedPassword, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Forgot Password opens dedicated page and Back returns to login',
    (tester) async {
      final repository = PageAuth();
      await show(tester, LoginPage(repository: repository));
      await tap(tester, find.text('Forgot Password?'));
      expect(find.byType(ForgotPasswordPage), findsOneWidget);
      await tap(tester, find.text('Back to Sign In'));
      expect(find.byType(LoginPage), findsOneWidget);
    },
  );

  testWidgets('reset validates required, length, matching and handles keyboard', (
    tester,
  ) async {
    final repository = PageAuth();
    await show(
      tester,
      ResetPasswordPage(repository: repository),
      keyboard: true,
    );
    final button = find.widgetWithText(FilledButton, 'Reset Password');
    await tap(tester, button);
    expect(find.text('Password is required.'), findsOneWidget);
    expect(find.text('Confirm password is required.'), findsOneWidget);
    final fields = find.byType(TextFormField);
    for (var index = 0; index < 2; index++) {
      final editable = find.descendant(
        of: fields.at(index),
        matching: find.byType(EditableText),
      );
      final eye = find.descendant(
        of: fields.at(index),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<EditableText>(editable).obscureText, isTrue);
      await tap(tester, eye);
      expect(tester.widget<EditableText>(editable).obscureText, isFalse);
      await tap(tester, eye);
      expect(tester.widget<EditableText>(editable).obscureText, isTrue);
    }
    await tester.enterText(fields.at(0), 'short');
    await tap(tester, button);
    expect(
      find.text(
        'Password must be at least 8 characters and include uppercase, lowercase, number, and special character.',
      ),
      findsOneWidget,
    );
    await tester.enterText(fields.at(0), 'Password123!');
    await tester.enterText(fields.at(1), 'different');
    await tap(tester, button);
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(repository.updatedPassword, isNull);
    await tester.enterText(fields.at(1), 'Password123!');
    await tap(tester, button);
    expect(repository.updatedPassword, 'Password123!');
    expect(
      find.text(
        'Password updated successfully. Please sign in with your new password.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recovery gate returns to login after reset, without loading home',
    (tester) async {
      final repository = PageAuth();
      await show(tester, AuthGate(repository: repository));
      expect(find.byType(ResetPasswordPage), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'Password123!');
      await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
      await tap(tester, find.widgetWithText(FilledButton, 'Reset Password'));
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        find.text(
          'Password updated successfully. Please sign in with your new password.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'invalid recovery cannot update password and allows safe cancellation',
    (tester) async {
      final repository = PageAuth()..valid = false;
      await show(tester, AuthGate(repository: repository));
      expect(find.text(AuthRepository.invalidRecoveryMessage), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await tap(tester, find.text('Back to Sign In'));
      expect(find.byType(LoginPage), findsOneWidget);
      expect(repository.updatedPassword, isNull);
    },
  );

  testWidgets(
    'real Supabase recovery callback replaces pushed page and blocks profile routing',
    (tester) async {
      final backend = (await tester.runAsync(() async {
        final value = AuthBackend()..role = 'admin';
        value.client;
        return value;
      }))!;
      final repository = AuthRepository(
        client: backend.client,
        redirectUrl: 'test-auth://callback',
      );
      addTearDown(() async {
        repository.dispose();
        await backend.client.dispose();
      });
      await show(tester, AuthGate(repository: repository));
      await tap(tester, find.text('Forgot Password?'));
      await tester.runAsync(() async {
        await repository.sendPasswordReset('owner@example.test');
        await repository.handleAuthCallback(
          Uri.parse('test-auth://callback?code=recovery'),
        );
      });
      await tester.pumpAndSettle();
      expect(find.byType(ResetPasswordPage), findsOneWidget);
      expect(find.byType(ForgotPasswordPage), findsNothing);
      expect(
        backend.requests.where((r) => r.url.path.contains('/rest/')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
