import 'dart:async';
import 'dart:convert';

import 'package:government_transit_collector/core/config/gemini_config.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_models.dart';
import 'package:http/http.dart' as http;

const geminiInteractionsEndpoint =
    'https://generativelanguage.googleapis.com/v1beta/interactions';

abstract interface class GeminiDataSource {
  Future<GeminiStructuredInteractionResult> createStructuredInteraction(
    GeminiStructuredInteractionRequest request,
  );
}

class GeminiInteractionsDataSource implements GeminiDataSource {
  GeminiInteractionsDataSource({
    GeminiConfig? config,
    http.Client? client,
    this.model = defaultGeminiModel,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _config = config ?? GeminiConfig.fromDotEnv(),
       _client = client ?? http.Client();

  final GeminiConfig _config;
  final http.Client _client;
  final String model;
  final Duration requestTimeout;

  @override
  Future<GeminiStructuredInteractionResult> createStructuredInteraction(
    GeminiStructuredInteractionRequest request,
  ) async {
    final apiKey = _config.apiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw const GeminiTransportException(
        failure: GeminiTransportFailure.notConfigured,
        message: 'Gemini is not configured.',
      );
    }

    try {
      final response = await _client
          .post(
            Uri.parse(geminiInteractionsEndpoint),
            headers: {
              'x-goog-api-key': apiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'input': request.input,
              if (request.instructions != null &&
                  request.instructions!.trim().isNotEmpty)
                'system_instruction': request.instructions,
              'response_format': {
                'type': 'text',
                'mime_type': 'application/json',
                'schema': request.responseSchema,
              },
              'store': false,
            }),
          )
          .timeout(requestTimeout);
      _validateStatus(response.statusCode);
      return parseGeminiStructuredInteractionResponse(response.body);
    } on GeminiTransportException {
      rethrow;
    } on TimeoutException {
      throw const GeminiTransportException(
        failure: GeminiTransportFailure.timeout,
        message: 'The Gemini request timed out.',
      );
    } on http.ClientException {
      throw const GeminiTransportException(
        failure: GeminiTransportFailure.network,
        message: 'Unable to connect to Gemini.',
      );
    } on Object {
      throw const GeminiTransportException(
        failure: GeminiTransportFailure.network,
        message: 'Unable to complete the Gemini request.',
      );
    }
  }
}

void _validateStatus(int statusCode) {
  if (statusCode >= 200 && statusCode < 300) return;
  if (statusCode == 401 || statusCode == 403) {
    throw GeminiTransportException(
      failure: GeminiTransportFailure.authentication,
      statusCode: statusCode,
      message: 'Gemini authentication or permission was denied.',
    );
  }
  if (statusCode == 429) {
    throw GeminiTransportException(
      failure: GeminiTransportFailure.rateLimited,
      statusCode: statusCode,
      message: 'Gemini rate limit was reached.',
    );
  }
  throw GeminiTransportException(
    failure: GeminiTransportFailure.http,
    statusCode: statusCode,
    message: 'Gemini returned HTTP $statusCode.',
  );
}

GeminiStructuredInteractionResult parseGeminiStructuredInteractionResponse(
  String body,
) {
  late final Map<String, dynamic> root;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    root = decoded;
  } on Object {
    throw const GeminiTransportException(
      failure: GeminiTransportFailure.malformedResponse,
      message: 'Gemini returned a malformed response.',
    );
  }

  final object = root['object'];
  final status = root['status'];
  final isInteraction =
      object == 'interaction' ||
      root.containsKey('steps') ||
      (root.containsKey('id') && _interactionStatuses.contains(status));
  if (!isInteraction) {
    return GeminiStructuredInteractionResult(interactionId: null, value: root);
  }

  if ((object != null && object != 'interaction') || status != 'completed') {
    throw const GeminiTransportException(
      failure: GeminiTransportFailure.malformedResponse,
      message: 'Gemini returned an unexpected response shape.',
    );
  }

  final id = root['id'];
  if (id != null && (id is! String || id.isEmpty)) {
    throw const GeminiTransportException(
      failure: GeminiTransportFailure.malformedResponse,
      message: 'Gemini returned an unexpected response shape.',
    );
  }
  final steps = root['steps'];
  if (steps is! List<dynamic>) {
    throw const GeminiTransportException(
      failure: GeminiTransportFailure.missingStructuredOutput,
      message: 'Gemini returned no structured output.',
    );
  }

  String? output;
  for (final step in steps.reversed) {
    if (step is! Map<String, dynamic> || step['type'] != 'model_output') {
      continue;
    }
    final content = step['content'];
    if (content is! List<dynamic>) continue;
    final textParts = <String>[];
    for (final part in content) {
      if (part is Map<String, dynamic> &&
          part['type'] == 'text' &&
          part['text'] is String) {
        textParts.add(part['text'] as String);
      }
    }
    if (textParts.isNotEmpty) {
      output = textParts.join();
      break;
    }
  }
  if (output == null || output.trim().isEmpty) {
    throw const GeminiTransportException(
      failure: GeminiTransportFailure.missingStructuredOutput,
      message: 'Gemini returned no structured output.',
    );
  }

  try {
    final decoded = jsonDecode(output);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    return GeminiStructuredInteractionResult(
      interactionId: id as String?,
      value: decoded,
    );
  } on Object {
    throw const GeminiTransportException(
      failure: GeminiTransportFailure.invalidStructuredJson,
      message: 'Gemini returned invalid structured JSON.',
    );
  }
}

const _interactionStatuses = {
  'in_progress',
  'requires_action',
  'completed',
  'failed',
  'cancelled',
  'incomplete',
};
