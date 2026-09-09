import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:timezone/timezone.dart' as timezone;

class RouteBusStopRecommendationPage extends StatefulWidget {
  const RouteBusStopRecommendationPage({
    this.session,
    this.coordinator,
    this.recommendationRepository,
    this.evidenceRepository,
    this.routeRepository,
    this.now,
    super.key,
  });

  final RouteStopDashboardSession? session;
  final RouteStopDashboardCoordinator? coordinator;
  final RouteStopRecommendationRepository? recommendationRepository;
  final DistrictRouteStopEvidenceRepository? evidenceRepository;
  final RoutePerformanceRepository? routeRepository;
  final DateTime Function()? now;

  @override
  State<RouteBusStopRecommendationPage> createState() =>
      _RouteBusStopRecommendationPageState();
}

class _RouteBusStopRecommendationPageState
    extends State<RouteBusStopRecommendationPage> {
  late final RouteStopDashboardCoordinator _coordinator;
  late final RouteStopDashboardSession _session;
  bool _screening = false;
  bool _analysing = false;
  String? _retryingRouteId;

  List<RouteStopDashboardCandidate> get _candidates => _session.candidates;
  List<RouteStopDashboardExcludedRoute> get _excludedRoutes =>
      _session.excludedRoutes;
  List<RouteStopDashboardEntry> get _entries => _session.entries;
  DateTime? get _periodStartUtc => _session.periodStartUtc;
  DateTime? get _periodEndUtc => _session.periodEndUtc;
  bool get _empty => _session.empty;
  set _empty(bool value) => _session.empty = value;
  bool get _setupFailure => _session.setupFailure;
  set _setupFailure(bool value) => _session.setupFailure = value;
  int get _completedInBatch => _session.completedInBatch;
  set _completedInBatch(int value) => _session.completedInBatch = value;
  int get _batchTotal => _session.batchTotal;
  set _batchTotal(int value) => _session.batchTotal = value;
  int get _nextCandidateIndex => _session.nextCandidateIndex;
  set _nextCandidateIndex(int value) => _session.nextCandidateIndex = value;

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? RouteStopDashboardSession();
    _coordinator =
        widget.coordinator ??
        RouteStopDashboardCoordinator(
          routeRepository: widget.routeRepository,
          evidenceRepository: widget.evidenceRepository,
          recommendationRepository: widget.recommendationRepository,
        );
    final period = _newPeriod();
    if (_session.periodStartUtc != null &&
        !_session.matchesPeriod(period.startUtc, period.endUtc)) {
      _session.clear();
    }
    if (!_session.screeningComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prepareEvidence();
      });
    }
  }

  ({DateTime startUtc, DateTime endUtc}) _newPeriod() {
    final now = currentTransitServiceDateTime(now: widget.now);
    final today = timezone.TZDateTime(
      transitServiceLocation,
      now.year,
      now.month,
      now.day,
    );
    return (
      startUtc: today.subtract(const Duration(days: 29)).toUtc(),
      endUtc: today.add(const Duration(days: 1)).toUtc(),
    );
  }

  Future<void> _prepareEvidence() async {
    if (_screening || _analysing || _retryingRouteId != null) return;
    final period = _newPeriod();
    setState(() {
      _session.begin(period.startUtc, period.endUtc);
      _screening = true;
    });
    try {
      final result = await _coordinator.screenRoutes(
        startUtc: period.startUtc,
        endExclusiveUtc: period.endUtc,
      );
      if (!mounted) return;
      setState(() {
        _candidates.addAll(result.candidates);
        _excludedRoutes.addAll(result.excludedRoutes);
        _session.routesAnalysed = result.routesAnalysed;
        _session.screeningComplete = true;
        _session.selectedRouteId = result.candidates.firstOrNull?.route.routeId;
        _screening = false;
        _empty = result.candidates.isEmpty;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _screening = false;
        _setupFailure = true;
      });
    }
  }

  Future<void> _generateRecommendations() async {
    if (!_session.screeningComplete ||
        _candidates.isEmpty ||
        _entries.isNotEmpty ||
        _analysing) {
      return;
    }
    await _analyseNextBatch();
  }

  Future<void> _analyseNextBatch() async {
    final start = _periodStartUtc;
    final end = _periodEndUtc;
    if (_analysing ||
        _retryingRouteId != null ||
        start == null ||
        end == null) {
      return;
    }
    final remaining = _candidates.skip(_nextCandidateIndex).toList();
    if (remaining.isEmpty) return;
    final total = remaining.length.clamp(0, routeStopDashboardBatchSize);
    setState(() {
      _analysing = true;
      _completedInBatch = 0;
      _batchTotal = total;
    });
    await _coordinator.analyseBatch(
      candidates: remaining,
      startUtc: start,
      endExclusiveUtc: end,
      onCompleted: (completed, batchTotal, entry) {
        if (!mounted) return;
        setState(() {
          _entries.add(entry);
          _completedInBatch = completed;
          _batchTotal = batchTotal;
          _nextCandidateIndex++;
        });
      },
    );
    if (!mounted) return;
    setState(() => _analysing = false);
  }

  Future<void> _retry(RouteStopDashboardEntry entry) async {
    if (_screening || _analysing || _retryingRouteId != null) return;
    final start = _periodStartUtc;
    final end = _periodEndUtc;
    final candidate = _candidates
        .where((item) => item.route.routeId == entry.route.routeId)
        .firstOrNull;
    if (start == null || end == null || candidate == null) return;
    setState(() => _retryingRouteId = entry.route.routeId);
    try {
      final replacement = await _coordinator.retry(
        candidate: candidate,
        startUtc: start,
        endExclusiveUtc: end,
      );
      if (!mounted) return;
      final index = _entries.indexWhere(
        (item) => item.route.routeId == entry.route.routeId,
      );
      if (index >= 0) setState(() => _entries[index] = replacement);
    } on Object {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _retryingRouteId = null);
    }
  }

  int get _remainingCount => _candidates.length - _nextCandidateIndex;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Route & Bus Stop Recommendations')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 16),
              _analysisCard(),
              if (_session.screeningComplete) ...[
                const SizedBox(height: 16),
                _evidenceOverview(),
                if (_candidates.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _routeMapSection(),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('generate-ai-recommendation'),
                    onPressed:
                        _analysing ||
                            _screening ||
                            _retryingRouteId != null ||
                            _entries.isNotEmpty
                        ? null
                        : _generateRecommendations,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Generate AI Recommendation'),
                  ),
                ],
              ],
              if (_screening || _analysing) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(key: Key('analysis-progress')),
                const SizedBox(height: 8),
                Text(
                  _screening
                      ? 'Screening routes using deterministic evidence...'
                      : 'Analysing route ${(_completedInBatch + 1).clamp(1, _batchTotal)} of $_batchTotal',
                  key: const Key('analysis-progress-label'),
                  textAlign: TextAlign.center,
                ),
              ],
              if (_setupFailure) ...[
                const SizedBox(height: 16),
                _messageCard(
                  'Route evidence could not be prepared.',
                  'Start a new analysis when the data service is available.',
                ),
              ],
              if (_empty) ...[
                const SizedBox(height: 16),
                _messageCard(
                  'No eligible routes',
                  'No routes currently have enough deterministic route and stop evidence for AI analysis over the past 30 days.',
                ),
              ],
              if (_entries.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Recommendation Results',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                for (final entry in _entries) ...[
                  _resultCard(entry),
                  const SizedBox(height: 12),
                ],
                Text(
                  '${_entries.length} of ${_candidates.length} eligible routes analysed',
                  key: const Key('analysed-count'),
                ),
                if (_remainingCount > 0) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('analyse-next-routes'),
                    onPressed:
                        _analysing || _screening || _retryingRouteId != null
                        ? null
                        : _analyseNextBatch,
                    icon: const Icon(Icons.navigate_next),
                    label: Text(
                      'Analyse Next Routes ($_remainingCount remaining)',
                    ),
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    ),
  );

  Widget _header() => Row(
    children: [
      Icon(
        Icons.alt_route,
        size: 40,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Route & Bus Stop Recommendations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Review evidence-grounded route and stop actions across eligible routes.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _analysisCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Analysis Period',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text('Past 30 Days', key: Key('analysis-period')),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('analyse-routes'),
            onPressed: _screening || _analysing || _retryingRouteId != null
                ? null
                : _prepareEvidence,
            icon: const Icon(Icons.refresh),
            label: const Text('Start New Analysis'),
          ),
        ],
      ),
    ),
  );

  Widget _evidenceOverview() {
    final routeStructures = _candidates
        .map((candidate) => candidate.evidence.routeStopEvidence.network.trips)
        .toList();
    final stopLists = routeStructures
        .expand((trips) => trips)
        .map((trip) => trip.stops);
    final allStops = stopLists.expand((stops) => stops).toList();
    final coordinateCount = allStops
        .where((stop) => _usableCoordinate(stop.coordinate))
        .length;
    final distanceSources = _candidates.map((candidate) {
      final source = candidate.evidence.routeStopEvidence;
      final distances = source.network.trips
          .map((trip) => trip.routeDistanceMeters)
          .whereType<double>();
      final spacing = source.stopSpacingByTrip
          .expand((trip) => trip.consecutiveStops)
          .map((item) => item.distanceMeters)
          .whereType<double>();
      return (
        available: distances.isNotEmpty && spacing.isNotEmpty,
        present: distances.isNotEmpty || spacing.isNotEmpty,
      );
    }).toList();
    final operational = _candidates.map((candidate) {
      final source = candidate.evidence.routeStopEvidence.operational;
      return source.peakOperationSummary.observationCount > 0 ||
          source.routePerformanceSummary.totalObservations > 0;
    }).toList();
    final feedback = _candidates
        .map(
          (candidate) =>
              candidate
                  .evidence
                  .routeStopEvidence
                  .feedback
                  .routeStopRelevantRecordCount >
              0,
        )
        .toList();
    return Card(
      key: const Key('route-stop-evidence-overview'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Route / Stop Evidence Coverage',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _coverageMetric(
                  'Routes Analysed',
                  '${_session.routesAnalysed}',
                ),
                _coverageMetric('Eligible Routes', '${_candidates.length}'),
                _coverageMetric(
                  'Limited / Excluded Routes',
                  '${_excludedRoutes.length}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _coverageRow(
              'Route / Trip Structure',
              _candidates.isEmpty ? 'Missing' : 'Available',
            ),
            _coverageRow(
              'Ordered Stops',
              _sourceCoverage(
                total: routeStructures.length,
                available: routeStructures
                    .where(
                      (trips) => trips.every((trip) => trip.stops.length >= 2),
                    )
                    .length,
                present: routeStructures
                    .where(
                      (trips) => trips.any((trip) => trip.stops.isNotEmpty),
                    )
                    .length,
              ),
            ),
            _coverageRow(
              'Stop Coordinates',
              _sourceCoverage(
                total: allStops.length,
                available: coordinateCount,
                present: coordinateCount,
              ),
            ),
            _coverageRow(
              'Route Distance / Spacing',
              _sourceCoverage(
                total: distanceSources.length,
                available: distanceSources
                    .where((source) => source.available)
                    .length,
                present: distanceSources
                    .where((source) => source.available || source.present)
                    .length,
              ),
            ),
            _coverageRow('Operational Evidence', _booleanCoverage(operational)),
            _coverageRow('Relevant Feedback', _booleanCoverage(feedback)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('view-route-stop-evidence'),
                  onPressed: _selectedCandidate == null
                      ? null
                      : () => _showDeterministicEvidence(_selectedCandidate!),
                  child: const Text('View Evidence'),
                ),
                if (_excludedRoutes.isNotEmpty)
                  OutlinedButton(
                    key: const Key('view-limited-routes'),
                    onPressed: _showLimitedRoutes,
                    child: const Text('View Limited / Excluded Routes'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeMapSection() {
    final selected = _selectedCandidate;
    return Card(
      key: const Key('existing-network-map-section'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Existing Route Network',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('route-map-selector'),
              initialValue: _session.selectedRouteId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Route',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final candidate in _candidates)
                  DropdownMenuItem(
                    value: candidate.route.routeId,
                    child: Text(
                      candidate.route.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (routeId) {
                if (routeId == null) return;
                setState(() => _session.selectedRouteId = routeId);
              },
            ),
            const SizedBox(height: 12),
            if (selected != null) ...[
              Text(
                selected.route.displayName,
                key: const Key('selected-map-route'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 280,
                child: _ExistingNetworkMap(
                  key: ValueKey(
                    'existing-network-map-${selected.route.routeId}',
                  ),
                  evidence: selected.evidence,
                ),
              ),
              if (!_selectedHasShape(selected))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'An existing route shape is unavailable; mapped stops are shown.',
                  ),
                ),
              if (_selectedMissingCoordinateCount(selected) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_selectedMissingCoordinateCount(selected)} stop occurrences cannot be mapped because coordinates are unavailable.',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  RouteStopDashboardCandidate? get _selectedCandidate {
    final selectedRouteId = _session.selectedRouteId;
    return _candidates
        .where((candidate) => candidate.route.routeId == selectedRouteId)
        .firstOrNull;
  }

  bool _selectedHasShape(RouteStopDashboardCandidate candidate) =>
      candidate.evidence.routeStopEvidence.network.trips.any(
        (trip) =>
            trip.shapePoints
                .where((point) => _usableCoordinate(point.coordinate))
                .length >=
            2,
      );

  int _selectedMissingCoordinateCount(RouteStopDashboardCandidate candidate) =>
      candidate.evidence.routeStopEvidence.network.trips
          .expand((trip) => trip.stops)
          .where((stop) => !_usableCoordinate(stop.coordinate))
          .length;

  Widget _coverageMetric(String label, String value) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 140),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _coverageRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  String _booleanCoverage(List<bool> values) => _sourceCoverage(
    total: values.length,
    available: values.where((value) => value).length,
    present: values.where((value) => value).length,
  );

  String _sourceCoverage({
    required int total,
    required int available,
    required int present,
  }) {
    if (total == 0 || present == 0) return 'Missing';
    return available == total ? 'Available' : 'Limited';
  }

  Future<void> _showLimitedRoutes() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: .8,
      child: ListView(
        key: const Key('limited-routes-details'),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Limited / Excluded Routes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final item in _excludedRoutes)
            ListTile(
              title: Text(item.route.displayName),
              subtitle: Text(_exclusionReason(item.reason)),
            ),
        ],
      ),
    ),
  );

  Future<void> _showDeterministicEvidence(
    RouteStopDashboardCandidate candidate,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final evidence = candidate.evidence;
      final source = evidence.routeStopEvidence;
      final trips = source.network.trips;
      final stops = trips.expand((trip) => trip.stops).toList();
      final coordinateCount = stops
          .where((stop) => _usableCoordinate(stop.coordinate))
          .length;
      final routeDistances = trips
          .map((trip) => trip.routeDistanceMeters)
          .whereType<double>()
          .length;
      final spacingValues = source.stopSpacingByTrip
          .expand((trip) => trip.consecutiveStops)
          .map((spacing) => spacing.distanceMeters)
          .whereType<double>()
          .length;
      return FractionallySizedBox(
        heightFactor: .85,
        child: ListView(
          key: Key('deterministic-evidence-${candidate.route.routeId}'),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              candidate.route.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _detailSection('Route Structure', [
              'Usable trips: ${trips.where(_usableTrip).length}',
              'Trips represented: ${trips.length}',
              'Ordered stop occurrences: ${stops.length}',
            ]),
            _detailSection('Stop Coverage', [
              'Stops with coordinates: $coordinateCount of ${stops.length}',
              'District membership inside: '
                  '${evidence.stopOccurrenceCounts.insideJohorBahruDistrict}',
              'District membership outside: '
                  '${evidence.stopOccurrenceCounts.outsideJohorBahruDistrict}',
              'District membership unverifiable: '
                  '${evidence.stopOccurrenceCounts.unverifiable}',
            ]),
            _detailSection('Distance / Spacing', [
              'Trips with route distance: $routeDistances of ${trips.length}',
              'Available consecutive spacing values: $spacingValues',
            ]),
            _detailSection('Operational Evidence', [
              'Peak Operation observations: '
                  '${source.operational.peakOperationSummary.observationCount}',
              'Route Performance observations: '
                  '${source.operational.routePerformanceSummary.totalObservations}',
            ]),
            _detailSection('Feedback', [
              'Relevant route/stop feedback: '
                  '${source.feedback.routeStopRelevantRecordCount}',
            ]),
            _detailSection(
              'Limitations',
              _routeLimitations(evidence, coordinateCount, stops.length),
            ),
          ],
        ),
      );
    },
  );

  Widget _detailSection(String title, List<String> values) => Padding(
    key: Key(
      'evidence-section-${title.toLowerCase().replaceAll(RegExp('[^a-z]+'), '-')}',
    ),
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        for (final value in values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(value),
          ),
      ],
    ),
  );

  List<String> _routeLimitations(
    DistrictRouteStopEvidence evidence,
    int coordinateCount,
    int stopCount,
  ) {
    final source = evidence.routeStopEvidence;
    final values = <String>[
      if (coordinateCount < stopCount)
        '${stopCount - coordinateCount} stop occurrences do not have usable coordinates.',
      if (source.network.trips.every(
        (trip) => trip.routeDistanceMeters == null,
      ))
        'Route distance is unavailable.',
      if (source.stopSpacingByTrip
          .expand((trip) => trip.consecutiveStops)
          .every((spacing) => spacing.distanceMeters == null))
        'Inter-stop spacing is unavailable.',
      if (source.operational.peakOperationSummary.observationCount == 0 &&
          source.operational.routePerformanceSummary.totalObservations == 0)
        'Operational observations are unavailable.',
      if (source.feedback.routeStopRelevantRecordCount == 0)
        'No relevant feedback is available; this does not confirm that no route or stop issue exists.',
      if (evidence.stopOccurrenceCounts.unverifiable > 0)
        'Some stop district memberships are unverifiable.',
    ];
    return values.isEmpty
        ? const ['No deterministic evidence limitations were recorded.']
        : values;
  }

  Widget _resultCard(RouteStopDashboardEntry entry) {
    final recommendation = entry.result.recommendation;
    final failure =
        entry.result.status ==
            RouteStopRecommendationStatus.temporarilyUnavailable ||
        entry.result.status == RouteStopRecommendationStatus.invalidAiResponse;
    return Card(
      key: Key('route-result-${entry.route.routeId}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.route.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              failure
                  ? _routeFailureTitle(entry.result)
                  : _actionLabel(recommendation!.action),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (recommendation != null) ...[
              const SizedBox(height: 4),
              Text(
                'Evidence: ${_sufficiencyLabel(recommendation.evidenceSufficiency)}',
              ),
              const SizedBox(height: 8),
              Text(recommendation.summary),
              if (recommendation.candidateArea case final area?) ...[
                const SizedBox(height: 12),
                Text(
                  'Suggested Area for Further Evaluation',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text('Between ${area.fromStopName} and ${area.toStopName}'),
                Text(area.areaDescription),
              ],
            ] else ...[
              const SizedBox(height: 8),
              Text(_failureMessage(entry.result.failure)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  key: Key('view-details-${entry.route.routeId}'),
                  onPressed: () => _showDetails(entry),
                  child: const Text('View Details'),
                ),
                if (failure)
                  TextButton.icon(
                    key: Key('retry-${entry.route.routeId}'),
                    onPressed: _retryingRouteId == null && !_analysing
                        ? () => _retry(entry)
                        : null,
                    icon: _retryingRouteId == entry.route.routeId
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetails(RouteStopDashboardEntry entry) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (context, controller) => ListView(
            key: const Key('recommendation-details'),
            controller: controller,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Recommendation Details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _detail('Route', entry.route.displayName),
              _detail('Analysis Period', 'Past 30 Days'),
              if (entry.result.recommendation case final recommendation?) ...[
                _detail('Recommendation', _actionLabel(recommendation.action)),
                _detail(
                  'Evidence Sufficiency',
                  _sufficiencyLabel(recommendation.evidenceSufficiency),
                ),
                const Divider(height: 32),
                Text(recommendation.summary),
                if (recommendation.candidateArea case final area?) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Suggested Area for Further Evaluation',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  _detail(
                    'From Stop',
                    '${area.fromStopName} (${area.fromStopId})',
                  ),
                  _detail('To Stop', '${area.toStopName} (${area.toStopId})'),
                  _detail('Area Description', area.areaDescription),
                ],
                if (recommendation.rationale.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _section('Rationale', recommendation.rationale),
                ],
                if (recommendation.evidenceReferences.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _section(
                    'Supporting Evidence',
                    recommendation.evidenceReferences
                        .map(
                          (reference) =>
                              '${_evidenceLabel(reference)} ($reference)',
                        )
                        .toList(),
                  ),
                ],
                if (recommendation.limitations.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _section('Limitations', recommendation.limitations),
                ],
              ] else ...[
                _detail('Recommendation', _routeFailureTitle(entry.result)),
                const SizedBox(height: 12),
                Text(_failureMessage(entry.result.failure)),
              ],
            ],
          ),
        ),
      );

  Widget _messageCard(String title, String body) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body),
        ],
      ),
    ),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  Widget _section(String title, List<String> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      for (final item in items)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $item')),
    ],
  );
}

class _ExistingNetworkMap extends StatelessWidget {
  const _ExistingNetworkMap({required this.evidence, super.key});

  final DistrictRouteStopEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final trips = evidence.routeStopEvidence.network.trips;
    final shapeLines = [
      for (final trip in trips)
        trip.shapePoints
            .where((point) => _usableCoordinate(point.coordinate))
            .toList()
          ..sort((first, second) => first.sequence.compareTo(second.sequence)),
    ];
    final uniqueStops = <String, AiRouteStopEvidence>{};
    for (final stop in trips.expand((trip) => trip.stops)) {
      if (_usableCoordinate(stop.coordinate)) {
        uniqueStops.putIfAbsent(stop.stopId, () => stop);
      }
    }
    final coordinates = <MapCoordinate>[
      for (final line in shapeLines)
        for (final point in line) point.coordinate,
      for (final stop in uniqueStops.values) stop.coordinate!,
    ];
    if (coordinates.isEmpty) {
      return const DecoratedBox(
        key: Key('existing-network-map'),
        decoration: BoxDecoration(color: Color(0xFFF1F3F4)),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('No existing route or stop coordinates are available.'),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final projection = _MapProjection(coordinates, constraints.biggest);
        return ClipRect(
          child: InteractiveViewer(
            key: const Key('existing-network-map'),
            minScale: 1,
            maxScale: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFFF1F3F4)),
                if (shapeLines.any((line) => line.length >= 2))
                  CustomPaint(
                    key: const Key('existing-route-shape'),
                    painter: _ExistingNetworkPainter(
                      lines: [
                        for (final line in shapeLines)
                          [
                            for (final point in line)
                              projection.offset(point.coordinate),
                          ],
                      ],
                    ),
                  ),
                for (final stop in uniqueStops.values)
                  Positioned(
                    key: Key('existing-stop-marker-${stop.stopId}'),
                    left: projection.offset(stop.coordinate!).dx - 14,
                    top: projection.offset(stop.coordinate!).dy - 14,
                    child: Tooltip(
                      message: stop.stopName?.trim().isNotEmpty == true
                          ? stop.stopName!
                          : stop.stopId,
                      child: Icon(
                        Icons.location_on,
                        size: 28,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MapProjection {
  _MapProjection(List<MapCoordinate> coordinates, this.size)
    : minimumLatitude = coordinates
          .map((coordinate) => coordinate.latitude)
          .reduce((first, second) => first < second ? first : second),
      maximumLatitude = coordinates
          .map((coordinate) => coordinate.latitude)
          .reduce((first, second) => first > second ? first : second),
      minimumLongitude = coordinates
          .map((coordinate) => coordinate.longitude)
          .reduce((first, second) => first < second ? first : second),
      maximumLongitude = coordinates
          .map((coordinate) => coordinate.longitude)
          .reduce((first, second) => first > second ? first : second);

  final Size size;
  final double minimumLatitude;
  final double maximumLatitude;
  final double minimumLongitude;
  final double maximumLongitude;

  Offset offset(MapCoordinate coordinate) {
    const padding = 28.0;
    final latitudeRange = maximumLatitude - minimumLatitude;
    final longitudeRange = maximumLongitude - minimumLongitude;
    final xRatio = longitudeRange == 0
        ? .5
        : (coordinate.longitude - minimumLongitude) / longitudeRange;
    final yRatio = latitudeRange == 0
        ? .5
        : (maximumLatitude - coordinate.latitude) / latitudeRange;
    return Offset(
      padding + xRatio * (size.width - padding * 2),
      padding + yRatio * (size.height - padding * 2),
    );
  }
}

class _ExistingNetworkPainter extends CustomPainter {
  const _ExistingNetworkPainter({required this.lines});

  final List<List<Offset>> lines;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1565C0)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final line in lines.where((line) => line.length >= 2)) {
      final path = Path()..moveTo(line.first.dx, line.first.dy);
      for (final point in line.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ExistingNetworkPainter oldDelegate) =>
      oldDelegate.lines != lines;
}

bool _usableCoordinate(MapCoordinate? coordinate) =>
    coordinate != null &&
    coordinate.latitude.isFinite &&
    coordinate.longitude.isFinite &&
    coordinate.latitude >= -90 &&
    coordinate.latitude <= 90 &&
    coordinate.longitude >= -180 &&
    coordinate.longitude <= 180;

bool _usableTrip(AiRouteTripEvidence trip) =>
    trip.tripId.trim().isNotEmpty &&
    trip.stops.where((stop) => stop.stopId.trim().isNotEmpty).length >= 2;

String _exclusionReason(RouteStopDashboardExclusionReason reason) =>
    switch (reason) {
      RouteStopDashboardExclusionReason.unusableTripStructure =>
        'No usable trip with at least two ordered stops is available.',
      RouteStopDashboardExclusionReason.evidenceLoadingFailure =>
        'Route and stop evidence could not be loaded.',
    };

String _actionLabel(RouteStopRecommendationAction action) => switch (action) {
  RouteStopRecommendationAction.routeImprovement => 'Route Improvement',
  RouteStopRecommendationAction.stopImprovement => 'Bus Stop Improvement',
  RouteStopRecommendationAction.additionalStopCoverage =>
    'Additional Stop Coverage',
  RouteStopRecommendationAction.maintainCurrentConfiguration =>
    'Maintain Current Configuration',
  RouteStopRecommendationAction.insufficientEvidence => 'Insufficient Evidence',
};

String _sufficiencyLabel(RouteStopEvidenceSufficiency value) => switch (value) {
  RouteStopEvidenceSufficiency.sufficient => 'Sufficient',
  RouteStopEvidenceSufficiency.limited => 'Limited',
  RouteStopEvidenceSufficiency.insufficient => 'Insufficient',
};

String _routeFailureTitle(RouteStopRecommendationResult result) =>
    result.status == RouteStopRecommendationStatus.invalidAiResponse
    ? 'Response Could Not Be Validated'
    : 'Recommendation Temporarily Unavailable';

String _failureMessage(RouteStopRecommendationFailure? failure) =>
    switch (failure) {
      RouteStopRecommendationFailure.timeout =>
        'The request timed out. Retry manually when ready.',
      RouteStopRecommendationFailure.network =>
        'The AI service could not be reached.',
      RouteStopRecommendationFailure.http =>
        'The AI service returned an unavailable response.',
      RouteStopRecommendationFailure.rateLimited =>
        'The AI service rate limit was reached.',
      RouteStopRecommendationFailure.authentication =>
        'The AI service is unavailable with the current configuration.',
      RouteStopRecommendationFailure.geminiNotConfigured =>
        'AI recommendation is not configured.',
      RouteStopRecommendationFailure.evidenceUnavailable =>
        'Route evidence could not be prepared.',
      _ => 'The AI response could not be validated. Please try again.',
    };

String _evidenceLabel(String reference) {
  if (reference.startsWith('stop.')) return 'Existing stop evidence';
  if (reference.startsWith('trip.')) return 'Route trip evidence';
  return switch (reference) {
    'network.route' => 'Route network evidence',
    'network.stop_spacing' => 'Consecutive stop-spacing evidence',
    'district.membership' => 'Johor Bahru District evidence',
    'operational.peak_operation' => 'Peak operation evidence',
    'operational.route_performance' => 'Route performance evidence',
    'feedback.missing_bus_stop' => 'Missing bus stop feedback',
    'feedback.long_walking_distance' => 'Long walking distance feedback',
    'feedback.incorrect_route_information' =>
      'Incorrect route information feedback',
    _ => 'Evidence reference',
  };
}
