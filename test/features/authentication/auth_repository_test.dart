import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'auth_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthBackend backend;
  late AuthRepository repository;
  // Deliberate test fixture, not production redirect configuration.
  const redirect = 'test-auth://callback';
  setUp(() {
    backend = AuthBackend();
    repository = AuthRepository(
      client: backend.client,
      emailVerificationRedirectUrl: 'https://example.test/verified/',
      redirectUrl: redirect,
    );
  });
  tearDown(() async {
    repository.dispose();
    await backend.client.dispose();
  });

  test(
    'email verification signup and resend use HTTPS without profile writes',
    () async {
      backend.google = false;
      final result = await repository.register(
        fullName: 'Rider',
        email: ' rider@example.test ',
        password: 'Password123!',
      );
      expect(result.requiresEmailConfirmation, isTrue);
      expect(repository.currentSession, isNull);
      await repository.resendVerificationEmail(' rider@example.test ');
      expect(backend.requests.map((r) => r.url.path), [
        '/auth/v1/signup',
        '/auth/v1/resend',
      ]);
      for (final request in backend.requests) {
        expect(
          request.url.queryParameters['redirect_to'],
          'https://example.test/verified/',
        );
        expect(jsonDecode(request.body)['email'], 'rider@example.test');
      }
      expect(jsonDecode(backend.requests.last.body)['type'], 'signup');
    },
  );

  test(
    'email verification rejects unconfirmed login and allows verified or Google',
    () async {
      backend.google = false;
      backend.loginErrorCode = 'email_not_confirmed';
      await expectLater(
        repository.login(email: 'rider@example.test', password: 'Password123!'),
        throwsA(isA<EmailNotVerifiedException>()),
      );
      expect(repository.currentSession, isNull);
      backend.loginErrorCode = null;
      backend.emailVerified = false;
      await expectLater(
        repository.login(email: 'rider@example.test', password: 'Password123!'),
        throwsA(isA<EmailNotVerifiedException>()),
      );
      expect(repository.currentSession, isNull);
      backend.emailVerified = true;
      await repository.login(
        email: 'rider@example.test',
        password: 'Password123!',
      );
      expect(repository.currentSession, isNotNull);
      await repository.logout();
      backend.google = true;
      backend.emailVerified = false;
      await backend.signIn();
      expect(repository.currentSession!.user.id, 'authenticated-owner');
    },
  );

  test(
    'signup respects returned confirmation state without inferring configuration',
    () async {
      backend.google = false;
      for (final state in [(true, false), (false, false), (false, true)]) {
        backend.confirmationRequired = state.$1;
        backend.emailVerified = state.$2;
        final result = await repository.register(
          fullName: 'Rider',
          email: 'rider@example.test',
          password: 'Password123!',
        );
        expect(result.requiresEmailConfirmation, state.$1 || !state.$2);
        expect(repository.currentSession != null, !state.$1 && state.$2);
        if (!state.$2) expect(backend.client.auth.currentSession, isNull);
      }
    },
  );

  test(
    'email verification uses the approved HTTPS default without environment configuration',
    () async {
      final auth = AuthRepository(client: backend.client);
      addTearDown(auth.dispose);
      await auth.register(
        fullName: 'Rider',
        email: 'rider@example.test',
        password: 'Strong1!',
      );
      await auth.resendVerificationEmail('rider@example.test');
      for (final request in backend.requests) {
        expect(
          request.url.queryParameters['redirect_to'],
          'https://looyien.github.io/government-transit-collector-site/',
        );
      }
    },
  );

  for (final role in ['passenger', 'admin']) {
    test(
      'Google reuses authenticated ID and preserves existing $role',
      () async {
        backend.role = role;
        await backend.signIn();
        final profile = await repository.loadCurrentProfile();
        expect(profile!.userId, 'authenticated-owner');
        expect(profile.email, 'owner@example.test');
        expect(profile.fullName, 'Existing Name');
        expect(profile.role, role);
        expect(backend.requests, hasLength(1));
        expect(
          backend.requests.single.url.queryParameters['user_id'],
          'eq.authenticated-owner',
        );
        expect(backend.requests.single.method, 'GET');
      },
    );
  }

  test(
    'missing Google profile uses restricted RPC and re-reads by ID',
    () async {
      backend.missingProfile = true;
      await backend.signIn();
      final profile = await repository.loadCurrentProfile();
      expect(profile!.role, 'passenger');
      expect(profile.userId, 'authenticated-owner');
      final rpc = backend.requests
          .where((r) => r.url.path.contains('/rpc/'))
          .single;
      expect(
        jsonDecode(rpc.body),
        isNull,
      ); // No caller-selected identity or role.
      await repository.loadCurrentProfile();
      expect(
        backend.requests.where((r) => r.url.path.contains('/rpc/')),
        hasLength(1),
      );
    },
  );

  test('email profile behavior remains unchanged', () async {
    backend.google = false;
    backend.missingProfile = true;
    await backend.signIn();
    expect(await repository.loadCurrentProfile(), isNull);
    expect(backend.requests, hasLength(1));
  });

  test('profile errors never expose database details', () async {
    await backend.signIn();
    backend.failProfile = true;
    await expectLater(
      repository.loadCurrentProfile(),
      throwsA(
        isA<AuthFlowException>().having(
          (e) => e.message,
          'message',
          'Unable to load your profile. Please try again.',
        ),
      ),
    );
  });

  test(
    'email login and signup retain API, name metadata and confirmation logic',
    () async {
      await repository.login(
        email: ' owner@example.test ',
        password: 'Password123!',
      );
      expect(
        backend.requests.last.url.queryParameters['grant_type'],
        'password',
      );
      expect(
        jsonDecode(backend.requests.last.body)['email'],
        'owner@example.test',
      );
      final result = await repository.register(
        fullName: ' Rider ',
        email: ' new@example.test ',
        password: 'Password123!',
      );
      expect(result.requiresEmailConfirmation, true);
      expect(jsonDecode(backend.requests.last.body)['data'], {
        'full_name': 'Rider',
      });
      await repository.logout();
      expect(repository.currentSession, isNull);
    },
  );

  test(
    'forgot password uses HTTPS recovery independently of the app callback',
    () async {
      await repository.sendPasswordReset(' owner@example.test ');
      expect(backend.requests, hasLength(1));
      expect(backend.requests.single.url.path, '/auth/v1/recover');
      expect(
        backend.requests.single.url.queryParameters['redirect_to'],
        AuthRepository.passwordRecoveryRedirectUrl,
      );
      expect(
        jsonDecode(backend.requests.single.body)['email'],
        'owner@example.test',
      );
      expect(
        jsonDecode(backend.requests.single.body).containsKey('password'),
        false,
      );
      expect(repository.currentSession, isNull);
    },
  );

  test(
    'reset email cooldown survives form navigation and preserves PKCE request',
    () async {
      await repository.sendPasswordReset('owner@example.test');
      await expectLater(
        repository.sendPasswordReset('owner@example.test'),
        throwsA(isA<AuthFlowException>()),
      );
      expect(
        backend.requests.where((r) => r.url.path == '/auth/v1/recover'),
        hasLength(1),
      );
      expect(
        backend.requests.single.url.queryParameters['redirect_to'],
        AuthRepository.passwordRecoveryRedirectUrl,
      );
      expect(
        jsonDecode(backend.requests.single.body)['code_challenge'],
        isNotEmpty,
      );
    },
  );

  test('recovery endpoint errors do not reveal account existence', () async {
    backend.failRecovery = true;
    await expectLater(
      repository.sendPasswordReset('owner@example.test'),
      throwsA(
        isA<AuthFlowException>().having(
          (e) => e.message,
          'message',
          'Unable to send a reset link. Please try again.',
        ),
      ),
    );
  });

  test(
    'PKCE recovery routes separately, updates password then signs out',
    () async {
      backend.emailIdentity = true;
      await repository.sendPasswordReset('owner@example.test');
      await repository.handleAuthCallback(
        Uri.parse('$redirect?code=test-code'),
      );
      expect(repository.recoveryRequired, true);
      expect(repository.hasValidRecoverySession, true);
      backend.requests.clear();
      await repository.resetPassword('New-password123!');
      expect(backend.requests.first.method, 'PUT');
      expect(backend.requests.first.url.path, '/auth/v1/user');
      expect(
        jsonDecode(backend.requests.first.body)['password'],
        'New-password123!',
      );
      expect(backend.requests.last.url.path, '/auth/v1/logout');
      expect(repository.currentSession, isNull);
      expect(repository.recoveryRequired, false);
      expect(
        backend.storage.values.values,
        isNot(contains('New-password123!')),
      );
    },
  );

  test(
    'normal authenticated session is insufficient for password reset',
    () async {
      await backend.signIn();
      await expectLater(
        repository.resetPassword('New-password123!'),
        throwsA(isA<AuthFlowException>()),
      );
      expect(backend.requests, isEmpty);
    },
  );

  test('expired recovery is isolated and cannot update password', () async {
    await repository.sendPasswordReset('owner@example.test');
    backend.failExchange = true;
    await repository.handleAuthCallback(Uri.parse('$redirect?code=expired'));
    expect(repository.recoveryRequired, true);
    expect(repository.hasValidRecoverySession, false);
    expect(repository.callbackMessage, AuthRepository.invalidRecoveryMessage);
    await expectLater(
      repository.resetPassword('New-password123!'),
      throwsA(isA<AuthFlowException>()),
    );
    await repository.cancelRecovery();
    expect(repository.recoveryRequired, false);
  });

  test('server rejects expired recovery session with friendly error', () async {
    backend.emailIdentity = true;
    await repository.sendPasswordReset('owner@example.test');
    await repository.handleAuthCallback(Uri.parse('$redirect?code=test-code'));
    backend.updateStatus = 401;
    await expectLater(
      repository.resetPassword('New-password123!'),
      throwsA(
        isA<AuthFlowException>().having(
          (e) => e.message,
          'message',
          AuthRepository.invalidRecoveryMessage,
        ),
      ),
    );
    expect(repository.recoveryRequired, true);
    expect(repository.hasValidRecoverySession, false);
  });

  test(
    'Google PKCE callback is normal auth and duplicate delivery is ignored',
    () async {
      await backend.client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: redirect,
      );
      final callback = Uri.parse('$redirect?code=google-code');
      await repository.handleAuthCallback(callback);
      expect(repository.currentSession!.user.id, 'authenticated-owner');
      expect(repository.recoveryRequired, false);
      await repository.handleAuthCallback(callback);
      expect(
        backend.requests.where((r) => r.url.path.endsWith('/token')),
        hasLength(1),
      );
      expect(repository.currentSession, isNotNull);
    },
  );

  test('Google cancellation and failed callbacks are sanitized', () async {
    await repository.handleAuthCallback(
      Uri.parse('$redirect?error=access_denied&error_description=secret'),
    );
    expect(repository.callbackMessage, 'Google sign-in was cancelled.');
    await repository.handleAuthCallback(
      Uri.parse('$redirect?code=missing-verifier'),
    );
    expect(
      repository.callbackMessage,
      'Unable to sign in with Google. Please try again.',
    );
  });

  test(
    'wrong endpoints and implicit token callbacks cannot establish a session',
    () async {
      expect(
        repository.acceptsCallback(Uri.parse('other://callback?code=test')),
        false,
      );
      expect(
        repository.acceptsCallback(Uri.parse('$redirect/extra?code=test')),
        false,
      );
      await repository.handleAuthCallback(
        Uri.parse('other://callback?code=test'),
      );
      await repository.handleAuthCallback(
        Uri.parse('$redirect#access_token=untrusted&type=recovery'),
      );
      expect(repository.currentSession, isNull);
      expect(backend.requests, isEmpty);
    },
  );

  test(
    'Google launcher receives Supabase provider, PKCE challenge and configured redirect',
    () async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Uri? launched;
      messenger.setMockMethodCallHandler(channel, (call) async {
        launched = Uri.parse((call.arguments as Map)['url'] as String);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await repository.signInWithGoogle();
      expect(launched!.host, 'auth.example.test');
      expect(launched!.path, '/auth/v1/authorize');
      expect(launched!.queryParameters['provider'], 'google');
      expect(launched!.queryParameters['redirect_to'], redirect);
      expect(launched!.queryParameters['code_challenge'], isNotEmpty);
      await repository.cancelGoogleSignIn();
      expect(backend.storage.values, isEmpty);
    },
  );

  for (final throwsPlatformError in [false, true]) {
    test(
      'Google launcher ${throwsPlatformError ? 'failure' : 'cancellation'} is sanitized',
      () async {
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (_) async {
          if (throwsPlatformError) {
            throw PlatformException(code: 'private-details');
          }
          return false;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await expectLater(
          repository.signInWithGoogle(),
          throwsA(
            isA<AuthFlowException>().having(
              (e) => e.message,
              'message',
              throwsPlatformError
                  ? 'Unable to sign in with Google. Please try again.'
                  : 'Google sign-in was cancelled.',
            ),
          ),
        );
      },
    );
  }

  test(
    'missing app redirect blocks Google but not the dedicated web recovery flow',
    () async {
      final unconfigured = AuthRepository(
        client: backend.client,
        redirectUrl: '',
      );
      addTearDown(unconfigured.dispose);
      await expectLater(
        unconfigured.signInWithGoogle(),
        throwsA(isA<AuthFlowException>()),
      );
      expect(backend.requests, isEmpty);
      await unconfigured.sendPasswordReset('owner@example.test');
      expect(
        backend.requests.single.url.queryParameters['redirect_to'],
        AuthRepository.passwordRecoveryRedirectUrl,
      );
    },
  );

  test(
    'cold callback is processed before UI and interrupted recovery stays isolated',
    () async {
      SharedPreferences.setMockInitialValues({});
      const links = MethodChannel('com.llfbandit.app_links/messages');
      const events = MethodChannel('com.llfbandit.app_links/events');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? initial;
      messenger.setMockMethodCallHandler(links, (_) async => initial);
      messenger.setMockMethodCallHandler(events, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(links, null);
        messenger.setMockMethodCallHandler(events, null);
      });
      await repository.initializeDeepLinks();
      await repository.sendPasswordReset('owner@example.test');
      initial = '$redirect?code=cold-recovery';
      final cold = AuthRepository(
        client: backend.client,
        redirectUrl: redirect,
      );
      await cold.initializeDeepLinks();
      expect(cold.recoveryRequired, true);
      expect(cold.hasValidRecoverySession, true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auth_recovery_in_progress'), true);
      initial = null;
      final restarted = AuthRepository(
        client: backend.client,
        redirectUrl: redirect,
      );
      await restarted.initializeDeepLinks();
      expect(restarted.currentSession, isNotNull);
      expect(restarted.recoveryRequired, true);
      expect(restarted.hasValidRecoverySession, false);
      await restarted.cancelRecovery();
      expect(prefs.getBool('auth_recovery_in_progress'), false);
      expect(restarted.currentSession, isNull);
      cold.dispose();
      restarted.dispose();
    },
  );
}
