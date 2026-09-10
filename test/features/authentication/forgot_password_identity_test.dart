import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/authentication/presentation/forgot_password_page.dart';
import 'package:government_transit_collector/features/authentication/presentation/reset_password_page.dart';
import 'auth_pages_test.dart' show PageAuth;
import 'auth_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['email', 'google', 'linked']) {
    test(
      'forgot identity: $kind recovery changes only an existing email password',
      () async {
        final backend = AuthBackend()
          ..google = kind != 'email'
          ..emailIdentity = kind == 'linked'
          ..role = 'admin';
        final repository = AuthRepository(
          client: backend.client,
          redirectUrl: 'test-auth://callback',
        );
        addTearDown(repository.dispose);
        addTearDown(backend.client.dispose);
        await repository.sendPasswordReset('owner@example.test');
        expect(backend.requests.single.url.path, '/auth/v1/recover');
        await repository.handleAuthCallback(
          Uri.parse('test-auth://callback?code=recovery'),
        );
        expect(repository.hasValidRecoverySession, isTrue);
        expect(repository.currentSession!.user.id, 'authenticated-owner');
        final identities = repository.currentSession!.user.identities!
            .map((i) => i.provider)
            .toList();
        backend.requests.clear();
        if (kind == 'google') {
          await expectLater(
            repository.resetPassword('New-password123!'),
            throwsA(
              isA<AuthFlowException>().having(
                (e) => e.message,
                'message',
                AuthRepository.googleOnlyResetMessage,
              ),
            ),
          );
          expect(backend.requests, isEmpty);
          expect(
            repository.currentSession!.user.identities!.map((i) => i.provider),
            identities,
          );
          await repository.cancelRecovery();
        } else {
          await repository.resetPassword('New-password123!');
          expect(backend.requests.map((r) => r.url.path), [
            '/auth/v1/user',
            '/auth/v1/logout',
          ]);
          expect(backend.requests.first.method, 'PUT');
          expect(jsonDecode(backend.requests.first.body), {
            'password': 'New-password123!',
          });
          expect(repository.currentSession, isNull);
        }
        expect(backend.role, 'admin');
        expect(backend.user['id'], 'authenticated-owner');
        expect(
          (backend.user['identities'] as List).map((i) => i['provider']),
          identities,
        );
      },
    );

    test(
      'forgot identity: authenticated $kind request uses own identities',
      () async {
        final backend = AuthBackend()
          ..google = kind != 'email'
          ..emailIdentity = kind == 'linked';
        final repository = AuthRepository(client: backend.client);
        addTearDown(repository.dispose);
        addTearDown(backend.client.dispose);
        await backend.signIn();
        if (kind == 'google') {
          await expectLater(
            repository.sendPasswordReset(' OWNER@example.test '),
            throwsA(
              isA<AuthFlowException>().having(
                (e) => e.message,
                'message',
                AuthRepository.googleOnlyResetMessage,
              ),
            ),
          );
          expect(backend.requests, isEmpty);
          backend.recoveryErrorCode = 'user_not_found';
          await repository.sendPasswordReset('unknown@example.test');
        } else {
          await repository.sendPasswordReset('owner@example.test');
        }
        expect(backend.requests.single.url.path, '/auth/v1/recover');
        expect(repository.currentSession!.user.id, 'authenticated-owner');
      },
    );

    testWidgets(
      'forgot identity: $kind recovery UI offers only eligible password fields',
      (tester) async {
        final repository = PageAuth()
          ..emailPassword = kind != 'google'
          ..googleIdentity = kind != 'email';
        addTearDown(repository.dispose);
        await tester.pumpWidget(
          MaterialApp(home: ResetPasswordPage(repository: repository)),
        );
        expect(
          find.byType(TextFormField),
          kind == 'google' ? findsNothing : findsNWidgets(2),
        );
        if (kind == 'google') {
          expect(
            find.text(AuthRepository.googleOnlyResetMessage),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(FilledButton, 'Reset Password'),
            findsNothing,
          );
        }
      },
    );
  }

  testWidgets(
    'forgot identity: known Google-only request offers guidance without a reset form',
    (tester) async {
      final repository = PageAuth()
        ..emailPassword = false
        ..googleIdentity = true;
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordPage(
            repository: repository,
            accountEmail: 'rider@example.test',
            googleSession: true,
          ),
        ),
      );
      expect(find.text(AuthRepository.googleOnlyResetMessage), findsOneWidget);
      expect(find.byType(Form), findsNothing);
      expect(find.text('Send Password Reset Email'), findsNothing);
      expect(repository.resetEmailCalls, 0);
    },
  );
}
