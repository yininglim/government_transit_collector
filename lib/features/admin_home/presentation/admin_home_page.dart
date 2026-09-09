import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/ai_recommendation_dashboard_page.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_repository.dart';
import 'package:government_transit_collector/features/peak_operation/presentation/peak_operation_analysis_page.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:government_transit_collector/features/route_performance/presentation/route_performance_dashboard_page.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report_repository.dart';
import 'package:government_transit_collector/features/saved_operational_reports/presentation/saved_operational_reports_page.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({
    required this.profile,
    required this.repository,
    this.routePerformanceRepository,
    this.peakOperationRepository,
    this.savedOperationalReportRepository,
    super.key,
  });

  final AppProfile profile;
  final AuthRepository repository;
  final RoutePerformanceRepository? routePerformanceRepository;
  final PeakOperationRepository? peakOperationRepository;
  final SavedOperationalReportRepository? savedOperationalReportRepository;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  bool _signingOut = false;

  Future<void> _logout() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await widget.repository.logout();
    } on AuthFlowException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      setState(() => _signingOut = false);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to sign out. Please try again.')),
      );
      setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Government Transit Collector'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signingOut ? null : _logout,
            icon: _signingOut
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Admin / Transport Authority',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Welcome, ${widget.profile.displayName}'),
            const SizedBox(height: 32),
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('AI Transit Recommendation'),
                subtitle: const Text(
                  'Review transit recommendations and estimation reports.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiRecommendationDashboardPage(),
                  ),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('Route Performance Dashboard'),
                subtitle: const Text(
                  'Analyse collected travel time, delay frequency, and route efficiency.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RoutePerformanceDashboardPage(
                      repository: widget.routePerformanceRepository,
                    ),
                  ),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.query_stats),
                title: const Text('Peak Operation Analysis'),
                subtitle: const Text(
                  'Identify high observed bus service activity by time of day.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PeakOperationAnalysisPage(
                      repository: widget.peakOperationRepository,
                    ),
                  ),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Saved Operational Reports'),
                subtitle: const Text(
                  'Review historical Route Performance and Peak Operation snapshots.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SavedOperationalReportsPage(
                      repository: widget.savedOperationalReportRepository,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
