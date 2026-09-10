import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/authentication/presentation/register_page.dart';
import 'auth_test_support.dart';

void main() {
  late AuthRepository repository;
  late SupabaseClient client;
  late AuthBackend fixture;
  late Future<http.Response> Function() signup;
  var signupCalls = 0;

  http.Response reply(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {
      'content-type': 'application/json',
      'x-supabase-api-version': '2024-01-01',
    },
  );

  setUp(() {
    signupCalls = 0;
    fixture = AuthBackend()..google = false;
    signup = () async => reply({...fixture.user, 'email_confirmed_at': null});
    client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.pkce,
        pkceAsyncStorage: MemoryAuthStorage(),
      ),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/auth/v1/signup');
        signupCalls++;
        return signup();
      }),
    );
    repository = AuthRepository(client: client);
  });

  tearDown(() async {
    repository.dispose();
    await client.dispose();
  });

  List<Object?> finishes(WidgetTester tester) => tester.testTextInput.log
      .where((call) => call.method == 'TextInput.finishAutofillContext')
      .map((call) => call.arguments)
      .toList();

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RegisterPage(repository: repository),
                ),
              ),
              child: const Text('Open registration'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open registration'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    for (final entry in [
      'Rider',
      'rider@example.test',
      'Password123!',
      'Password123!',
    ].asMap().entries) {
      await tester.enterText(fields.at(entry.key), entry.value);
    }
    tester.testTextInput.log.clear();
  }

  Future<void> submit(WidgetTester tester, {bool keyboard = false}) async {
    if (keyboard) {
      await tester.testTextInput.receiveAction(TextInputAction.done);
    } else {
      await tester.ensureVisible(find.text('Register'));
      await tester.tap(find.text('Register'));
    }
    await tester.pump();
  }

  for (final invalid in [
    (0, ''),
    (1, 'invalid'),
    (2, 'short'),
    (3, 'Mismatch123!'),
  ]) {
    testWidgets(
      'invalid signup field ${invalid.$1} never commits credentials',
      (tester) async {
        await show(tester);
        await tester.enterText(
          find.byType(TextFormField).at(invalid.$1),
          invalid.$2,
        );
        await tester.pump();
        tester.testTextInput.log.clear();
        await submit(tester);
        expect(signupCalls, 0);
        expect(finishes(tester), [false]);
        final calls = tester.testTextInput.log;
        expect(
          calls.indexWhere(
            (call) => call.method == 'TextInput.finishAutofillContext',
          ),
          lessThan(
            calls.indexWhere((call) => call.method == 'TextInput.clearClient'),
          ),
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(finishes(tester), [false, false]);
      },
    );
  }

  for (final failure in [
    'rejected',
    'existing',
    'obfuscated',
    'missing user',
    'backend',
    'network',
    'unexpected',
  ]) {
    testWidgets(
      '$failure signup never commits credentials, including on exit',
      (tester) async {
        signup = () async {
          switch (failure) {
            case 'network':
              throw http.ClientException('Network unavailable');
            case 'unexpected':
              throw StateError('Unexpected failure');
            case 'obfuscated':
              return reply({...fixture.user, 'identities': []});
            case 'missing user':
              return reply({});
            default:
              return reply({
                'code': failure == 'existing'
                    ? 'user_already_exists'
                    : 'signup_disabled',
                'message': 'Signup rejected',
              }, failure == 'backend' ? 500 : 422);
          }
        };
        await show(tester);
        await submit(tester, keyboard: true);
        await tester.pumpAndSettle();
        expect(signupCalls, greaterThanOrEqualTo(1));
        expect(find.byType(RegisterPage), findsOneWidget);
        expect(find.text('Verify Your Email'), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(finishes(tester), [false]);
        final calls = tester.testTextInput.log;
        final cancel = calls.indexWhere(
          (call) => call.method == 'TextInput.finishAutofillContext',
        );
        expect(
          calls
              .skip(cancel + 1)
              .any((call) => call.method == 'TextInput.clearClient'),
          isTrue,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(finishes(tester), [false, false]);
      },
    );
  }

  for (final confirmation in [true, false]) {
    testWidgets(
      'signup commits only after success (verification: $confirmation)',
      (tester) async {
        final response = Completer<http.Response>();
        signup = () => response.future;
        await show(tester);
        await submit(tester);
        expect(finishes(tester), isEmpty);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        response.complete(
          reply(
            confirmation
                ? {...fixture.user, 'email_confirmed_at': null}
                : fixture.session,
          ),
        );
        await tester.pumpAndSettle();
        expect(finishes(tester), [true, false]);
        expect(
          find.text('Verify Your Email'),
          confirmation ? findsOneWidget : findsNothing,
        );
        if (confirmation) {
          expect(find.text('rider@example.test'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
        } else {
          expect(find.byType(RegisterPage), findsNothing);
        }
      },
    );
  }

  testWidgets(
    'successful retry can save unchanged credentials after a rejection',
    (tester) async {
      signup = () async =>
          reply({'code': 'signup_disabled', 'message': 'Rejected'}, 422);
      await show(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(finishes(tester), [false]);
      signup = () async => reply({...fixture.user, 'email_confirmed_at': null});
      await submit(tester);
      await tester.pumpAndSettle();
      expect(signupCalls, 2);
      expect(finishes(tester), [false, true, false]);
      final calls = tester.testTextInput.log;
      final cancel = calls.indexWhere(
        (call) => call.method == 'TextInput.finishAutofillContext',
      );
      final save = calls.indexWhere(
        (call) =>
            call.method == 'TextInput.finishAutofillContext' &&
            call.arguments == true,
      );
      final reattach = calls.indexWhere(
        (call) => call.method == 'TextInput.setClient',
        cancel + 1,
      );
      expect(reattach, greaterThan(cancel));
      expect(reattach, lessThan(save));
      final config = (calls[reattach].arguments as List)[1] as Map;
      final fields = config['fields'] as List;
      expect(
        fields.any(
          (field) =>
              field['autofill']['editingValue']['text'] == 'Password123!',
        ),
        isTrue,
      );
      expect(find.text('Verify Your Email'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );

  for (final keyboard in [false, true]) {
    testWidgets(
      'pending signup retains autofill and locks input (IME: $keyboard)',
      (tester) async {
        final response = Completer<http.Response>();
        signup = () => response.future;
        await show(tester);
        final group = tester.state(find.byType(AutofillGroup));
        await submit(tester, keyboard: keyboard);
        await tester.pump();
        expect(tester.state(find.byType(AutofillGroup)), same(group));
        expect(finishes(tester), isEmpty);
        final fields = tester.widgetList<EditableText>(
          find.byType(EditableText),
        );
        expect(fields.every((field) => !field.readOnly), isTrue);
        expect(fields.map((field) => field.autofillHints?.toList()), [
          [AutofillHints.name],
          [AutofillHints.email],
          [AutofillHints.newPassword],
          [AutofillHints.newPassword],
        ]);
        expect(fields.where((field) => field.focusNode.hasFocus).length, 1);
        tester.testTextInput.log.clear();
        tester.testTextInput.enterText('changed@example.test');
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(1))
              .controller!
              .text,
          'rider@example.test',
        );
        expect(
          tester.testTextInput.log.where(
            (call) =>
                call.method == 'TextInput.clearClient' ||
                call.method == 'TextInput.hide' ||
                call.method == 'TextInput.finishAutofillContext',
          ),
          isEmpty,
        );
        response.complete(
          reply({'code': 'signup_disabled', 'message': 'Rejected'}, 422),
        );
        await tester.pumpAndSettle();
        expect(finishes(tester), [false]);
        expect(tester.state(find.byType(AutofillGroup)), same(group));
        await tester.pageBack();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'leaving an unfinished signup cancels and late success does not commit',
    (tester) async {
      final response = Completer<http.Response>();
      signup = () => response.future;
      await show(tester);
      await submit(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(finishes(tester), [false]);
      response.complete(reply({...fixture.user, 'email_confirmed_at': null}));
      await tester.pumpAndSettle();
      expect(finishes(tester), [false]);
    },
  );
}
