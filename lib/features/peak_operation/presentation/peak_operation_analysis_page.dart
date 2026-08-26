import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_calculator.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_repository.dart';
import 'package:timezone/timezone.dart' as timezone;

enum PeakAnalysisPeriod { today, lastSevenDays, custom }

class PeakOperationAnalysisPage extends StatefulWidget {
  const PeakOperationAnalysisPage({this.repository, this.now, super.key});
  final PeakOperationRepository? repository;
  final DateTime Function()? now;
  @override
  State<PeakOperationAnalysisPage> createState() =>
      _PeakOperationAnalysisState();
}

class _PeakOperationAnalysisState extends State<PeakOperationAnalysisPage> {
  late final PeakOperationRepository _repository;
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? DefaultPeakOperationRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _routes = await _repository.loadRoutes();
      if (!mounted) return;
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
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

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = _summary != null;
      _loading = _summary == null;
      _error = null;
    });
    final range = _range();
    try {
      final observations = await _repository.loadObservations(
        startUtc: range.start,
        endExclusiveUtc: range.end,
        routeId: _routeId,
      );
      if (!mounted) return;
      setState(() {
        _summary = _calculator.calculate(
          observations: observations,
          periodStart: range.start,
          periodEnd: range.end,
          routeId: _routeId,
        );
        _updated = currentTransitServiceDateTime(now: widget.now);
        _loading = false;
        _refreshing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _customDates() async {
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
    if (range == null) return;
    setState(() {
      _customStart = range.start;
      _customEnd = range.end;
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Peak Operation Analysis')),
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
        onPressed: _loading || _refreshing ? null : _refresh,
        icon: const Icon(Icons.refresh),
      ),
    ],
  );

  Widget _filters() => LayoutBuilder(
    builder: (context, constraints) {
      final scope = DropdownButtonFormField<String?>(
        key: const Key('peak-scope-selector'),
        initialValue: _routeId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Scope',
          prefixIcon: Icon(Icons.route),
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('All Routes'),
          ),
          ..._routes.map(
            (route) => DropdownMenuItem<String?>(
              value: route.routeId,
              child: Text(route.displayName, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) {
          setState(() {
            _routeId = value;
            _summary = null;
          });
          _refresh();
        },
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
          setState(() => _period = selection.first);
          if (_period == PeakAnalysisPeriod.custom) {
            await _customDates();
          } else {
            await _refresh();
          }
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
    final summary = _summary!;
    if (!summary.hasData) return _emptyState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.hasReliablePeak)
          _summaryCards(summary)
        else
          _limitedState(summary),
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

  Widget _errorState() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(_error ?? 'Unable to load peak operation analysis.'),
          const SizedBox(height: 8),
          FilledButton(onPressed: _load, child: const Text('Retry')),
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
