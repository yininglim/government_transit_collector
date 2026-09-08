import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/journey_reminders/reminder_controller.dart';
import 'package:government_transit_collector/app/app.dart';
import 'package:government_transit_collector/core/config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  final authRepository = AuthRepository();
  await authRepository.initializeDeepLinks();
  // Observe account changes for reminder ownership; never requests permission.
  sharedReminderController;
  runApp(App(authRepository: authRepository));
}
