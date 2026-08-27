import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/core/config/gemini_config.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_data_source.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const secret = 'test-secret-value';
  const schema = {
    'type': 'object',
    'properties': {
      'result': {'type': 'string'},
    },
    'required': ['result'],
    'additionalProperties': false,
  };
  const request = GeminiStructuredInteractionRequest(
    input: 'Provide structured evidence.',
    instructions: 'Return only evidence.',
    responseSchema: schema,
  );

  test('missing API key fails before an HTTP call', () async {
    var called = false;
    final source = GeminiInteractionsDataSource(
      config: const GeminiConfig(apiKey: '  '),
      client: MockClient((_) async {
        called = true;
        return http.Response('', 200);
      }),
    );

    await expectLater(
      source.createStructuredInteraction(request),
      throwsA(_failure(GeminiTransportFailure.notConfigured)),
    );
    expect(called, isFalse);
  });

  test('sends the structured stateless interaction request', () async {
    late http.Request captured;
    final source = GeminiInteractionsDataSource(
      config: const GeminiConfig(apiKey: secret),
      client: MockClient((request) async {
        captured = request;
        return http.Response(_successfulResponse(), 200);
      }),
    );

    await source.createStructuredInteraction(request);

    expect(captured.method, 'POST');
    expect(captured.url.toString(), geminiInteractionsEndpoint);
    expect(captured.url.query, isEmpty);
    expect(captured.headers['x-goog-api-key'], secret);
    expect(captured.headers['content-type'], 'application/json');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], defaultGeminiModel);
    expect(body['input'], request.input);
    expect(body['system_instruction'], request.instructions);
    expect(body['store'], isFalse);
    expect(body.containsKey('previous_interaction_id'), isFalse);
    expect(body['response_format'], {
      'type': 'text',
      'mime_type': 'application/json',
      'schema': schema,
    });
  });

  test('parses structured JSON from the completed model output', () async {
    final source = _source(
      (_) async => http.Response(_successfulResponse(), 200),
    );

    final result = await source.createStructuredInteraction(request);

    expect(result.interactionId, 'interaction-1');
    expect(result.value, {'result': 'available'});
  });

  test('parses a completed envelope when optional object is omitted', () async {
    final response = jsonDecode(_successfulResponse()) as Map<String, dynamic>
      ..remove('object');
    final source = _source(
      (_) async => http.Response(jsonEncode(response), 200),
    );

    final result = await source.createStructuredInteraction(request);

    expect(result.interactionId, 'interaction-1');
    expect(result.value, {'result': 'available'});
  });

  test(
    'parses a direct structured JSON object without an interaction ID',
    () async {
      final source = _source(
        (_) async => http.Response('{"result":"available"}', 200),
      );

      final result = await source.createStructuredInteraction(request);

      expect(result.interactionId, isNull);
      expect(result.value, {'result': 'available'});
    },
  );

  test('rejects malformed outer JSON', () async {
    final source = _source((_) async => http.Response('not-json', 200));

    await expectLater(
      source.createStructuredInteraction(request),
      throwsA(_failure(GeminiTransportFailure.malformedResponse)),
    );
  });

  test('rejects an unexpected top-level response shape', () async {
    final source = _source((_) async => http.Response('[]', 200));

    await expectLater(
      source.createStructuredInteraction(request),
      throwsA(_failure(GeminiTransportFailure.malformedResponse)),
    );
  });

  test('rejects a non-completed Interaction', () async {
    final response = jsonDecode(_successfulResponse()) as Map<String, dynamic>
      ..['status'] = 'incomplete';
    final source = _source(
      (_) async => http.Response(jsonEncode(response), 200),
    );

    await expectLater(
      source.createStructuredInteraction(request),
      throwsA(_failure(GeminiTransportFailure.malformedResponse)),
    );
  });

  test('rejects a completed Interaction with missing steps', () async {
    final source = _source(
      (_) async => http.Response(
        jsonEncode({
          'id': 'interaction-1',
          'object': 'interaction',
          'status': 'completed',
        }),
        200,
      ),
    );

    await expectLater(
      source.createStructuredInteraction(request),
      throwsA(_failure(GeminiTransportFailure.missingStructuredOutput)),
    );
  });

  test('rejects malformed structured JSON', () async {
    final source = _source(
      (_) async => http.Response(_successfulResponse(text: '{invalid'), 200),
    );

    await expectLater(
      source.createStructuredInteraction(request),
      throwsA(_failure(GeminiTransportFailure.invalidStructuredJson)),
    );
  });

  test('rejects missing structured output', () async {
    final source = _source(
      (_) async => http.Response(
        jsonEncode({
          'id': 'interaction-1',
          'object': 'interaction',
          'status': 'completed',
          'steps': <Object>[],
        }),
        200,
      ),
    );

    await expectLater(
      source.createStructuredInteraction(request),
      throwsA(_failure(GeminiTransportFailure.missingStructuredOutput)),
    );
  });

  test('maps a non-success HTTP response', () async {
    final source = _source((_) async => http.Response('failure', 500));

    await expectLater(
      source.createStructuredInteraction(request),
      throwsA(
        isA<GeminiTransportException>()
            .having(
              (error) => error.failure,
              'failure',
              GeminiTransportFailure.http,
            )
            .having((error) => error.statusCode, 'statusCode', 500),
      ),
    );
  });

  for (final statusCode in [401, 403]) {
    test('maps HTTP $statusCode to authentication failure', () async {
      final source = _source((_) async => http.Response('failure', statusCode));

      await expectLater(
        source.createStructuredInteraction(request),
        throwsA(_failure(GeminiTransportFailure.authentication)),
      );
    });
  }

  test('maps HTTP 429 to rate-limit failure', () async {
    final source = _source((_) async => http.Response('failure', 429));

    await expectLater(
      source.createStructuredInteraction(request),
      throwsA(_failure(GeminiTransportFailure.rateLimited)),
    );
  });

  test('maps request timeout without exposing the API key', () async {
    final source = GeminiInteractionsDataSource(
      config: const GeminiConfig(apiKey: secret),
      client: MockClient((_) => Completer<http.Response>().future),
      requestTimeout: const Duration(milliseconds: 1),
    );

    final error = await _captureFailure(source, request);

    expect(error.failure, GeminiTransportFailure.timeout);
    expect(error.toString(), isNot(contains(secret)));
  });

  test('maps network failure without exposing the API key', () async {
    final source = _source((_) async => throw http.ClientException('failed'));

    final error = await _captureFailure(source, request);

    expect(error.failure, GeminiTransportFailure.network);
    expect(error.toString(), isNot(contains(secret)));
  });

  test('configuration text never exposes the API key', () {
    const config = GeminiConfig(apiKey: secret);

    expect(config.toString(), isNot(contains(secret)));
    expect(config.isAvailable, isTrue);
  });
}

GeminiInteractionsDataSource _source(
  Future<http.Response> Function(http.Request) handler,
) => GeminiInteractionsDataSource(
  config: const GeminiConfig(apiKey: 'test-secret-value'),
  client: MockClient(handler),
);

Matcher _failure(GeminiTransportFailure failure) =>
    isA<GeminiTransportException>().having(
      (error) => error.failure,
      'failure',
      failure,
    );

Future<GeminiTransportException> _captureFailure(
  GeminiDataSource source,
  GeminiStructuredInteractionRequest request,
) async {
  try {
    await source.createStructuredInteraction(request);
    throw StateError('Expected the interaction to fail.');
  } on GeminiTransportException catch (error) {
    return error;
  }
}

String _successfulResponse({String text = '{"result":"available"}'}) =>
    jsonEncode({
      'id': 'interaction-1',
      'object': 'interaction',
      'status': 'completed',
      'steps': [
        {
          'type': 'model_output',
          'content': [
            {'type': 'text', 'text': text},
          ],
        },
      ],
    });
