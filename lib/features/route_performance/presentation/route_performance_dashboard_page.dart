import 'package:government_transit_collector/core/widgets/readable_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_calculator.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report_repository.dart';
import 'package:timezone/timezone.dart' as timezone;

enum RoutePerformancePeriod { today, lastSevenDays, custom }

class RoutePerformanceDashboardPage extends StatefulWidget {
  const RoutePerformanceDashboardPage({
    this.repository,
    this.savedReportRepository,
    this.now,
    this.showPageHeader = true,
    super.key,
  });
  final RoutePerformanceRepository? repository;
  final SavedOperationalReportRepository? savedReportRepository;
  final DateTime Function()? now;

  final bool showPageHeader;

  @override
  State<RoutePerformanceDashboardPage> createState() => _DashboardState();
}

class _DashboardState extends State<RoutePerformanceDashboardPage> {
  final _calculator = const RoutePerformanceCalculator();
  late final RoutePerformanceRepository _repository;
  SavedOperationalReportRepository? _savedReportRepository;
  List<RoutePerformanceRoute> _routes = const [];
  RoutePerformanceRoute? _route;
  RoutePerformancePeriod _period = RoutePerformancePeriod.today;
  DateTime? _customStart;
  DateTime? _customEnd;
  DateTime? _lastUpdated;
  RoutePerformanceSummary? _summary;
  bool _loading = true;
  bool _refreshing = false;
  bool _showPartial = false;
  bool _savingReport = false;
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? DefaultRoutePerformanceRepository();
    _savedReportRepository = widget.savedReportRepository;
    _reloadAvailableRoutes();
  }

  Future<void> _reloadAvailableRoutes() async {
    final generation = ++_requestGeneration;
    setState(() {
      _refreshing = _summary != null;
      _loading = _summary == null;
      _error = null;
    });
    final range = _range();
    try {
      final routes = _repository is PeriodRoutePerformanceRepository
          ? await (_repository as PeriodRoutePerformanceRepository)
                .loadRoutesWithObservations(
                  startUtc: range.startUtc,
                  endExclusiveUtc: range.endUtc,
                )
          : await _repository.loadRoutes();
      if (!mounted || generation != _requestGeneration) return;
      final previousRouteId = _route?.routeId;
      final selected = routes
          .where((route) => route.routeId == previousRouteId)
          .firstOrNull;
      final nextRoute = selected ?? routes.firstOrNull;
      final keepSummary =
          _summary != null && nextRoute?.routeId == previousRouteId;
      setState(() {
        _routes = routes;
        _route = nextRoute;
        if (!keepSummary) _summary = null;
        _loading = nextRoute != null && !keepSummary;
        _showPartial = false;
      });
      if (_route == null) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _lastUpdated = currentTransitServiceDateTime(now: widget.now);
        });
        return;
      }
      await _loadSelectedRoute(
        route: _route!,
        range: range,
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

  ({DateTime startUtc, DateTime endUtc, String label}) _range() {
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
      case RoutePerformancePeriod.today:
        start = today;
        end = today.add(const Duration(days: 1));
      case RoutePerformancePeriod.lastSevenDays:
        start = today.subtract(const Duration(days: 6));
        end = today.add(const Duration(days: 1));
      case RoutePerformancePeriod.custom:
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
      startUtc: start.toUtc(),
      endUtc: end.toUtc(),
      label:
          '${_date(start)} – ${_date(end.subtract(const Duration(days: 1)))}',
    );
  }

  Future<void> _loadSelectedRoute({
    RoutePerformanceRoute? route,
    ({DateTime startUtc, DateTime endUtc, String label})? range,
    int? generation,
  }) async {
    final requestGeneration = generation ?? ++_requestGeneration;
    final selectedRoute = route ?? _route;
    if (selectedRoute == null) return;
    if (generation == null) {
      setState(() {
        _refreshing = _summary != null;
        _loading = _summary == null;
        _error = null;
      });
    }
    final selectedRange = range ?? _range();
    try {
      final data = await _repository.loadRoutePerformance(
        routeId: selectedRoute.routeId,
        startUtc: selectedRange.startUtc,
        endExclusiveUtc: selectedRange.endUtc,
      );
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _summary = _calculator.calculate(data);
        _lastUpdated = currentTransitServiceDateTime(now: widget.now);
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

  Future<bool> _chooseCustomDates() async {
    final local = currentTransitServiceDateTime(now: widget.now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(local.year, local.month, local.day),
      initialDateRange: DateTimeRange(
        start: _customStart ?? DateTime(local.year, local.month, local.day),
        end: _customEnd ?? DateTime(local.year, local.month, local.day),
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
        ? readableAppBar(context, title: const Text('Route Performance'))
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
              if (_period == RoutePerformancePeriod.custom) ...[
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
                _errorCard()
              else
                _content(),
            ],
          ),
          if (_refreshing)
            const LinearProgressIndicator(key: Key('refresh-progress')),
        ],
      ),
    ),
  );

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Based on collected realtime observations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _lastUpdated == null
                  ? 'Not refreshed yet'
                  : 'Updated ${_time(_lastUpdated!)}',
              key: const Key('updated-time'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      IconButton.filledTonal(
        tooltip: 'Refresh',
        onPressed: _loading || _refreshing ? null : _reloadAvailableRoutes,
        icon: const Icon(Icons.refresh),
      ),
    ],
  );

  Widget _filters() => LayoutBuilder(
    builder: (context, constraints) {
      final route = DropdownButtonFormField<RoutePerformanceRoute>(
              itemHeight: null,
              isDense: false,
        key: ValueKey('route-selector-${_route?.routeId}'),
        initialValue: _route,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Route',
          prefixIcon: Icon(Icons.route_outlined),
          border: OutlineInputBorder(),
        ),
        selectedItemBuilder: (_) => _routes
            .map(
              (item) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  item.shortName?.trim().isNotEmpty == true
                      ? item.shortName!
                      : item.displayName,
                ),
              ),
            )
            .toList(),
        items: _routes
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _routeLabel(item),
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            _route = value;
            _summary = null;
            _showPartial = false;
          });
          _loadSelectedRoute();
        },
      );
      final periods = SegmentedButton<RoutePerformancePeriod>(
        segments: const [
          ButtonSegment(
            value: RoutePerformancePeriod.today,
            label: Text('Today'),
          ),
          ButtonSegment(
            value: RoutePerformancePeriod.lastSevenDays,
            label: Text('7 Days'),
          ),
          ButtonSegment(
            value: RoutePerformancePeriod.custom,
            label: Text('Custom'),
          ),
        ],
        selected: {_period},
        onSelectionChanged: (value) async {
          final previous = _period;
          setState(() => _period = value.first);
          if (_period == RoutePerformancePeriod.custom) {
            final selected = await _chooseCustomDates();
            if (!selected) {
              if (mounted) setState(() => _period = previous);
              return;
            }
          }
          await _reloadAvailableRoutes();
        },
      );
      final routeSelector = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          route,
          if (_route?.longName?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                _route!.longName!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      );
      if (constraints.maxWidth < 720) {
        return Column(
          children: [
            routeSelector,
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
          Expanded(child: routeSelector),
          const SizedBox(width: 16),
          periods,
        ],
      );
    },
  );

  Widget _routeLabel(RoutePerformanceRoute route) => Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        route.shortName?.trim().isNotEmpty == true
            ? route.shortName!
            : route.displayName,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      if (route.longName?.trim().isNotEmpty == true)
        Text(
          route.longName!,
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );

  Widget _content() {
    if (_routes.isEmpty) return _noRoutesState();
    final summary = _summary;
    if (summary == null || summary.totalObservations == 0) return _emptyState();
    final complete = summary.completeTrips;
    if (complete.isEmpty) return _insufficientState(summary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metrics(summary),
        const SizedBox(height: 12),
        _coverageWarning(),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final coverage = _coverage(summary);
            final second = _delayBreakdown(summary);
            if (constraints.maxWidth >= 760) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: coverage),
                  const SizedBox(width: 12),
                  Expanded(child: second),
                ],
              );
            }
            return Column(
              children: [coverage, const SizedBox(height: 12), second],
            );
          },
        ),
        const SizedBox(height: 12),
        _saveReportSection(summary),
        if (complete.isNotEmpty) ...[
          _sectionTitle('Observed trip performance'),
          ...complete.map(_tripCard),
        ],
        if (summary.partialTripCount > 0) _partialSection(summary),
      ],
    );
  }

  Widget _saveReportSection(RoutePerformanceSummary summary) => Card(
    key: const Key('route-performance-save-section'),
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
            key: const Key('save-route-performance-report'),
            onPressed: _refreshing || _savingReport
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

  Future<void> _showSaveReportDialog(RoutePerformanceSummary summary) async {
    if (_savingReport || _route == null) return;
    final route = _route!;
    final range = _range();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaveRoutePerformanceDialog(
        defaultTitle:
            '${route.shortName?.trim().isNotEmpty == true ? route.shortName!.trim() : route.displayName} '
            'Route Performance - ${_periodLabel()}',
        onSave: ({required title, required adminNotes}) async {
          setState(() => _savingReport = true);
          try {
            final repository = _savedReportRepository ??=
                DefaultSavedOperationalReportRepository();
            await repository.createRoutePerformanceReport(
              routeId: route.routeId,
              routeNameSnapshot: route.displayName,
              periodStart: range.startUtc,
              periodEnd: range.endUtc,
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
        const SnackBar(content: Text('Route Performance report saved.')),
      );
    }
  }

  String _periodLabel() => switch (_period) {
    RoutePerformancePeriod.today => 'Today',
    RoutePerformancePeriod.lastSevenDays => '7 Days',
    RoutePerformancePeriod.custom => 'Custom',
  };

  Map<String, dynamic> _snapshot(RoutePerformanceSummary summary) {
    final tripsUsed = summary.completeTrips.length;
    return {
      'average_travel_time_minutes': summary.averageTravelTime!.inSeconds / 60,
      'delay_frequency_percent': summary.delayFrequencyPercent,
      'schedule_adherence_percent': summary.scheduleAdherencePercent,
      'total_observed_trip_occurrences': summary.trips.length,
      'trips_used_in_metrics': tripsUsed,
      'partial_trip_occurrences': summary.partialTripCount,
      'total_observations': summary.totalObservations,
      'delayed_trip_count': summary.delayedTripCount,
      'on_time_trip_count': tripsUsed - summary.delayedTripCount,
    };
  }

  Widget _metrics(RoutePerformanceSummary summary) {
    final scheme = Theme.of(context).colorScheme;
    final complete = summary.completeTrips.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth >= 560
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard(
              width: width,
              title: 'Average Travel Time',
              icon: Icons.schedule_outlined,
              value: summary.averageTravelTime == null
                  ? '—'
                  : _minutes(summary.averageTravelTime!),
              subtitle: 'Based on $complete observed trips',
              tint: scheme.primaryContainer,
              foreground: scheme.onPrimaryContainer,
            ),
            _metricCard(
              width: width,
              title: 'Delay Frequency',
              icon: Icons.warning_amber_rounded,
              value: summary.delayFrequencyPercent == null
                  ? '—'
                  : '${summary.delayFrequencyPercent!.round()}%',
              subtitle:
                  '${summary.delayedTripCount} of $complete trips delayed',
              tint: scheme.errorContainer,
              foreground: scheme.onErrorContainer,
            ),
            _metricCard(
              width: width,
              title: 'Schedule Adherence',
              icon: Icons.task_alt,
              value: summary.scheduleAdherencePercent == null
                  ? '—'
                  : '${summary.scheduleAdherencePercent!.round()}%',
              subtitle:
                  'How closely observed travel time matched the GTFS schedule.',
              tint: scheme.tertiaryContainer,
              foreground: scheme.onTertiaryContainer,
              progress: summary.scheduleAdherencePercent == null
                  ? null
                  : summary.scheduleAdherencePercent! / 100,
            ),
          ],
        );
      },
    );
  }

  Widget _metricCard({
    required double width,
    required String title,
    required IconData icon,
    required String value,
    required String subtitle,
    required Color tint,
    required Color foreground,
    double? progress,
  }) => SizedBox(
    width: width,
    child: Card(
      color: tint,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                key: const Key('adherence-progress'),
                value: progress.clamp(0, 1),
                color: foreground,
                backgroundColor: foreground.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                minHeight: 7,
              ),
            ],
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: foreground)),
          ],
        ),
      ),
    ),
  );

  Widget _coverageWarning() => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: const ListTile(
      leading: Icon(Icons.sync_problem_outlined),
      title: Text('Limited historical coverage'),
      subtitle: Text(
        'Some realtime trips could not be matched to the currently imported GTFS schedule. Metrics use valid matched observations only.',
      ),
    ),
  );

  Widget _coverage(RoutePerformanceSummary summary) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Historical Coverage', Icons.data_usage_outlined),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat('Observed Trips', summary.trips.length),
              _stat('Used in Metrics', summary.completeTrips.length),
              _stat('Partial', summary.partialTripCount),
              _stat('Observations', summary.totalObservations),
            ],
          ),
          const Divider(height: 24),
          Text('Period  ${_range().label}'),
        ],
      ),
    ),
  );

  Widget _stat(String label, int value) => Container(
    constraints: const BoxConstraints(minWidth: 116),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

  Widget _delayBreakdown(RoutePerformanceSummary summary) {
    final total = summary.completeTrips.length;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Delay Breakdown', Icons.stacked_bar_chart),
            const SizedBox(height: 16),
            _bar(
              'On time / within 5 min',
              total - summary.delayedTripCount,
              total,
              scheme.tertiary,
            ),
            const SizedBox(height: 12),
            _bar('Delayed', summary.delayedTripCount, total, scheme.error),
          ],
        ),
      ),
    );
  }

  Widget _bar(String label, int count, int total, Color color) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text('$count'),
        ],
      ),
      const SizedBox(height: 4),
      LinearProgressIndicator(
        value: total == 0 ? 0 : count / total,
        color: color,
        minHeight: 7,
        borderRadius: BorderRadius.circular(8),
      ),
    ],
  );

  Widget _tripCard(ObservedTripPerformance trip) {
    final delayed = trip.delay! > delayThreshold;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_dateLong(transitServiceDateTime(trip.firstObservedAt))} · ${_route?.shortName ?? _route?.displayName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _statusChip(delayed ? 'Delayed' : 'On time', delayed),
              ],
            ),
            Text('Vehicle ${trip.vehicleId}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _tripStat('Scheduled', _minutes(trip.scheduledDuration)),
                _tripStat('Observed', _minutes(trip.observedDuration!)),
                _tripStat('Difference', _signedMinutes(trip.delay!)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, bool delayed) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        delayed ? Icons.warning_amber_rounded : Icons.check_circle_outline,
        size: 18,
      ),
      label: Text(label),
      backgroundColor: delayed
          ? scheme.errorContainer
          : scheme.tertiaryContainer,
      side: BorderSide.none,
    );
  }

  Widget _tripStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );

  Widget _partialSection(RoutePerformanceSummary summary) {
    final trips = summary.trips
        .where((trip) => !trip.isSufficientlyCovered)
        .toList();
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.incomplete_circle_outlined),
            title: Text('Partial / insufficient trips (${trips.length})'),
            subtitle: const Text('Excluded from performance metrics'),
            trailing: Icon(
              _showPartial ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () => setState(() => _showPartial = !_showPartial),
          ),
          if (_showPartial)
            ...trips.map(
              (trip) => ListTile(
                dense: true,
                leading: Chip(
                  label: Text(
                    trip.coverageStatus == TripCoverageStatus.insufficient
                        ? 'Insufficient'
                        : 'Partial',
                  ),
                ),
                title: Text('Vehicle ${trip.vehicleId}'),
                subtitle: Text('Reason: ${trip.coverageReason}'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState() => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'No historical data',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'No realtime observations are available for ${_route?.shortName ?? 'this route'} during this period.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Try another route or period, or collect more historical data.',
          ),
        ],
      ),
    ),
  );

  Widget _noRoutesState() => Card(
    key: const Key('no-historical-route-data'),
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'No historical route data',
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

  Widget _insufficientState(RoutePerformanceSummary summary) => Card(
    key: const Key('insufficient-trip-coverage'),
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.hourglass_empty,
            size: 52,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Insufficient trip coverage',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Realtime observations are available for this route, but no complete trips could be evaluated during this period.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            '${summary.totalObservations} observations · '
            '${summary.trips.length} matched trip occurrences · '
            '${summary.partialTripCount} partial or insufficient',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Widget _errorCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40),
          const SizedBox(height: 8),
          Text(_error ?? 'Unable to load route performance.'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _reloadAvailableRoutes,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
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

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _SaveRoutePerformanceDialog extends StatefulWidget {
  const _SaveRoutePerformanceDialog({
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
  State<_SaveRoutePerformanceDialog> createState() =>
      _SaveRoutePerformanceDialogState();
}

class _SaveRoutePerformanceDialogState
    extends State<_SaveRoutePerformanceDialog> {
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
    title: const Text('Save Route Performance Report'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('save-report-title'),
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
            key: const Key('save-report-notes'),
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
              key: const Key('save-report-error'),
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
        key: const Key('confirm-save-route-performance-report'),
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

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _dateLong(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';
String _time(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  return '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
}

String _minutes(Duration duration) =>
    '${(duration.inSeconds / 60).round()} min';
String _signedMinutes(Duration duration) {
  final minutes = (duration.inSeconds / 60).round();
  return '${minutes >= 0 ? '+' : ''}$minutes min';
}

const _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
