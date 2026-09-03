import 'package:flutter_dotenv/flutter_dotenv.dart';

const defaultGeminiModel = 'gemini-3.5-flash-lite';
const defaultGeminiThinkingLevel = 'minimal';

class GeminiConfig {
  const GeminiConfig({this.apiKey});

  factory GeminiConfig.fromDotEnv() {
    String? apiKey;
    try {
      apiKey = dotenv.maybeGet('GEMINI_API_KEY')?.trim();
    } on Object {
      apiKey = null;
    }
    return GeminiConfig(apiKey: apiKey);
  }

  final String? apiKey;

  bool get isAvailable => apiKey != null && apiKey!.trim().isNotEmpty;

  @override
  String toString() => 'GeminiConfig(isAvailable: $isAvailable)';
}
