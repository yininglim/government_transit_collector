import 'package:flutter/material.dart';
import '../../ai_transit_recommendation/data/ai_recommendation_analysis_session_store.dart';
import '../../ai_transit_recommendation/data/recommendation_management_models.dart';
import '../../ai_transit_recommendation/data/recommendation_management_repository.dart';
import '../../ai_transit_recommendation/data/recommendation_priority.dart';
import '../../ai_transit_recommendation/presentation/bus_frequency_recommendation_page.dart';
import '../../ai_transit_recommendation/presentation/route_bus_stop_recommendation_page.dart';
import '../../ai_transit_recommendation/presentation/cost_estimation_report_page.dart';
import '../../ai_transit_recommendation/presentation/recommendation_management_page.dart';
import '../../route_performance/data/route_performance_repository.dart';

class AiRecommendationHomeCard extends StatefulWidget {
  const AiRecommendationHomeCard({
    required this.sessionStore,
    required this.onOpenAnalysis,
    this.repository,
    this.routeRepository,
    this.active = true,
    this.pageBuilder,
    super.key,
  });

  final AiRecommendationAnalysisSessionStore sessionStore;
  final VoidCallback onOpenAnalysis;
  final RecommendationManagementRepository? repository;
  final RoutePerformanceRepository? routeRepository;
  final bool active;
  final Widget Function(Widget page)? pageBuilder;

  @override
  State<AiRecommendationHomeCard> createState() => _AiRecommendationHomeCardState();
}

class _AiRecommendationHomeCardState extends State<AiRecommendationHomeCard> {
  late final RecommendationManagementRepository _repository;
  List<SavedRecommendation>? _records;
  int? _routes;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? DefaultRecommendationManagementRepository();
    _load();
    _loadRoutes();
  }

  @override
  void didUpdateWidget(covariant AiRecommendationHomeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  Future<void> _loadRoutes() async {
    try {
      final repository =
          widget.routeRepository ?? DefaultRoutePerformanceRepository();
      final routes = await repository.loadRoutes();
      if (mounted) setState(() => _routes = routes.length);
    } on Object {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final records = [...await _repository.loadSavedRecommendations()];
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (mounted) setState(() => _records = records);
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _records = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(int index) async {
    final store = widget.sessionStore;
    final Widget page = switch (index) {
      0 => BusFrequencyRecommendationPage(
        session: store.busFrequency,
        preserveRetainedSession: true,
        managementRepository: _repository,
      ),
      1 => RouteBusStopRecommendationPage(
        session: store.routeStop,
        preserveRetainedSession: true,
        managementRepository: _repository,
      ),
      2 => CostEstimationReportPage(
        session: store.cost,
        busFrequencySession: store.busFrequency,
        preserveRetainedSession: true,
      ),
      _ => RecommendationManagementPage(repository: _repository),
    };
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => widget.pageBuilder?.call(page) ?? page,
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = widget.sessionStore;
    final available = [
      store.busFrequency.screeningComplete &&
          (store.busFrequency.routesAnalysed > 0 ||
              store.busFrequency.candidates.isNotEmpty ||
              store.busFrequency.recommendationResult != null),
      store.routeStop.screeningComplete &&
          (store.routeStop.routesAnalysed > 0 ||
              store.routeStop.candidates.isNotEmpty ||
              store.routeStop.recommendationResult != null),
      store.cost.hasRetainedCompletedState ||
          (store.cost.screeningComplete && store.cost.candidates.isNotEmpty),
    ];
    const labels = [
      'Bus Frequency',
      'Route & Bus Stop',
      'Cost Estimation',
      'Recommendation Management',
    ];
    const icons = [
      Icons.schedule,
      Icons.alt_route,
      Icons.request_quote_outlined,
      Icons.bookmarks_outlined,
    ];
    final records = _records;
    final saved = records != null && records.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.auto_awesome_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text('AI Transit Recommendation', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 8),
          Text('Review planning recommendations, priorities, and analysis.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: widget.onOpenAnalysis,
              icon: const Icon(Icons.chevron_right),
              label: const Text('Open AI Analysis'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 4, child: _loading ? const LinearProgressIndicator() : null),
          const SizedBox(height: 16),
          Wrap(spacing: 28, runSpacing: 16, children: [
            if (saved) ...[
              _Metric(label: 'Saved Recommendations', value: '${records.length}'),
              _Metric(label: 'Pending Review', value: '${records.where((r) => r.status == RecommendationReviewStatus.pending).length}'),
              _Metric(label: 'High Priority', value: '${records.where((r) => r.priorityLevel == RecommendationPriorityLevel.high).length}'),
            ] else ...[
              if (_routes != null) _Metric(label: 'Routes Available', value: '$_routes'),
              const _Metric(label: 'Analysis Functions', value: '3'),
              if (records != null) const _Metric(label: 'Saved Recommendations', value: '0'),
            ],
          ]),
          if (_failed) ...[
            const SizedBox(height: 12),
            const Text('Saved recommendations are unavailable. You can still open any analysis function.'),
          ],
          if (!saved && !available.contains(true)) ...[
            const SizedBox(height: 16),
            Text('Ready to analyse your transit network.', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text('Choose an analysis function to get started.'),
          ],
          if (available.contains(true)) ...[
            const Divider(height: 28),
            Text('Resume Analysis', style: theme.textTheme.titleSmall),
            Wrap(spacing: 12, runSpacing: 4, children: [
              for (var i = 0; i < 3; i++)
                if (available[i]) TextButton(onPressed: () => _open(i), child: Text('${labels[i]}: Analysis Available')),
            ]),
          ],
          if (saved) ...[
            const Divider(height: 28),
            Text('Latest Recommendation', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(_routeLabel(records.first), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(records.first.actions.isEmpty ? records.first.title : records.first.actions.map(recommendationActionLabel).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(_priorityLabel(records.first.priorityLevel), style: theme.textTheme.labelMedium?.copyWith(color: records.first.priorityLevel == RecommendationPriorityLevel.high ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              Text(recommendationStatusLabel(records.first.status), style: theme.textTheme.labelMedium),
              Text(recommendationFeatureLabel(records.first.feature), style: theme.textTheme.bodySmall),
            ]),
          ],
          const Divider(height: 28),
          Text('Quick Access', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < labels.length; i++)
                SizedBox(width: width, child: OutlinedButton(onPressed: () => _open(i), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icons[i], size: 20), const SizedBox(height: 6), Text(labels[i], textAlign: TextAlign.center)]))),
            ]);
          }),
        ]),
      ),
    );
  }
}

String _routeLabel(SavedRecommendation record) {
  for (final value in [record.routeDisplayLabel, record.routeId, record.title]) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return 'Network recommendation';
}

String _priorityLabel(RecommendationPriorityLevel? level) => switch (level) {
  RecommendationPriorityLevel.high => 'High Priority',
  RecommendationPriorityLevel.medium => 'Medium Priority',
  RecommendationPriorityLevel.low => 'Low Priority',
  null => 'Not Ranked',
};

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: Theme.of(context).textTheme.headlineSmall),
    Text(label, style: Theme.of(context).textTheme.bodySmall),
  ]);
}
