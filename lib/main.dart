import 'package:flutter/material.dart';
import 'package:government_transit_collector/app/app.dart';
import 'package:government_transit_collector/core/config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(const App());
}
