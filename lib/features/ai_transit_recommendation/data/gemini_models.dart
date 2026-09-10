class GeminiStructuredInteractionRequest {
  const GeminiStructuredInteractionRequest({
    required this.input,
    required this.responseSchema,
    this.instructions,
  });

  final String input;
  final String? instructions;
  final Map<String, dynamic> responseSchema;
}

class GeminiStructuredInteractionResult {
  const GeminiStructuredInteractionResult({
    required this.interactionId,
    required this.value,
  });

  final String? interactionId;
  final Map<String, dynamic> value;
}

enum GeminiTransportFailure {
  notConfigured,
  timeout,
  network,
  authentication,
  rateLimited,
  http,
  malformedResponse,
  missingStructuredOutput,
  invalidStructuredJson,
}

class GeminiTransportException implements Exception {
  const GeminiTransportException({
    required this.failure,
    required this.message,
    this.statusCode,
    this.providerErrorCode,
    this.providerErrorMessage,
  });

  final GeminiTransportFailure failure;
  final String message;
  final int? statusCode;
  final String? providerErrorCode;
  final String? providerErrorMessage;

  @override
  String toString() => message;
}
