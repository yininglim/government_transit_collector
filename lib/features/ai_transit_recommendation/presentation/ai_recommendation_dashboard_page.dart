import 'package:government_transit_collector/core/widgets/readable_app_bar.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_priority.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

import 'package:government_transit_collector/features/ai_transit_recommendation/data/ai_recommendation_analysis_session_store.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/bus_frequency_recommendation_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/cost_estimation_report_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/route_bus_stop_recommendation_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/recommendation_management_page.dart';

class AiRecommendationDashboardPage extends StatefulWidget {
  const AiRecommendationDashboardPage({
    this.busFrequencyPageBuilder,
    this.routeStopPageBuilder,
    this.costPageBuilder,
    this.managementPageBuilder,
    this.busFrequencyCoordinator,
    this.routeStopCoordinator,
    this.costCoordinator,
    this.managementRepository,
    this.routeRepository,
    this.sessionStore,
    this.now,
    this.preloadBusFrequency = false,
    this.preloadRouteStops = false,
    this.showPageHeader = true,
    super.key,
  });

  final Widget Function(BusFrequencyDashboardSession session)?
  busFrequencyPageBuilder;
  final Widget Function(RouteStopDashboardSession session)?
  routeStopPageBuilder;
  final Widget Function(CostDashboardSession session)? costPageBuilder;
  final Widget Function(RecommendationManagementRepository repository)?
  managementPageBuilder;
  final BusFrequencyDashboardCoordinator? busFrequencyCoordinator;
  final RouteStopDashboardCoordinator? routeStopCoordinator;
  final CostDashboardCoordinator? costCoordinator;
  final RecommendationManagementRepository? managementRepository;
  final RoutePerformanceRepository? routeRepository;
  final AiRecommendationAnalysisSessionStore? sessionStore;
  final DateTime Function()? now;
  final bool preloadBusFrequency;
  final bool preloadRouteStops;

  final bool showPageHeader;

  @override
  State<AiRecommendationDashboardPage> createState() =>
      _AiRecommendationDashboardPageState();
}

class _AiRecommendationDashboardPageState
    extends State<AiRecommendationDashboardPage> {
  late final BusFrequencyDashboardSession _busFrequencySession;
  late final RouteStopDashboardSession _routeStopSession;
  late final CostDashboardSession _costSession;
  BusFrequencyDashboardCoordinator? _busFrequencyCoordinator;
  RouteStopDashboardCoordinator? _routeStopCoordinator;
  CostDashboardCoordinator? _costCoordinator;
  RecommendationManagementRepository? _managementRepository;
  late final _RecommendationPreparationScheduler _preparationScheduler;
  List<SavedRecommendation>? _records;
  int? _routeCount;
  bool _loading = true;
  bool _loadFailed = false;


  BusFrequencyDashboardCoordinator get _frequencyCoordinator =>
      _busFrequencyCoordinator ??= BusFrequencyDashboardCoordinator();

  RouteStopDashboardCoordinator get _routeCoordinator =>
      _routeStopCoordinator ??= RouteStopDashboardCoordinator();

  CostDashboardCoordinator get _costCoordinatorValue =>
      _costCoordinator ??= CostDashboardCoordinator();

  RecommendationManagementRepository get _managementRepositoryValue =>
      _managementRepository ??= DefaultRecommendationManagementRepository();

  @override
  void initState() {
    super.initState();
    _busFrequencySession =
        widget.sessionStore?.busFrequency ?? BusFrequencyDashboardSession();
    _routeStopSession =
        widget.sessionStore?.routeStop ?? RouteStopDashboardSession();
    _costSession = widget.sessionStore?.cost ?? CostDashboardSession();
    _busFrequencyCoordinator = widget.busFrequencyCoordinator;
    _routeStopCoordinator = widget.routeStopCoordinator;
    _costCoordinator = widget.costCoordinator;
    _managementRepository = widget.managementRepository;
    _preparationScheduler = _RecommendationPreparationScheduler(
      preparations: {
        _RecommendationFeature.busFrequency: () async {
          final period = busFrequencyAnalysisPeriod(now: widget.now);
          await _frequencyCoordinator.prepareSession(
            session: _busFrequencySession,
            startUtc: period.startUtc,
            endExclusiveUtc: period.endUtc,
          );
        },
        _RecommendationFeature.routeStops: () async {
          final period = routeStopAnalysisPeriod(now: widget.now);
          await _routeCoordinator.prepareSession(
            session: _routeStopSession,
            startUtc: period.startUtc,
            endExclusiveUtc: period.endUtc,
          );
        },
        _RecommendationFeature.cost: () async {
          final period = costAnalysisPeriod(now: widget.now);
          await _costCoordinatorValue.prepareSession(
            session: _costSession,
            startUtc: period.startUtc,
            endExclusiveUtc: period.endUtc,
            referenceDate: period.referenceDate,
          );
        },
      },
      prepared: {
        _RecommendationFeature.busFrequency: () =>
            _busFrequencySession.screeningComplete &&
            (widget.sessionStore != null ||
                _busFrequencySession.matchesPeriod(
                  busFrequencyAnalysisPeriod(now: widget.now).startUtc,
                  busFrequencyAnalysisPeriod(now: widget.now).endUtc,
                )),
        _RecommendationFeature.routeStops: () =>
            _routeStopSession.screeningComplete &&
            (widget.sessionStore != null ||
                _routeStopSession.matchesPeriod(
                  routeStopAnalysisPeriod(now: widget.now).startUtc,
                  routeStopAnalysisPeriod(now: widget.now).endUtc,
                )),
        _RecommendationFeature.cost: () {
          final period = costAnalysisPeriod(now: widget.now);
          return (_costSession.screeningComplete ||
                  (widget.sessionStore != null &&
                      _costSession.hasRetainedCompletedState)) &&
              (widget.sessionStore != null ||
                  _costSession.matchesPeriod(
                    period.startUtc,
                    period.endUtc,
                    period.referenceDate,
                  ));
        },
      },
    );
    unawaited(_loadSummary());
    unawaited(_loadRoutes());
  }

  Future<void> _loadRoutes() async {
    try {
      final repository = widget.routeRepository ?? DefaultRoutePerformanceRepository();
      final routes = await repository.loadRoutes();
      if (mounted) setState(() => _routeCount = routes.length);
    } on Object {}
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final records = await _managementRepositoryValue.loadSavedRecommendations();
      if (mounted) setState(() => _records = records);
    } on Object {
      if (mounted) {
        setState(() {
          _records = null;
          _loadFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(WidgetBuilder builder) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
    if (mounted) await _loadSummary();
  }

  void _openBusFrequency() => _open((_) =>
    widget.busFrequencyPageBuilder?.call(_busFrequencySession) ??
    BusFrequencyRecommendationPage(
      session: _busFrequencySession,
      coordinator: _frequencyCoordinator,
      now: widget.now,
      preparationScheduler: () => _preparationScheduler.request(
        _RecommendationFeature.busFrequency,
      ),
      managementRepository: _managementRepositoryValue,
      preserveRetainedSession: widget.sessionStore != null,
    ),
  );

  void _openRouteStops() => _open((_) =>
    widget.routeStopPageBuilder?.call(_routeStopSession) ??
    RouteBusStopRecommendationPage(
      session: _routeStopSession,
      coordinator: _routeCoordinator,
      now: widget.now,
      preparationScheduler: () => _preparationScheduler.request(
        _RecommendationFeature.routeStops,
      ),
      managementRepository: _managementRepositoryValue,
      preserveRetainedSession: widget.sessionStore != null,
    ),
  );

  void _openCost() => _open((_) =>
    widget.costPageBuilder?.call(_costSession) ??
    CostEstimationReportPage(
      session: _costSession,
      coordinator: _costCoordinatorValue,
      preparationScheduler: () => _preparationScheduler.request(
        _RecommendationFeature.cost,
      ),
      busFrequencySession: _busFrequencySession,
      now: widget.now,
      preserveRetainedSession: widget.sessionStore != null,
    ),
  );

  void _openManagement() => _open((_) =>
    widget.managementPageBuilder?.call(_managementRepositoryValue) ??
    RecommendationManagementPage(repository: _managementRepositoryValue),
  );

  String? get _busState {
    final result = _busFrequencySession.recommendationResult;
    if (result?.status == BusFrequencyRecommendationStatus.available &&
        ((result?.synthesis?.routeRecommendations.isNotEmpty ?? false) ||
            (result?.synthesis?.recommendationGroups.any(
              (group) => group.routeRecommendations.isNotEmpty,
            ) ?? false))) {
      return 'Result Available';
    }
    if (_busFrequencySession.screeningComplete) {
      if (_busFrequencySession.candidates.isNotEmpty) return 'Evidence Ready';
      if (_busFrequencySession.routesAnalysed > 0) return 'Screening Available';
    }
    return null;
  }

  String? get _routeState {
    final result = _routeStopSession.recommendationResult;
    if (result?.status == RouteStopRecommendationStatus.available &&
        ((result?.synthesis?.routeRecommendations.isNotEmpty ?? false) ||
            (result?.synthesis?.recommendationGroups.any(
              (group) => group.routeIds.isNotEmpty,
            ) ?? false))) {
      return 'Result Available';
    }
    if (_routeStopSession.screeningComplete) {
      if (_routeStopSession.candidates.isNotEmpty) return 'Evidence Ready';
      if (_routeStopSession.routesAnalysed > 0) return 'Screening Available';
    }
    return null;
  }

  String? get _costState {
    if (_costSession.hasRetainedCompletedState) {
      if (_costSession.calculatedPlanningContext != null) {
        return 'Calculation Available';
      }
      if (_costSession.entries.any((entry) =>
          entry.result.status == CostRecommendationStatus.available &&
          entry.result.recommendation != null)) {
        return 'Result Available';
      }
    }
    if (_costSession.screeningComplete && _costSession.candidates.isNotEmpty) {
      return 'Evidence Ready';
    }
    return null;
  }

  int get _pendingCount => _records!.where((record) =>
      record.status == RecommendationReviewStatus.pending).length;

  int get _highCount => _records!.where((record) =>
      record.priorityLevel == RecommendationPriorityLevel.high).length;

  String? _savedFor(RecommendationManagementFeature feature) {
    final records = _records;
    if (records == null) return null;
    final count = records.where((record) => record.feature == feature).length;
    return '$count saved ${count == 1 ? 'recommendation' : 'recommendations'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCurrent = _busState != null || _routeState != null || _costState != null;

    return Scaffold(
      appBar: widget.showPageHeader
          ? readableAppBar(context, title: const Text('AI Recommendation Dashboard'))
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('AI Transit Recommendation',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Analyse transit operations and manage planning recommendations.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _summary(hasCurrent),
                  if (hasCurrent) ...[
                    const SizedBox(height: 24),
                    Text('Current Analysis', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      if (_busState != null)
                        _ResumeAnalysis(label: 'Bus Frequency', status: _busState!, onTap: _openBusFrequency),
                      if (_routeState != null)
                        _ResumeAnalysis(label: 'Route & Bus Stop', status: _routeState!, onTap: _openRouteStops),
                      if (_costState != null)
                        _ResumeAnalysis(label: 'Cost Estimation', status: _costState!, onTap: _openCost),
                    ]),
                  ],
                  const SizedBox(height: 24),
                  Text('Analysis & Management', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 600;
                    final cards = [
                      _FunctionCard(
                        compact: !twoColumns,
                        icon: Icons.schedule,
                        title: 'Bus Frequency Recommendation',
                        description: 'Review service frequency and identify routes for planning adjustments.',
                        status: _busState ?? 'Ready to analyse',
                        detail: _savedFor(RecommendationManagementFeature.busFrequency),
                        action: 'Open Analysis',
                        onTap: _openBusFrequency,
                      ),
                      _FunctionCard(
                        compact: !twoColumns,
                        icon: Icons.alt_route,
                        title: 'Route & Bus Stop Recommendation',
                        description: 'Review route coverage, stop suitability, and network improvements.',
                        status: _routeState ?? 'Ready to analyse',
                        detail: _savedFor(RecommendationManagementFeature.routeBusStop),
                        action: 'Open Analysis',
                        onTap: _openRouteStops,
                      ),
                      _FunctionCard(
                        compact: !twoColumns,
                        icon: Icons.request_quote_outlined,
                        title: 'Cost Estimation Report',
                        description: 'Estimate planning costs and review resource assumptions for recommendations.',
                        status: _costState ?? 'Ready to estimate',
                        action: 'Open Cost Estimation',
                        onTap: _openCost,
                      ),
                      _FunctionCard(
                        compact: !twoColumns,
                        icon: Icons.bookmarks_outlined,
                        title: 'Recommendation Management',
                        description: 'Save, review, and manage generated AI recommendations.',
                        status: _records == null
                            ? 'Review saved planning recommendations'
                            : '${_records!.length} saved recommendations',
                        detail: _records?.isNotEmpty == true
                            ? '$_pendingCount pending review / $_highCount high priority'
                            : null,
                        action: 'Open Management',
                        onTap: _openManagement,
                      ),
                    ];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < cards.length;
                            index += twoColumns ? 2 : 1) ...[
                          if (index > 0) const SizedBox(height: 16),
                          if (twoColumns)
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: cards[index]),
                                  const SizedBox(width: 16),
                                  Expanded(child: cards[index + 1]),
                                ],
                              ),
                            )
                          else
                            cards[index],
                        ],
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(bool hasCurrent) {
    final theme = Theme.of(context);
    final records = _records;
    final hasSaved = records != null && records.isNotEmpty;
    final metrics = [
      if (hasSaved) ...[
        _SummaryMetric(icon: Icons.bookmarks_outlined,
          label: 'Saved Recommendations', value: '${records.length}'),
        _SummaryMetric(icon: Icons.pending_actions,
          label: 'Pending Review', value: '$_pendingCount'),
        _SummaryMetric(icon: Icons.flag_outlined,
          label: 'High Priority', value: '$_highCount'),
      ] else ...[
        if (_routeCount != null)
          _SummaryMetric(icon: Icons.alt_route,
            label: 'Routes Available', value: '$_routeCount'),
        const _SummaryMetric(icon: Icons.analytics_outlined,
          label: 'Analysis Tools', value: '3'),
        if (records != null)
          const _SummaryMetric(icon: Icons.bookmarks_outlined,
            label: 'Saved Recommendations', value: '0'),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Planning Overview', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(child: metrics[index]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 3,
          child: _loading ? const LinearProgressIndicator() : null),
        if (_loadFailed) ...[
          const SizedBox(height: 12),
          const Text('Saved recommendations are unavailable. All analysis tools remain accessible.'),
          Align(alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _loadSummary, child: const Text('Retry summary')),
          ),
        ] else if (_loading) ...[
          const SizedBox(height: 12),
          const Text('Loading saved recommendations...'),
        ],
        if (!hasSaved && !hasCurrent) ...[
          const SizedBox(height: 16),
          Text('Ready to analyse your transit network.', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text('Choose Bus Frequency, Route & Bus Stop, or Cost Estimation to get started.'),
        ],
      ],
    );
  }

}

enum _RecommendationFeature { busFrequency, routeStops, cost }

class _RecommendationPreparationScheduler {
  _RecommendationPreparationScheduler({
    required this.preparations,
    required this.prepared,
  });

  final Map<_RecommendationFeature, Future<void> Function()> preparations;
  final Map<_RecommendationFeature, bool Function()> prepared;
  final List<_RecommendationFeature> _queue = [];
  final Map<_RecommendationFeature, Completer<void>> _pending = {};
  _RecommendationFeature? _running;

  Future<void> request(_RecommendationFeature feature) {
    return _schedule(feature, userPriority: true);
  }

  Future<void> _schedule(
    _RecommendationFeature feature, {
    required bool userPriority,
  }) {
    if (prepared[feature]!()) return Future<void>.value();
    final existing = _pending[feature];
    if (existing != null) {
      if (userPriority && _running != feature) {
        _queue.remove(feature);
        _queue.insert(0, feature);
      }
      return existing.future;
    }
    final completer = Completer<void>();
    _pending[feature] = completer;
    if (userPriority) {
      _queue.insert(0, feature);
    } else {
      _queue.add(feature);
    }
    _pump();
    return completer.future;
  }

  void _pump() {
    if (_running != null || _queue.isEmpty) return;
    final feature = _queue.removeAt(0);
    final completer = _pending[feature];
    if (completer == null) {
      _pump();
      return;
    }
    _running = feature;
    () async {
      try {
        await preparations[feature]!();
      } on Object {}
      if (!completer.isCompleted) completer.complete();
      _pending.remove(feature);
      _running = null;
      _pump();
    }();
  }
}

class _FunctionCard extends StatelessWidget {
  const _FunctionCard({
    required this.compact,
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.action,
    required this.onTap,
    this.detail,
  });

  final bool compact;
  final IconData icon;
  final String title;
  final String description;
  final String status;
  final String? detail;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        customBorder: theme.cardTheme.shape ?? RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 24, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ))),
                ]),
                const SizedBox(height: 12),
                Text(description, style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
                const Divider(height: 28),
                Text(status, style: theme.textTheme.labelLarge),
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(detail!, style: theme.textTheme.bodySmall),
                ],
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Align(alignment: Alignment.centerLeft,
                  child: FilledButton(onPressed: onTap,
                    child: Text(action, textAlign: TextAlign.center),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('planning-metric-$label'),
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Column(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            )),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeAnalysis extends StatelessWidget {
  const _ResumeAnalysis({required this.label, required this.status, required this.onTap});
  final String label;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, textAlign: TextAlign.center),
        Text(status, textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ]),
    ),
  );
}
