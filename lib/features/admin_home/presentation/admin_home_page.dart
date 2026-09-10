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
  static const _destinationCount = 5;

  late final List<Widget?> _destinations;
  int _selectedIndex = 0;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _destinations = List<Widget?>.filled(_destinationCount, null);
    _destinations[0] = _buildDestination(0);
  }

  Widget _buildDestination(int index) => switch (index) {
    0 => _AdminDashboard(
      profile: widget.profile,
      signingOut: _signingOut,
      onLogout: _logout,
    ),
    1 => const AiRecommendationDashboardPage(),
    2 => RoutePerformanceDashboardPage(
      repository: widget.routePerformanceRepository,
      savedReportRepository: widget.savedOperationalReportRepository,
    ),
    3 => PeakOperationAnalysisPage(
      repository: widget.peakOperationRepository,
      savedReportRepository: widget.savedOperationalReportRepository,
    ),
    4 => SavedOperationalReportsPage(
      repository: widget.savedOperationalReportRepository,
    ),
    _ => throw RangeError.index(index, _destinations),
  };

  void _selectDestination(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _destinations[index] ??= _buildDestination(index);
    });
  }

  Future<void> _logout() async {
    if (_signingOut) return;
    setState(() {
      _signingOut = true;
      _destinations[0] = _buildDestination(0);
    });
    try {
      await widget.repository.logout();
    } on AuthFlowException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      _resetSigningOut();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to sign out. Please try again.')),
      );
      _resetSigningOut();
    }
  }

  void _resetSigningOut() {
    setState(() {
      _signingOut = false;
      _destinations[0] = _buildDestination(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: List<Widget>.generate(
          _destinationCount,
          (index) => _destinations[index] ?? const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _selectDestination,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'AI',
            ),
            NavigationDestination(
              icon: Icon(Icons.analytics_outlined),
              selectedIcon: Icon(Icons.analytics),
              label: 'Performance',
            ),
            NavigationDestination(
              icon: Icon(Icons.query_stats_outlined),
              selectedIcon: Icon(Icons.query_stats),
              label: 'Peak',
            ),
            NavigationDestination(
              icon: Icon(Icons.description_outlined),
              selectedIcon: Icon(Icons.description),
              label: 'Reports',
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard({
    required this.profile,
    required this.signingOut,
    required this.onLogout,
  });

  final AppProfile profile;
  final bool signingOut;
  final VoidCallback onLogout;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Government Transit Collector'),
        actions: [
          IconButton(
            tooltip: 'Admin profile',
            onPressed: null,
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: signingOut ? null : onLogout,
            icon: signingOut
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth >= 720 ? 40 : 24,
              vertical: 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$_greeting, ${profile.displayName}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Monitor and improve Johor bus operations.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.directions_bus_filled_outlined,
                              size: 36,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Operations overview',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Use the navigation below to review recommendations, performance, peak activity, and saved reports.',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
