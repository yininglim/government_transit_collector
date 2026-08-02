import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/theme/app_theme.dart';
import 'package:government_transit_collector/features/authentication/presentation/auth_gate.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Government Transit Collector',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: AuthGate(),
    );
  }
}
