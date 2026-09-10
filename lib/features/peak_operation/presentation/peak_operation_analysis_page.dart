import 'package:government_transit_collector/core/widgets/readable_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_calculator.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_repository.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report_repository.dart';
import 'package:timezone/timezone.dart' as timezone;

enum PeakAnalysisPeriod { today, lastSevenDays, custom }

class PeakOperationAnalysisPage extends StatefulWidget {
  const PeakOperationAnalysisPage({
    this.repository,
    this.savedReportRepository,
    this.now,
    this.showPageHeader = true,
    super.key,
  });
  final PeakOperationRepository? repository;
  final SavedOperationalReportRepository? savedReportRepository;
  final DateTime Function()? now;
  final bool showPageHeader;

  @override
  State<PeakOperationAnalysisPage> createState() =>
      _PeakOperationAnalysisState();
}

class _PeakOperationAnalysisState extends State<PeakOperationAnalysisPage> {
  late final PeakOperationRepository _repository;
  SavedOperationalReportRepository? _savedReportRepository;
  final _calculator = const PeakOperationCalculator();
  List<PeakOperationRoute> _routes = const [];
  String? _routeId;
  PeakAnalysisPeriod _period = PeakAnalysisPeriod.today;
  DateTime? _customStart;
  DateTime? _customEnd;
  PeakOperationSummary? _summary;
  DateTime? _updated;
  bool _loading = true;
  bool _refreshing = false;
  bool _savingReport = false;
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? DefaultPeakOperationRepository();
    _savedReportRepository = widget.savedReportRepository;
    _reloadAvailability();
  }

  Future<void> _reloadAvailability() async {
    final generation = ++_requestGeneration;
    setState(() {
      _refreshing = _summary != null;
      _loading = _summary == null;
      _error = null;
    });
    final range = _range();
    try {
      final routes = _repository is PeriodPeakOperationRepository
          ? await (_repository as PeriodPeakOperationRepository)
                .loadRoutesWithObservations(
                  startUtc: range.start,
                  endExclusiveUtc: range.end,
                )
          : await _repository.loadRoutes();
      if (!mounted || generation != _requestGeneration) return;
      final previousRouteId = _routeId;
      final nextRouteId =
          routes.any((route) => route.routeId == previousRouteId)
          ? previousRouteId
          : null;
      final keepSummary =
          _summary != null &&
          nextRouteId == previousRouteId &&
          routes.isNotEmpty;
      setState(() {
        _routes = routes;
        _routeId = nextRouteId;
        if (!keepSummary) _summary = null;
        _loading = routes.isNotEmpty && !keepSummary;
      });
      if (routes.isEmpty) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _updated = currentTransitServiceDateTime(now: widget.now);
        });
        return;
      }
      await _loadObservations(
        range: range,
        routeId: nextRouteId,
        generation: generation,
      );
    } on Object catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = error.toString();
      });
    }
  }

  ({DateTime start, DateTime end, String label}) _range() {
    final now = currentTransitServiceDateTime(now: widget.now);
    final today = timezone.TZDateTime(
      transitServiceLocation,
      now.year,
      now.month,
      now.day,
    );
    late timezone.TZDateTime start;
    late timezone.TZDateTime end;
    switch (_period) {
      case PeakAnalysisPeriod.today:
        start = today;
        end = today.add(const Duration(days: 1));
      case PeakAnalysisPeriod.lastSevenDays:
        start = today.subtract(const Duration(days: 6));
        end = today.add(const Duration(days: 1));
      case PeakAnalysisPeriod.custom:
        final first = _customStart ?? DateTime(now.year, now.month, now.day);
        final last = _customEnd ?? first;
        start = timezone.TZDateTime(
          transitServiceLocation,
          first.year,
          first.month,
          first.day,
        );
        end = timezone.TZDateTime(
          transitServiceLocation,
          last.year,
          last.month,
          last.day + 1,
        );
    }
    return (
      start: start.toUtc(),
      end: end.toUtc(),
      label:
          '${_date(start)} – ${_date(end.subtract(const Duration(days: 1)))}',
    );
  }

  Future<void> _loadObservations({
    ({DateTime start, DateTime end, String label})? range,
    String? routeId,
    int? generation,
  }) async {
    final requestGeneration = generation ?? ++_requestGeneration;
    final selectedRange = range ?? _range();
    final selectedRouteId = generation == null ? _routeId : routeId;
    if (generation == null) {
      setState(() {
        _refreshing = _summary != null;
        _loading = _summary == null;
        _error = null;
      });
    }
    try {
      final observations = await _repository.loadObservations(
        startUtc: selectedRange.start,
        endExclusiveUtc: selectedRange.end,
        routeId: selectedRouteId,
      );
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _summary = _calculator.calculate(
          observations: observations,
          periodStart: selectedRange.start,
          periodEnd: selectedRange.end,
          routeId: selectedRouteId,
        );
        _updated = currentTransitServiceDateTime(now: widget.now);
        _loading = false;
        _refreshing = false;
      });
    } on Object catch (error) {
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = error.toString();
      });
    }
  }

  Future<bool> _customDates() async {
    final now = currentTransitServiceDateTime(now: widget.now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(
        start: _customStart ?? DateTime(now.year, now.month, now.day),
        end: _customEnd ?? DateTime(now.year, now.month, now.day),
      ),
    );
    if (range == null) return false;
    setState(() {
      _customStart = range.start;
      _customEnd = range.end;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.showPageHeader
        ? readableAppBar(context, title: const Text('Peak Operation Analysis'))
        : null,
    body: SafeArea(
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(),
              const SizedBox(height: 16),
              _filters(),
              if (_period == PeakAnalysisPeriod.custom) ...[
                const SizedBox(height: 8),
                Text('Selected period: ${_range().label}'),
              ],
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _summary == null)
                _errorState()
              else
                _content(),
            ],
          ),
          if (_refreshing)
            const LinearProgressIndicator(key: Key('peak-refresh-progress')),
        ],
      ),
    ),
  );

  Widget _header() => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Observed bus operational activity',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _updated == null
                  ? 'Not refreshed yet'
                  : 'Updated ${_time(_updated!)}',
              key: const Key('peak-updated-time'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      IconButton.filledTonal(
        tooltip: 'Refresh',
        onPressed: _loading || _refreshing ? null : _reloadAvailability,
        icon: const Icon(Icons.refresh),
      ),
    ],
  );

  Widget _filters() => LayoutBuilder(
    builder: (context, constraints) {
      final scope = KeyedSubtree(
        key: const Key('peak-scope-selector'),
        child: DropdownButtonFormField<String?>(
              itemHeight: null,
              isDense: false,
          key: ValueKey('peak-scope-${_routeId ?? 'all'}-${_routes.length}'),
          initialValue: _routeId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Scope',
            prefixIcon: Icon(Icons.route),
            border: OutlineInputBorder(),
          ),
          hint: const Text('No routes with data'),
          items: _routes.isEmpty
              ? const []
              : [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Routes'),
                  ),
                  ..._routes.map(
                    (route) => DropdownMenuItem<String?>(
                      value: route.routeId,
                      child: Text(
                        route.displayName,
                      ),
                    ),
                  ),
                ],
          onChanged: _routes.isEmpty
              ? null
              : (value) {
                  setState(() {
                    _routeId = value;
                    _summary = null;
                  });
                  _loadObservations();
                },
        ),
      );
      final periods = SegmentedButton<PeakAnalysisPeriod>(
        segments: const [
          ButtonSegment(value: PeakAnalysisPeriod.today, label: Text('Today')),
          ButtonSegment(
            value: PeakAnalysisPeriod.lastSevenDays,
            label: Text('7 Days'),
          ),
          ButtonSegment(
            value: PeakAnalysisPeriod.custom,
            label: Text('Custom'),
          ),
        ],
        selected: {_period},
        onSelectionChanged: (selection) async {
          final previous = _period;
          setState(() => _period = selection.first);
          if (_period == PeakAnalysisPeriod.custom) {
            final selected = await _customDates();
            if (!selected) {
              if (mounted) setState(() => _period = previous);
              return;
            }
          }
          await _reloadAvailability();
        },
      );
      if (constraints.maxWidth < 720) {
        return Column(
          children: [
            scope,
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: periods,
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: scope),
          const SizedBox(width: 16),
          periods,
        ],
      );
    },
  );

  Widget _content() {
    if (_routes.isEmpty) return _periodEmptyState();
    final summary = _summary!;
    if (!summary.hasData) return _emptyState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.hasReliablePeak)
          _summaryCards(summary)
        else
          _limitedState(summary),
        if (summary.hasReliablePeak) ...[
          const SizedBox(height: 12),
          _saveReportSection(summary),
        ],
        const SizedBox(height: 12),
        _activityChart(summary),
        if (summary.dailyActivity.length > 1) ...[
          const SizedBox(height: 12),
          _dailySummary(summary),
        ],
        const SizedBox(height: 12),
        _insight(summary),
        const SizedBox(height: 12),
        _coverage(summary),
        const SizedBox(height: 12),
        _gtfsWarning(),
      ],
    );
  }

  Widget _saveReportSection(PeakOperationSummary summary) => Card(
    key: const Key('peak-operation-save-section'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final description = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Save operational report',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Preserve the displayed analysis as a historical snapshot.',
              ),
            ],
          );
          final button = FilledButton.icon(
            key: const Key('save-peak-operation-report'),
            onPressed: _refreshing || _savingReport || _error != null
                ? null
                : () => _showSaveReportDialog(summary),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save Report'),
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                description,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: button),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: description),
              const SizedBox(width: 16),
              button,
            ],
          );
        },
      ),
    ),
  );

  Future<void> _showSaveReportDialog(PeakOperationSummary summary) async {
    if (_savingReport) return;
    final routeId = _routeId;
    final routeName = routeId == null ? 'All Routes' : _routeName(routeId);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SavePeakOperationDialog(
        defaultTitle:
            '${routeId == null ? 'All Routes' : _routeShortName(routeId)} '
            'Peak Operation - ${_periodLabel()}',
        onSave: ({required title, required adminNotes}) async {
          setState(() => _savingReport = true);
          try {
            final repository = _savedReportRepository ??=
                DefaultSavedOperationalReportRepository();
            await repository.createPeakOperationReport(
              routeId: routeId,
              routeNameSnapshot: routeName,
              periodStart: summary.periodStart,
              periodEnd: summary.periodEnd,
              title: title,
              adminNotes: adminNotes,
              resultSnapshot: _snapshot(summary),
            );
          } finally {
            if (mounted) setState(() => _savingReport = false);
          }
        },
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Peak Operation report saved.')),
      );
    }
  }

  String _periodLabel() => switch (_period) {
    PeakAnalysisPeriod.today => 'Today',
    PeakAnalysisPeriod.lastSevenDays => '7 Days',
    PeakAnalysisPeriod.custom => 'Custom',
  };

  String _routeShortName(String routeId) {
    final route = _routes.where((item) => item.routeId == routeId).firstOrNull;
    final shortName = route?.shortName?.trim() ?? '';
    return shortName.isEmpty ? route?.displayName ?? routeId : shortName;
  }

  Map<String, dynamic> _snapshot(PeakOperationSummary summary) {
    final peak = summary.peakBucket!;
    final busiest = summary.busiestRoute;
    return {
      'peak_period': _bucketLabel(peak),
      'peak_bucket_start_minute': peak.startMinute,
      'peak_bucket_end_minute': peak.endMinute,
      'peak_average_active_trips': peak.averageActiveTrips,
      'peak_activity_level': peak.level.name,
      'average_activity': summary.averageActivity,
      'activity_difference_percent': summary.activityDifferencePercent,
      'has_reliable_peak': summary.hasReliablePeak,
      'has_limited_coverage': summary.hasLimitedCoverage,
      'total_observations': summary.observationCount,
      'distinct_trip_occurrences': summary.distinctTripOccurrences,
      'populated_bucket_count': summary.bucketBreakdown.length,
      'observed_day_count': summary.observedDayCount,
      'routes_represented': summary.routesRepresented,
      'observed_window_start': summary.observedWindowStart?.toIso8601String(),
      'observed_window_end': summary.observedWindowEnd?.toIso8601String(),
      if (busiest != null) ...{
        'busiest_route_id': busiest.routeId,
        'busiest_route_name': _routeName(busiest.routeId),
        'busiest_route_trip_occurrences': busiest.tripOccurrences,
      },
    };
  }

  Widget _summaryCards(PeakOperationSummary summary) {
    final peak = summary.peakBucket!;
    final cards = <Widget>[
      _metric('Peak Period', _bucketLabel(peak), Icons.access_time_filled),
      _metric(
        'Average Active Trips',
        _number(peak.averageActiveTrips),
        Icons.directions_bus_filled,
      ),
      _metric('Observed Service Window', _window(summary), Icons.timeline),
      if (_routeId == null)
        _metric(
          'Busiest Observed Route',
          _routeName(summary.busiestRoute?.routeId),
          Icons.emoji_events_outlined,
        )
      else
        _metric(
          'Peak Activity',
          '${_number(peak.averageActiveTrips)} active trips',
          Icons.trending_up,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 800
            ? (constraints.maxWidth - 36) / 4
            : constraints.maxWidth >= 500
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(),
        );
      },
    );
  }

  Widget _metric(String title, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.onPrimaryContainer),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityChart(PeakOperationSummary summary) {
    final maximum = summary.bucketBreakdown.fold<double>(
      0,
      (max, bucket) =>
          bucket.averageActiveTrips > max ? bucket.averageActiveTrips : max,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Operational Activity by Time', Icons.bar_chart),
            const SizedBox(height: 4),
            const Text(
              'Average distinct active trip occurrences per observed day',
            ),
            const SizedBox(height: 16),
            ...summary.bucketBreakdown.map(
              (bucket) => _activityBar(bucket, maximum),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityBar(OperationTimeBucket bucket, double maximum) {
    final scheme = Theme.of(context).colorScheme;
    final color = bucket.level == ActivityLevel.high
        ? scheme.primary
        : bucket.level == ActivityLevel.moderate
        ? scheme.secondary
        : scheme.outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(_bucketLabel(bucket).split(' – ').first),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: maximum == 0 ? 0 : bucket.averageActiveTrips / maximum,
              color: color,
              minHeight: 12,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 68,
            child: Text(
              '${_number(bucket.averageActiveTrips)} ${_level(bucket.level)}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _dailySummary(PeakOperationSummary summary) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Daily Activity', Icons.calendar_view_week),
          const SizedBox(height: 12),
          ...summary.dailyActivity.map(
            (day) => ListTile(
              dense: true,
              title: Text(_date(day.date)),
              subtitle: Text(
                '${day.tripOccurrences} observed trip occurrences',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _insight(PeakOperationSummary summary) {
    final peak = summary.peakBucket;
    final scope = _routeId == null ? 'The network' : _routeName(_routeId);
    final text = peak == null
        ? 'More distinct trip coverage is needed before a reliable peak operational period can be identified.'
        : '$scope shows its highest observed service activity during ${_bucketLabel(peak)}. '
              'Activity is ${summary.activityDifferencePercent.round()}% above the average observed time bucket. '
              'Review whether scheduled frequency is adequate during this period.';
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.lightbulb_outline),
        title: const Text('Operational Insight'),
        subtitle: Text(text),
      ),
    );
  }

  Widget _coverage(PeakOperationSummary summary) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Historical Coverage', Icons.data_usage),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat('Observations Used', summary.observationCount),
              _stat('Trip Occurrences', summary.distinctTripOccurrences),
              _stat('Observed Days', summary.observedDayCount),
              _stat('Routes Represented', summary.routesRepresented),
            ],
          ),
          const Divider(height: 24),
          Text('Period  ${_range().label}'),
          if (summary.hasLimitedCoverage)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Coverage is limited and may not represent typical daily operations.',
              ),
            ),
        ],
      ),
    ),
  );

  Widget _stat(String label, int value) => Container(
    constraints: const BoxConstraints(minWidth: 130),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  Widget _gtfsWarning() => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: const ListTile(
      leading: Icon(Icons.sync_problem_outlined),
      title: Text('Limited historical coverage'),
      subtitle: Text(
        'Some J30/J300 realtime trips could not be matched to the currently imported GTFS schedule. Missing records are not interpreted as low activity.',
      ),
    ),
  );

  Widget _limitedState(PeakOperationSummary summary) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.hourglass_empty, size: 42),
          const SizedBox(height: 8),
          Text(
            'Limited operational history',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '${summary.observationCount} observations are available, but there is not enough distinct trip coverage to identify a reliable peak period.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _emptyState() => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(Icons.query_stats, size: 52),
          const SizedBox(height: 8),
          Text(
            'No operational history',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'No historical realtime observations are available for this scope and period.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _periodEmptyState() => Card(
    key: const Key('no-operational-route-data'),
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(Icons.query_stats, size: 52),
          const SizedBox(height: 8),
          Text(
            'No operational history',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'No realtime observations are available for any route during this period.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Try another period or collect more historical data.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _errorState() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(_error ?? 'Unable to load peak operation analysis.'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _reloadAvailability,
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  Widget _title(String text, IconData icon) => Row(
    children: [
      Icon(icon),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      ),
    ],
  );

  String _routeName(String? id) => id == null
      ? 'Not available'
      : _routes
                .where((route) => route.routeId == id)
                .firstOrNull
                ?.displayName ??
            id;
  String _window(PeakOperationSummary summary) =>
      summary.observedWindowStart == null
      ? 'Not available'
      : '${_time(summary.observedWindowStart!)} – ${_time(summary.observedWindowEnd!)}';
}

class _SavePeakOperationDialog extends StatefulWidget {
  const _SavePeakOperationDialog({
    required this.defaultTitle,
    required this.onSave,
  });

  final String defaultTitle;
  final Future<void> Function({
    required String title,
    required String? adminNotes,
  })
  onSave;

  @override
  State<_SavePeakOperationDialog> createState() =>
      _SavePeakOperationDialogState();
}

class _SavePeakOperationDialogState extends State<_SavePeakOperationDialog> {
  late final TextEditingController _titleController;
  final _notesController = TextEditingController();
  String? _titleError;
  String? _saveError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.defaultTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Report title is required.');
      return;
    }
    final notes = _notesController.text.trim();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(
        title: title,
        adminNotes: notes.isEmpty ? null : notes,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save Peak Operation Report'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('save-peak-report-title'),
            controller: _titleController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Report Title',
              border: const OutlineInputBorder(),
              errorText: _titleError,
            ),
            onChanged: (_) {
              if (_titleError != null || _saveError != null) {
                setState(() {
                  _titleError = null;
                  _saveError = null;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('save-peak-report-notes'),
            controller: _notesController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Admin Notes (optional)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 12),
            Text(
              _saveError!,
              key: const Key('save-peak-report-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('confirm-save-peak-operation-report'),
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save Report'),
      ),
    ],
  );
}

String _bucketLabel(OperationTimeBucket bucket) =>
    '${_clock(bucket.startMinute)} – ${_clock(bucket.endMinute)}';
String _clock(int minute) {
  final hour24 = minute ~/ 60;
  final minutePart = minute % 60;
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour:${minutePart.toString().padLeft(2, '0')} ${hour24 >= 12 ? 'PM' : 'AM'}';
}

String _time(DateTime date) => _clock(date.hour * 60 + date.minute);
String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _number(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(1);
String _level(ActivityLevel level) => switch (level) {
  ActivityLevel.high => 'High',
  ActivityLevel.moderate => 'Moderate',
  ActivityLevel.low => 'Low',
};
