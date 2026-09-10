import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/route_stop_network_map.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

class RouteBusStopRecommendationPage extends StatefulWidget {
  const RouteBusStopRecommendationPage({
    this.session,
    this.coordinator,
    this.recommendationRepository,
    this.evidenceRepository,
    this.routeRepository,
    this.now,
    this.baseMapEnabled = true,
    this.preparationScheduler,
    super.key,
  });

  final RouteStopDashboardSession? session;
  final RouteStopDashboardCoordinator? coordinator;
  final RouteStopRecommendationRepository? recommendationRepository;
  final DistrictRouteStopEvidenceRepository? evidenceRepository;
  final RoutePerformanceRepository? routeRepository;
  final DateTime Function()? now;
  final bool baseMapEnabled;
  final Future<void> Function()? preparationScheduler;

  @override
  State<RouteBusStopRecommendationPage> createState() =>
      _RouteBusStopRecommendationPageState();
}

class _RouteBusStopRecommendationPageState
    extends State<RouteBusStopRecommendationPage> {
  late final RouteStopDashboardCoordinator _coordinator;
  late final RouteStopDashboardSession _session;
  final _mapSectionKey = GlobalKey();
  bool _screening = false;
  bool _analysing = false;
  bool _retrying = false;
  final Set<String> _expandedGroups = <String>{};

  List<RouteStopDashboardCandidate> get _candidates => _session.candidates;
  List<RouteStopDashboardExcludedRoute> get _excludedRoutes =>
      _session.excludedRoutes;
  RouteStopRecommendationResult? get _result => _session.recommendationResult;
  DateTime? get _periodStartUtc => _session.periodStartUtc;
  DateTime? get _periodEndUtc => _session.periodEndUtc;
  bool get _empty => _session.empty;
  bool get _setupFailure => _session.setupFailure;

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
    return routeStopAnalysisPeriod(now: widget.now);
  }

  Future<void> _prepareEvidence() async {
    if (_screening || _analysing || _retrying) return;
    final period = _newPeriod();
    setState(() => _screening = true);
    if (widget.preparationScheduler != null) {
      await widget.preparationScheduler!();
    } else {
      await _coordinator.prepareSession(
        session: _session,
        startUtc: period.startUtc,
        endExclusiveUtc: period.endUtc,
      );
    }
    if (!mounted) return;
    setState(() => _screening = false);
  }

  Future<void> _startNewAnalysis() async {
    _session.clear();
    await _prepareEvidence();
  }

  Future<void> _generateRecommendations() async {
    if (!_session.screeningComplete ||
        _candidates.isEmpty ||
        _result != null ||
        _analysing) {
      return;
    }
    await _analyse();
  }

  Future<void> _analyse() async {
    final start = _periodStartUtc;
    final end = _periodEndUtc;
    if (_analysing || _retrying || start == null || end == null) {
      return;
    }
    if (_candidates.isEmpty) return;
    setState(() => _analysing = true);
    final result = await _coordinator.analyse(
      candidates: _candidates,
      startUtc: start,
      endExclusiveUtc: end,
    );
    if (!mounted) return;
    setState(() {
      _expandedGroups.clear();
      _session.recommendationResult = result;
      _analysing = false;
    });
  }

  Future<void> _retry() async {
    if (_screening || _analysing || _retrying) return;
    final start = _periodStartUtc;
    final end = _periodEndUtc;
    if (start == null || end == null || _candidates.isEmpty) return;
    setState(() => _retrying = true);
    try {
      final replacement = await _coordinator.retry(
        candidates: _candidates,
        startUtc: start,
        endExclusiveUtc: end,
      );
      if (!mounted) return;
      setState(() => _session.recommendationResult = replacement);
    } on Object {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

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
              if (!_session.screeningComplete && !_setupFailure) ...[
                const SizedBox(height: 16),
                Card(
                  key: const Key('route-map-loading-shell'),
                  child: SizedBox(
                    height: 280,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Preparing existing route network…'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
                        _analysing || _screening || _retrying || _result != null
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
                      : 'Analysing eligible routes in one feature synthesis...',
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
              if (_result != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Recommendation Results',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _groupedResult(_result!),
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
            onPressed: _screening || _analysing || _retrying
                ? null
                : _startNewAnalysis,
            icon: const Icon(Icons.refresh),
            label: const Text('Start New Analysis'),
          ),
        ],
      ),
    ),
  );

  Widget _evidenceOverview() {
    final allStops = _candidates
        .expand(
          (candidate) => candidate.evidence.routeStopEvidence.network.trips,
        )
        .expand((trip) => trip.stops)
        .toList();
    final delayedTrips = _candidates.fold<int>(
      0,
      (sum, candidate) =>
          sum +
          candidate
              .evidence
              .routeStopEvidence
              .operational
              .routePerformanceSummary
              .delayedTripCount,
    );
    final relevantFeedback = _candidates.fold<int>(
      0,
      (sum, candidate) =>
          sum +
          candidate
              .evidence
              .routeStopEvidence
              .feedback
              .routeStopRelevantRecordCount,
    );
    final stopIssues = _candidates.fold<int>(
      0,
      (sum, candidate) =>
          sum +
          (candidate.evidence.routeStopEvidence.feedback.countByIssueType[
                  RouteStopFeedbackIssueTypes.missingBusStop] ??
              0) +
          (candidate.evidence.routeStopEvidence.feedback.countByIssueType[
                  RouteStopFeedbackIssueTypes.longWalkingDistance] ??
              0),
    );
    final routeInformationIssues = _candidates.fold<int>(
      0,
      (sum, candidate) =>
          sum +
          (candidate.evidence.routeStopEvidence.feedback.countByIssueType[
                  RouteStopFeedbackIssueTypes.incorrectRouteInformation] ??
              0),
    );
    return Card(
      key: const Key('route-stop-evidence-overview'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Route & Stop Evidence',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _coverageMetric('Analysis Period', 'Past 30 Days'),
                _coverageMetric(
                  'Routes Analysed',
                  '${_session.routesAnalysed}',
                ),
                _coverageMetric('Stop Records Analysed', '${allStops.length}'),
                _coverageMetric(
                  'Delayed Trips',
                  '$delayedTrips',
                ),
                _coverageMetric(
                  'Relevant Route/Stop Feedback',
                  '$relevantFeedback',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Feedback breakdown',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('Stop-related Issues: $stopIssues'),
                Text('Route-information Issues: $routeInformationIssues'),
              ],
            ),
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
            SizedBox(key: _mapSectionKey),
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
                setState(() {
                  _session.selectedRouteId = routeId;
                  _session.selectedRecommendationAction = null;
                  _session.selectedCandidateArea = null;
                  _session.selectedTargetStopIds = const [];
                });
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
                  recommendationAction: _session.selectedRecommendationAction,
                  candidateArea: _session.selectedCandidateArea,
                  targetStopIds: _session.selectedTargetStopIds,
                  baseMapEnabled: widget.baseMapEnabled,
                ),
              ),
              if (_session.selectedRecommendationAction case final action?) ...[
                const SizedBox(height: 10),
                _mapRecommendationContext(action),
              ],
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
            _detailSection('Operational Observations', [
              'Peak Operation observations: '
                  '${source.operational.peakOperationSummary.observationCount}',
              'Route Performance observations: '
                  '${source.operational.routePerformanceSummary.totalObservations}',
            ]),
            _detailSection('Passenger Feedback', [
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

  Widget _groupedResult(RouteStopRecommendationResult result) {
    final synthesis = result.synthesis;
    if (synthesis == null) {
      return Card(
        key: const Key('route-stop-feature-failure'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                result.status == RouteStopRecommendationStatus.invalidAiResponse
                    ? 'Response Could Not Be Validated'
                    : 'Recommendation Temporarily Unavailable',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(_failureMessage(result.failure)),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('retry-feature-synthesis'),
                  onPressed: _retrying || _analysing ? null : _retry,
                  icon: _retrying
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Retry Feature Analysis'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      key: const Key('route-stop-grouped-result'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Overall Route & Stop Analysis',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(synthesis.overallSummary),
            for (final group in _visibleRecommendationGroups(synthesis)) ...[
              const SizedBox(height: 16),
              _actionGroup(group),
            ],
            if (_visibleRecommendationGroups(synthesis).isEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'No actionable recommendations are available with the current evidence.',
                key: Key('no-actionable-recommendations'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<RouteStopRecommendationGroup> _visibleRecommendationGroups(
    RouteStopRecommendationSynthesis synthesis,
  ) {
    final groups = synthesis.recommendationGroups
        .where(
          (group) =>
              group.action !=
              RouteStopRecommendationAction.insufficientEvidence,
        )
        .toList();
    groups.sort(
      (left, right) => left.action.index.compareTo(right.action.index),
    );
    return groups;
  }

  Widget _actionGroup(RouteStopRecommendationGroup group) => Card.outlined(
    key: Key('action-group-${group.action.name}'),
    color:
        group.action ==
            RouteStopRecommendationAction.maintainCurrentConfiguration
        ? Theme.of(context).colorScheme.surfaceContainerLowest
        : null,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _actionLabel(group.action),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(_routeCountLabel(group.routeIds.length)),
          const SizedBox(height: 8),
          Text(group.summary),
          const SizedBox(height: 10),
          for (final routeId in (_expandedGroups.contains(group.action.name)
              ? group.routeIds
              : group.routeIds.take(3)))
            _recommendationRoute(group, routeId),
          if (group.routeIds.length > 3)
            TextButton(
              onPressed: () => setState(() {
                if (!_expandedGroups.add(group.action.name)) {
                  _expandedGroups.remove(group.action.name);
                }
              }),
              child: Text(
                _expandedGroups.contains(group.action.name)
                    ? 'Show fewer'
                    : 'Show ${group.routeIds.length - 3} more routes',
              ),
            ),
        ],
      ),
    ),
  );

  Widget _recommendationRoute(
    RouteStopRecommendationGroup group,
    String routeId,
  ) {
    final candidate = _candidate(routeId);
    final record = _recommendationRecord(routeId);
    final rationale = record?.conciseRationale;
    final evidence = candidate?.evidence.routeStopEvidence;
    final stopIssueCount = evidence == null
        ? 0
        : (evidence.feedback.countByIssueType[
                    RouteStopFeedbackIssueTypes.missingBusStop] ??
                0) +
            (evidence.feedback.countByIssueType[
                    RouteStopFeedbackIssueTypes.longWalkingDistance] ??
                0);
    final routeInformationIssueCount = evidence == null
        ? 0
        : evidence.feedback.countByIssueType[
                RouteStopFeedbackIssueTypes.incorrectRouteInformation] ??
            0;
    final targetStopNames = group.action ==
            RouteStopRecommendationAction.stopImprovement
        ? _targetStopNames(candidate, record?.targetStopIds ?? const [])
        : const <String>[];
    return Container(
      key: Key('group-route-$routeId'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _routeName(routeId),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (targetStopNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Target Stops', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 2),
            for (final name in targetStopNames) Text(name),
          ],
          if (evidence != null) ...[
            const SizedBox(height: 8),
            Text(
              'Supporting Evidence',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 2),
            Text(
              'Relevant passenger feedback: '
              '${evidence.feedback.routeStopRelevantRecordCount}',
            ),
            Text(
              'Delayed trips: '
              '${evidence.operational.routePerformanceSummary.delayedTripCount}',
            ),
            Text('Stop-related issues: $stopIssueCount'),
            Text('Route-information issues: $routeInformationIssueCount'),
          ],
          if (rationale != null) ...[
            const SizedBox(height: 8),
            Text(
              'AI Rationale',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 2),
            Text(rationale),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                key: Key('view-recommendation-evidence-$routeId'),
                onPressed: candidate == null
                    ? null
                    : () => _showDeterministicEvidence(candidate),
                child: const Text('View Evidence'),
              ),
              OutlinedButton.icon(
                key: Key('show-on-map-$routeId'),
                onPressed: candidate == null
                    ? null
                    : () => _showOnMap(group, routeId),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Show on Map'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  RouteStopDashboardCandidate? _candidate(String routeId) => _candidates
      .where((candidate) => candidate.route.routeId == routeId)
      .firstOrNull;

  RouteStopRecommendationRecord? _recommendationRecord(String routeId) =>
      _result?.synthesis?.routeRecommendations
          .where((record) => record.routeId == routeId)
          .firstOrNull;

  List<String> _targetStopNames(
    RouteStopDashboardCandidate? candidate,
    List<String> targetStopIds,
  ) {
    if (candidate == null || targetStopIds.isEmpty) return const [];
    final namesById = <String, String>{};
    for (final stop in candidate.evidence.routeStopEvidence.network.trips
        .expand((trip) => trip.stops)) {
      final name = stop.stopName?.trim();
      if (targetStopIds.contains(stop.stopId) &&
          name != null &&
          name.isNotEmpty) {
        namesById.putIfAbsent(stop.stopId, () => name);
      }
    }
    return [
      for (final stopId in targetStopIds)
        if (namesById[stopId] case final name?) name,
    ];
  }

  void _showOnMap(RouteStopRecommendationGroup group, String routeId) {
    final record = _recommendationRecord(routeId);
    final candidateArea = record?.actions.contains(
              RouteStopRecommendationAction.additionalStopCoverage,
            ) ==
            true
        ? record?.candidateArea
        : null;
    setState(() {
      _session.selectedRouteId = routeId;
      _session.selectedRecommendationAction = group.action;
      _session.selectedCandidateArea = candidateArea;
      _session.selectedTargetStopIds = record?.actions.contains(
                RouteStopRecommendationAction.stopImprovement,
              ) ==
              true
          ? record!.targetStopIds
          : const [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mapContext = _mapSectionKey.currentContext;
      if (mapContext != null) {
        Scrollable.ensureVisible(
          mapContext,
          duration: const Duration(milliseconds: 250),
          alignment: .05,
        );
      }
    });
  }

  Widget _mapRecommendationContext(RouteStopRecommendationAction action) {
    final area = _session.selectedCandidateArea;
    final targetStopNames = _targetStopNames(
      _selectedCandidate,
      _session.selectedTargetStopIds,
    );
    final rationale = _session.selectedRouteId == null
        ? null
        : _recommendationRecord(_session.selectedRouteId!)?.conciseRationale;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedCandidate?.route.displayName ?? 'Selected Route',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Recommendation',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(_actionLabel(action)),
            if (action == RouteStopRecommendationAction.stopImprovement &&
                targetStopNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Target Stops',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (final name in targetStopNames) Text(name),
            ],
            if (action == RouteStopRecommendationAction.stopImprovement &&
                area != null) ...[
              const SizedBox(height: 8),
              Text(
                'Also Recommended',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Text('Additional Stop Coverage'),
              const SizedBox(height: 8),
              Text(
                'Suggested Area',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text('Between ${area.fromStopName} and ${area.toStopName}'),
              if (!_candidateAreaHasUsableShape(_selectedCandidate!, area))
                const Text(
                  'An exact map marker is unavailable; the validated boundary stops are highlighted.',
                ),
            ],
            if (action ==
                    RouteStopRecommendationAction.additionalStopCoverage &&
                area != null) ...[
              const SizedBox(height: 8),
              Text(
                'Suggested Area',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text('Between ${area.fromStopName} and ${area.toStopName}'),
              if (!_candidateAreaHasUsableShape(_selectedCandidate!, area))
                const Text(
                  'An exact map marker is unavailable; the validated boundary stops are highlighted.',
                ),
            ],
            if (action ==
                    RouteStopRecommendationAction.additionalStopCoverage &&
                targetStopNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Also Recommended',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Text('Stop Improvement'),
              const SizedBox(height: 8),
              Text(
                'Target Stops',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (final name in targetStopNames) Text(name),
            ],
            if (action != RouteStopRecommendationAction.stopImprovement &&
                action !=
                    RouteStopRecommendationAction.additionalStopCoverage &&
                area != null) ...[
              const SizedBox(height: 8),
              Text(
                'Suggested Area',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text('Between ${area.fromStopName} and ${area.toStopName}'),
              if (!_candidateAreaHasUsableShape(_selectedCandidate!, area))
                const Text(
                  'An exact map marker is unavailable; the validated boundary stops are highlighted.',
                ),
            ],
            if (rationale != null) ...[
              const SizedBox(height: 8),
              Text(
                'AI Rationale',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(rationale),
            ],
          ],
        ),
      ),
    );
  }

  bool _candidateAreaHasUsableShape(
    RouteStopDashboardCandidate candidate,
    RouteStopCandidateArea area,
  ) => _candidateShapeSegment(candidate.evidence, area) != null;

  String _routeName(String routeId) =>
      _candidates
          .where((candidate) => candidate.route.routeId == routeId)
          .map((candidate) => candidate.route.displayName)
          .firstOrNull ??
      routeId;

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
}

class _ExistingNetworkMap extends StatelessWidget {
  const _ExistingNetworkMap({
    required this.evidence,
    required this.recommendationAction,
    required this.candidateArea,
    required this.targetStopIds,
    required this.baseMapEnabled,
    super.key,
  });

  final DistrictRouteStopEvidence evidence;
  final RouteStopRecommendationAction? recommendationAction;
  final RouteStopCandidateArea? candidateArea;
  final List<String> targetStopIds;
  final bool baseMapEnabled;

  @override
  Widget build(BuildContext context) {
    final area = candidateArea;
    final trips = evidence.routeStopEvidence.network.trips;
    final routeLines = [
      for (final trip in trips)
        trip.shapePoints
            .where((point) => _usableCoordinate(point.coordinate))
            .toList()
          ..sort((first, second) => first.sequence.compareTo(second.sequence)),
    ].map((line) => line.map((point) => point.coordinate).toList()).toList();
    final uniqueStops = <String, AiRouteStopEvidence>{};
    for (final stop in trips.expand((trip) => trip.stops)) {
      if (_usableCoordinate(stop.coordinate)) {
        uniqueStops.putIfAbsent(stop.stopId, () => stop);
      }
    }
    final candidateSegment = area == null
        ? null
        : _candidateShapeSegment(evidence, area);
    final candidateMidpoint = candidateSegment == null
        ? null
        : _midpointAlong(candidateSegment);
    final markers = <RouteStopMapMarker>[
      for (final stop in uniqueStops.values)
        RouteStopMapMarker(
          id: stop.stopId,
          label: stop.stopName?.trim().isNotEmpty == true
              ? stop.stopName!
              : stop.stopId,
          coordinate: stop.coordinate!,
          isTargetStop: targetStopIds.contains(stop.stopId),
          role: _isCandidateBoundary(stop.stopId, area)
              ? RouteStopMapMarkerRole.candidateBoundary
              : targetStopIds.contains(stop.stopId)
              ? RouteStopMapMarkerRole.stopToImprove
              : RouteStopMapMarkerRole.existingStop,
        ),
      if (candidateMidpoint != null)
        RouteStopMapMarker(
          id: 'recommended-area',
          label: 'Recommended Stop Area',
          coordinate: candidateMidpoint,
          role: RouteStopMapMarkerRole.recommendedArea,
        ),
    ];
    return RouteStopNetworkMap(
      key: ValueKey(
        'route-stop-network-map-${evidence.routeStopEvidence.routeId}-${recommendationAction?.name}-${area?.fromStopId}',
      ),
      routeLines: routeLines,
      markers: markers,
      candidateSegment: candidateSegment,
      showCandidateLegend: area != null,
      showTargetLegend: targetStopIds.isNotEmpty,
      initialFocus: switch (recommendationAction) {
        RouteStopRecommendationAction.stopImprovement =>
          RouteStopMapInitialFocus.stopImprovement,
        RouteStopRecommendationAction.additionalStopCoverage =>
          RouteStopMapInitialFocus.additionalCoverage,
        _ => RouteStopMapInitialFocus.allHighlights,
      },
      recommendationAreaDescription: area == null
          ? null
          : 'Between ${area.fromStopName} and ${area.toStopName}',
      baseMapEnabled: baseMapEnabled,
    );
  }
}

bool _isCandidateBoundary(
  String stopId,
  RouteStopCandidateArea? candidateArea,
) =>
    candidateArea != null &&
    (stopId == candidateArea.fromStopId || stopId == candidateArea.toStopId);

List<MapCoordinate>? _candidateShapeSegment(
  DistrictRouteStopEvidence evidence,
  RouteStopCandidateArea area,
) {
  for (final trip in evidence.routeStopEvidence.network.trips) {
    final orderedStops = [...trip.stops]
      ..sort((left, right) => left.stopSequence.compareTo(right.stopSequence));
    for (var index = 0; index + 1 < orderedStops.length; index++) {
      final from = orderedStops[index];
      final to = orderedStops[index + 1];
      if (from.stopId != area.fromStopId || to.stopId != area.toStopId) {
        continue;
      }
      if (!_usableCoordinate(from.coordinate) ||
          !_usableCoordinate(to.coordinate) ||
          trip.shapePoints.length < 2) {
        return null;
      }
      final segment = segmentShape(
        shapePoints: trip.shapePoints,
        boarding: from.coordinate!,
        alighting: to.coordinate!,
      );
      if (segment.usedFullShapeFallback || segment.points.length < 2) {
        return null;
      }
      return segment.points;
    }
  }
  return null;
}

MapCoordinate _midpointAlong(List<MapCoordinate> points) {
  final lengths = <double>[];
  var total = 0.0;
  for (var index = 1; index < points.length; index++) {
    final latitude = points[index].latitude - points[index - 1].latitude;
    final longitude = points[index].longitude - points[index - 1].longitude;
    final length = math.sqrt(latitude * latitude + longitude * longitude);
    lengths.add(length);
    total += length;
  }
  final target = total / 2;
  var travelled = 0.0;
  for (var index = 0; index < lengths.length; index++) {
    final length = lengths[index];
    if (travelled + length >= target) {
      final ratio = length == 0 ? 0.0 : (target - travelled) / length;
      final from = points[index];
      final to = points[index + 1];
      return MapCoordinate(
        from.latitude + (to.latitude - from.latitude) * ratio,
        from.longitude + (to.longitude - from.longitude) * ratio,
      );
    }
    travelled += length;
  }
  return points.last;
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
  RouteStopRecommendationAction.stopImprovement => 'Stop Improvement',
  RouteStopRecommendationAction.additionalStopCoverage =>
    'Additional Stop Coverage',
  RouteStopRecommendationAction.maintainCurrentConfiguration =>
    'Maintain Current Configuration',
  RouteStopRecommendationAction.insufficientEvidence => 'Needs More Evidence',
};

String _routeCountLabel(int count) =>
    '$count ${count == 1 ? 'Route' : 'Routes'}';

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
