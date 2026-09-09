import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'auth_test_support.dart';

void main() {
  test(
    'dual identities use session AMR, never original provider metadata',
    () async {
      final backend = AuthBackend()
        ..emailIdentity = true
        ..sessionMethod = 'oauth';
      final auth = AuthRepository(client: backend.client);
      addTearDown(auth.dispose);
      addTearDown(backend.client.dispose);
      await backend.signIn();
      expect(auth.hasGoogleIdentity, isTrue);
      expect(auth.supportsEmailPassword, isTrue);
      expect(auth.passwordAuthenticatedSession, isFalse);
      await expectLater(
        auth.changePassword(
          currentPassword: 'not-a-google-password',
          newPassword: 'new-password123',
        ),
        throwsA(isA<AuthFlowException>()),
      );
      expect(backend.requests, isEmpty);
      backend.sessionMethod = 'password';
      await backend.signIn();
      expect(auth.passwordAuthenticatedSession, isTrue);
      expect(auth.currentSession!.user.id, 'authenticated-owner');
    },
  );
  late AuthBackend backend;
  late AuthRepository repository;
  setUp(() {
    backend = AuthBackend();
    repository = AuthRepository(
      client: backend.client,
      redirectUrl: 'test-auth://callback',
    );
  });
  tearDown(() async {
    repository.dispose();
    await backend.client.dispose();
  });
  Matcher message(String text) => throwsA(
    isA<AuthFlowException>().having((e) => e.message, 'message', text),
  );

  for (final code in ['user_already_exists', 'email_exists', 'obfuscated']) {
    test(
      'signup reports existing account from $code without profile writes',
      () async {
        backend.signupErrorCode = code == 'obfuscated' ? null : code;
        backend.obfuscatedSignup = code == 'obfuscated';
        await expectLater(
          repository.register(
            fullName: 'Rider',
            email: ' user@example.com ',
            password: 'password123',
          ),
          message(AuthRepository.existingAccountMessage),
        );
        expect(backend.requests.map((r) => r.url.path), ['/auth/v1/signup']);
      },
    );
  }
  test('signup rejects password equal to email before request', () async {
    await expectLater(
      repository.register(
        fullName: 'Rider',
        email: ' USER@example.com ',
        password: 'user@example.com',
      ),
      message('Password cannot be the same as your email address.'),
    );
    expect(backend.requests, isEmpty);
  });
  for (final code in [null, 'user_not_found']) {
    test(
      'valid recovery request returns identically for account existence $code',
      () async {
        backend.recoveryErrorCode = code;
        await repository.sendPasswordReset('user@example.com');
        expect(backend.requests.single.url.path, '/auth/v1/recover');
        expect(repository.currentSession, isNull);
      },
    );
  }
  test('email rate limit is sanitized', () async {
    backend.recoveryErrorCode = 'over_email_send_rate_limit';
    await expectLater(
      repository.sendPasswordReset('user@example.com'),
      message(
        'Too many requests. Please wait a few minutes before trying again.',
      ),
    );
  });
  test('reset rejects authenticated email equality without update', () async {
    await repository.sendPasswordReset('owner@example.test');
    await repository.handleAuthCallback(
      Uri.parse('test-auth://callback?code=recovery'),
    );
    backend.requests.clear();
    await expectLater(
      repository.resetPassword(' OWNER@example.test '),
      message('Password cannot be the same as your email address.'),
    );
    expect(backend.requests, isEmpty);
  });
  for (final code in ['same_password', 'weak_password']) {
    test('reset maps secure server reuse code only: $code', () async {
      await repository.sendPasswordReset('owner@example.test');
      await repository.handleAuthCallback(
        Uri.parse('test-auth://callback?code=recovery'),
      );
      backend.updateErrorCode = code;
      await expectLater(
        repository.resetPassword('new-password123'),
        message(
          code == 'same_password'
              ? 'Your new password cannot be the same as your previous password.'
              : 'Unable to update your password. Please try again.',
        ),
      );
      expect(repository.recoveryRequired, true);
      expect(repository.hasValidRecoverySession, true);
    });
  }
  test(
    'Google-only account never attempts password verification or update',
    () async {
      await backend.signIn();
      expect(repository.hasGoogleIdentity, true);
      expect(repository.supportsEmailPassword, false);
      await expectLater(
        repository.changePassword(
          currentPassword: 'not-a-google-password',
          newPassword: 'new-password123',
        ),
        message('This account does not support app password changes.'),
      );
      expect(backend.requests, isEmpty);
    },
  );
  test(
    'wrong app password is verified by Supabase, then no update happens',
    () async {
      backend.google = false;
      await backend.signIn();
      backend.loginErrorCode = 'invalid_credentials';
      await expectLater(
        repository.changePassword(
          currentPassword: 'wrong-password',
          newPassword: 'new-password123',
        ),
        message('Current password is incorrect.'),
      );
      expect(backend.requests.single.url.path, '/auth/v1/token');
      expect(repository.currentSession!.user.id, 'authenticated-owner');
    },
  );
  for (final both in [false, true]) {
    test(
      'change password preserves admin and ${both ? 'both identities' : 'email login'}',
      () async {
        backend.google = both;
        backend.emailIdentity = true;
        backend.role = 'admin';
        await backend.signIn();
        await repository.changePassword(
          currentPassword: 'old-password123',
          newPassword: 'new-password123',
        );
        expect(backend.requests.map((r) => r.url.path), [
          '/auth/v1/token',
          '/auth/v1/user',
        ]);
        expect(
          jsonDecode(backend.requests.first.body)['email'],
          'owner@example.test',
        );
        expect(jsonDecode(backend.requests.last.body), {
          'password': 'new-password123',
          'current_password': 'old-password123',
        });
        expect(repository.currentSession!.user.id, 'authenticated-owner');
        expect(repository.supportsEmailPassword, true);
        expect(repository.hasGoogleIdentity, both);
        expect((await repository.loadCurrentProfile())!.role, 'admin');
        expect(
          backend.requests.where(
            (r) => r.url.path.startsWith('/rest/') && r.method != 'GET',
          ),
          isEmpty,
        );
        expect(backend.storage.values, isEmpty);
      },
    );
  }
  test(
    'change rejects identical current and new password before request',
    () async {
      backend.google = false;
      await backend.signIn();
      await expectLater(
        repository.changePassword(
          currentPassword: 'password123',
          newPassword: 'password123',
        ),
        message('New password must be different from your current password.'),
      );
      await expectLater(
        repository.changePassword(
          currentPassword: 'password123',
          newPassword: 'owner@example.test',
        ),
        message('Password cannot be the same as your email address.'),
      );
      expect(backend.requests, isEmpty);
    },
  );
}
