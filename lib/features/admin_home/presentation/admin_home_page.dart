import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_priority.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report.dart';
import 'dart:async';
import 'package:government_transit_collector/core/widgets/responsive_app_shell.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_repository.dart';
import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/ai_recommendation_analysis_session_store.dart';
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
    this.aiRecommendationSessionStore,
    this.recommendationManagementRepository,
    this.aiRecommendationDashboardBuilder,
    super.key,
  });

  final RecommendationManagementRepository? recommendationManagementRepository;
  final AppProfile profile;
  final AuthRepository repository;
  final RoutePerformanceRepository? routePerformanceRepository;
  final PeakOperationRepository? peakOperationRepository;
  final SavedOperationalReportRepository? savedOperationalReportRepository;
  final AiRecommendationAnalysisSessionStore? aiRecommendationSessionStore;
  final Widget Function(AiRecommendationAnalysisSessionStore sessionStore)?
  aiRecommendationDashboardBuilder;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  static const _destinationCount = 5;

  late final List<Widget?> _destinations;
  int _selectedIndex = 0;
  bool _signingOut = false;
  late AiRecommendationAnalysisSessionStore _aiRecommendationSessionStore;

  @override
  void initState() {
    super.initState();
    final injected = widget.aiRecommendationSessionStore;
    if (injected != null && injected.belongsTo(widget.profile.userId)) {
      _aiRecommendationSessionStore = injected;
    } else {
      injected?.clear();
      _aiRecommendationSessionStore = AiRecommendationAnalysisSessionStore(
        adminUserId: widget.profile.userId,
      );
    }
    _destinations = List<Widget?>.filled(_destinationCount, null);
    _destinations[0] = _buildDestination(0);
  }

  @override
  void didUpdateWidget(covariant AdminHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_aiRecommendationSessionStore.belongsTo(widget.profile.userId)) {
      _aiRecommendationSessionStore.clear();
      _aiRecommendationSessionStore = AiRecommendationAnalysisSessionStore(
        adminUserId: widget.profile.userId,
      );
      _destinations[1] = _selectedIndex == 1 ? _buildDestination(1) : null;
    }
    _destinations[0] = _buildDestination(0);
  }

  Widget _buildDestination(int index) => switch (index) {
    0 => _AdminDashboard(
      key: ValueKey(widget.profile.userId),
      profile: widget.profile,
      routeRepository: widget.routePerformanceRepository,
      reportRepository: widget.savedOperationalReportRepository,
      recommendationRepository: widget.recommendationManagementRepository,
      onOpenAnalysis: () => _selectDestination(1),
      active: _selectedIndex == 0,
    ),
    1 =>
      widget.aiRecommendationDashboardBuilder?.call(
            _aiRecommendationSessionStore,
          ) ??
          AiRecommendationDashboardPage(
            showPageHeader: false,
            sessionStore: _aiRecommendationSessionStore,
          ),
    2 => RoutePerformanceDashboardPage(
      showPageHeader: false,
      repository: widget.routePerformanceRepository,
      savedReportRepository: widget.savedOperationalReportRepository,
    ),
    3 => PeakOperationAnalysisPage(
      showPageHeader: false,
      repository: widget.peakOperationRepository,
      savedReportRepository: widget.savedOperationalReportRepository,
    ),
    4 => SavedOperationalReportsPage(
      showPageHeader: false,
      repository: widget.savedOperationalReportRepository,
    ),
    _ => throw RangeError.index(index, _destinations),
  };

  void _selectDestination(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _destinations[index] ??= _buildDestination(index);
      _destinations[0] = _buildDestination(0);
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
      _aiRecommendationSessionStore.clear();
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
    return ResponsiveAppShell(
      items: const [
        AppNavigationItem(label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home_rounded),
        AppNavigationItem(label: 'AI', icon: Icons.auto_awesome_outlined, selectedIcon: Icons.auto_awesome),
        AppNavigationItem(label: 'Performance', icon: Icons.analytics_outlined, selectedIcon: Icons.analytics),
        AppNavigationItem(label: 'Peak', icon: Icons.query_stats_outlined, selectedIcon: Icons.query_stats),
        AppNavigationItem(label: 'Reports', icon: Icons.description_outlined, selectedIcon: Icons.description),
      ],
      selectedIndex: _selectedIndex,
      onSelected: _selectDestination,
      navigationKeyPrefix: 'admin-nav',
      actions: [
        const IconButton(
          tooltip: 'Admin profile',
          onPressed: null,
          icon: Icon(Icons.account_circle_outlined),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: _signingOut ? null : _logout,
          icon: _signingOut
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.logout),
        ),
      ],
      child: IndexedStack(
        index: _selectedIndex,
        children: List<Widget>.generate(
          _destinationCount,
          (index) => _destinations[index] ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _AdminDashboard extends StatefulWidget {
  const _AdminDashboard({
    required this.profile,
    required this.onOpenAnalysis,
    required this.active,
    this.routeRepository,
    this.reportRepository,
    this.recommendationRepository,
    super.key,
  });

  final AppProfile profile;
  final VoidCallback onOpenAnalysis;
  final bool active;
  final RoutePerformanceRepository? routeRepository;
  final SavedOperationalReportRepository? reportRepository;
  final RecommendationManagementRepository? recommendationRepository;

  @override
  State<_AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<_AdminDashboard> {
  int? _routeCount;
  List<SavedOperationalReport>? _reports;
  List<SavedRecommendation>? _recommendations;
  bool _routesLoading = true;
  bool _reportsLoading = true;
  bool _recommendationsLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRoutes());
    unawaited(_loadReports());
    unawaited(_loadRecommendations());
  }

  @override
  void didUpdateWidget(covariant _AdminDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      if (!_reportsLoading) unawaited(_loadReports());
      if (!_recommendationsLoading) unawaited(_loadRecommendations());
    }
  }

  Future<void> _loadRoutes() async {
    try {
      final repository = widget.routeRepository ?? DefaultRoutePerformanceRepository();
      final routes = await repository.loadRoutes();
      if (mounted) setState(() => _routeCount = routes.length);
    } on Object {
      if (mounted) setState(() => _routeCount = null);
    } finally {
      if (mounted) setState(() => _routesLoading = false);
    }
  }

  Future<void> _loadReports() async {
    setState(() => _reportsLoading = true);
    try {
      final repository = widget.reportRepository ?? DefaultSavedOperationalReportRepository();
      final reports = [...await repository.loadReports()];
      reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (mounted) setState(() => _reports = reports);
    } on Object {
      if (mounted) setState(() => _reports = null);
    } finally {
      if (mounted) setState(() => _reportsLoading = false);
    }
  }

  Future<void> _loadRecommendations() async {
    setState(() => _recommendationsLoading = true);
    try {
      final repository = widget.recommendationRepository ?? DefaultRecommendationManagementRepository();
      final recommendations = await repository.loadSavedRecommendations();
      if (mounted) setState(() => _recommendations = recommendations);
    } on Object {
      if (mounted) setState(() => _recommendations = null);
    } finally {
      if (mounted) setState(() => _recommendationsLoading = false);
    }
  }

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
                      '$_greeting, ${widget.profile.displayName}',
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
                    const SizedBox(height: 24),
                    Text('Network Snapshot', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _HomeMetric(
                            icon: Icons.alt_route,
                            label: 'Routes',
                            value: _routeCount,
                            loading: _routesLoading,
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _HomeMetric(
                            icon: Icons.description_outlined,
                            label: 'Saved Reports',
                            value: _reports?.length,
                            loading: _reportsLoading,
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    LayoutBuilder(builder: (context, constraints) {
                      final attention = _attention();
                      final planning = _planning();
                      if (constraints.maxWidth >= 600) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: attention),
                            const SizedBox(width: 24),
                            Expanded(child: planning),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          attention,
                          const SizedBox(height: 24),
                          planning,
                        ],
                      );
                    }),
                    if (_reports?.isNotEmpty == true) ...[
                      const SizedBox(height: 24),
                      _HomeSection(
                        title: 'Recent Activity',
                        children: [
                          Text(
                            'Recently saved operational reports',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final entry in _reports!.take(2).toList().asMap().entries) ...[
                            if (entry.key > 0) const Divider(height: 24),
                            _ReportPreview(
                              report: entry.value,
                              subtitle: '${entry.value.reportType.label} report saved / ${_savedAt(entry.value.createdAt)}',
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _savedAt(DateTime instant) {
    final local = instant.toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatMediumDate(local)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Widget _attention() {
    final theme = Theme.of(context);
    final reports = _reports;
    final attention = reports?.where((report) =>
        report.status == SavedOperationalReportStatus.needsAttention).toList();
    attention?.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _HomeSection(
      key: const Key('home-needs-attention'),
      title: 'Needs Attention',
      children: [
        if (reports == null)
          Text(_reportsLoading
              ? 'Checking saved report statuses...'
              : 'Operational report status is unavailable.')
        else if (attention!.isEmpty)
          const Text('No immediate operational issues to review.')
        else
          for (final report in attention!.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ReportPreview(
                report: report,
                subtitle: '${report.reportType.label} / ${report.status.label}',
                showRoute: true,
              ),
            ),
        if (reports != null) ...[
          const SizedBox(height: 8),
          Text('Based on saved report review statuses.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _planning() {
    final theme = Theme.of(context);
    final recommendations = _recommendations;
    return _HomeSection(
      key: const Key('home-ai-planning'),
      title: 'AI Planning',
      children: [
        if (recommendations == null)
          Text(_recommendationsLoading
              ? 'Loading planning summary...'
              : 'Planning summary is unavailable.')
        else if (recommendations.isEmpty)
          const Text('Ready for analysis')
        else ...[
          Text('Pending Recommendations: ${recommendations.where((record) => record.status == RecommendationReviewStatus.pending).length}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text('High Priority: ${recommendations.where((record) => record.priorityLevel == RecommendationPriorityLevel.high).length}'),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: widget.onOpenAnalysis,
            child: const Text('Open AI Analysis'),
          ),
        ),
      ],
    );
  }
}

class _HomeMetric extends StatelessWidget {
  const _HomeMetric({required this.icon, required this.label, required this.value, required this.loading});
  final IconData icon;
  final String label;
  final int? value;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('home-metric-$label'),
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(value?.toString() ?? (loading ? 'Loading...' : 'Unavailable'),
            textAlign: TextAlign.center,
            style: value == null ? theme.textTheme.bodySmall
                : theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _ReportPreview extends StatelessWidget {
  const _ReportPreview({required this.report, required this.subtitle, this.showRoute = false});
  final SavedOperationalReport report;
  final String subtitle;
  final bool showRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = report.routeNameSnapshot.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.description_outlined, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(showRoute && route.isNotEmpty ? route : report.title,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall,
            ),
          ],
        )),
      ],
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}
