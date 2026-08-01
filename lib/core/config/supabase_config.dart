import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseConfig {
  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: '.env');
    } on Object catch (error) {
      throw StateError(
        'Unable to load .env. Create it in the project root using '
        '.env.example as a template. Details: $error',
      );
    }

    final url = dotenv.maybeGet('SUPABASE_URL')?.trim();
    final publishableKey = dotenv.maybeGet('SUPABASE_ANON_KEY')?.trim();

    if (url == null ||
        url.isEmpty ||
        publishableKey == null ||
        publishableKey.isEmpty) {
      throw StateError(
        'Missing Supabase configuration. Set SUPABASE_URL and '
        'SUPABASE_ANON_KEY in the local .env file.',
      );
    }

    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }
}
