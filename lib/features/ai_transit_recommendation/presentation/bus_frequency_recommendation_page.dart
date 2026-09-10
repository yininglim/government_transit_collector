import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

class BusFrequencyRecommendationPage extends StatefulWidget {
  const BusFrequencyRecommendationPage({
    this.session,
    this.coordinator,
    this.recommendationRepository,
    this.evidenceRepository,
    this.routeRepository,
    this.now,
    this.preparationScheduler,
    super.key,
  });
  final BusFrequencyDashboardSession? session;
  final BusFrequencyDashboardCoordinator? coordinator;
  final BusFrequencyRecommendationRepository? recommendationRepository;
  final BusFrequencyEvidenceRepository? evidenceRepository;
  final RoutePerformanceRepository? routeRepository;
  final DateTime Function()? now;
  final Future<void> Function()? preparationScheduler;
  @override
  State<BusFrequencyRecommendationPage> createState() =>
      _BusFrequencyRecommendationPageState();
}

class _BusFrequencyRecommendationPageState
    extends State<BusFrequencyRecommendationPage> {
  late final BusFrequencyDashboardCoordinator _coordinator;
  late final BusFrequencyDashboardSession _session;
  bool _screening = false;
  bool _analysing = false;
  final Set<String> _expandedGroups = <String>{};

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? BusFrequencyDashboardSession();
    _coordinator =
        widget.coordinator ??
        BusFrequencyDashboardCoordinator(
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
    return busFrequencyAnalysisPeriod(now: widget.now);
  }

  Future<void> _prepareEvidence() async {
    if (_screening || _analysing) return;
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

  Future<void> _generate() async {
    final start = _session.periodStartUtc;
    final end = _session.periodEndUtc;
    if (_screening ||
        _analysing ||
        !_session.screeningComplete ||
        _session.candidates.isEmpty ||
        _session.recommendationResult != null ||
        start == null ||
        end == null) {
      return;
    }
    setState(() => _analysing = true);
    final result = await _coordinator.analyse(
      candidates: _session.candidates,
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
    final start = _session.periodStartUtc;
    final end = _session.periodEndUtc;
    if (_screening || _analysing || start == null || end == null) return;
    setState(() => _analysing = true);
    final result = await _coordinator.retry(
      candidates: _session.candidates,
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bus Frequency Recommendations')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bus Frequency Recommendations',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Review deterministic service evidence before generating an AI recommendation.',
              ),
              const SizedBox(height: 16),
              if (_screening)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text('Preparing frequency evidence...'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_session.setupFailure)
                _messageCard(
                  context,
                  'Frequency evidence is temporarily unavailable.',
                )
              else if (_session.screeningComplete) ...[
                _evidenceOverview(context),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('generate-ai-recommendation'),
                  onPressed:
                      _session.candidates.isEmpty ||
                          _session.recommendationResult != null ||
                          _analysing
                      ? null
                      : _generate,
                  icon: _analysing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _analysing
                        ? 'Generating Recommendation...'
                        : 'Generate AI Recommendation',
                  ),
                ),
                if (_analysing) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(key: Key('analysis-progress')),
                ],
                if (_session.recommendationResult != null) ...[
                  const SizedBox(height: 24),
                  _recommendationResult(
                    context,
                    _session.recommendationResult!,
                  ),
                ],
              ],
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const Key('analyse-routes'),
                onPressed: _screening || _analysing
                    ? null
                    : _startNewAnalysis,
                icon: const Icon(Icons.refresh),
                label: const Text('Start New Analysis'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _evidenceOverview(BuildContext context) {
    final evidence = _session.candidates.map((item) => item.evidence).toList();
    final lateFeedback = evidence.fold<int>(
      0,
      (sum, item) =>
          sum +
          (item.feedback.countByIssueType[BusFrequencyFeedbackIssueTypes.busWasLate] ??
              0),
    );
    final overcrowdedFeedback = evidence.fold<int>(
      0,
      (sum, item) =>
          sum +
          (item.feedback.countByIssueType[
                  BusFrequencyFeedbackIssueTypes.busOvercrowded] ??
              0),
    );
    final didNotArriveFeedback = evidence.fold<int>(
      0,
      (sum, item) =>
          sum +
          (item.feedback.countByIssueType[
                  BusFrequencyFeedbackIssueTypes.busDidNotArrive] ??
              0),
    );
    return Card(
      key: const Key('frequency-evidence-overview'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Frequency Evidence',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric('Analysis Period', 'Past 30 Days'),
                _metric('Routes Analysed', '${_session.routesAnalysed}'),
                _metric(
                  'Scheduled Departures',
                  '${evidence.fold<int>(0, (sum, item) => sum + item.scheduledService.scheduledDepartureCount)}',
                ),
                _metric(
                  'Vehicle Position Observations',
                  '${evidence.fold<int>(0, (sum, item) => sum + item.operational.routePerformanceSummary.totalObservations)}',
                ),
                _metric(
                  'Delayed Trips',
                  '${evidence.fold<int>(0, (sum, item) => sum + item.operational.routePerformanceSummary.delayedTripCount)}',
                ),
                _metric(
                  'Relevant Passenger Feedback',
                  '${evidence.fold<int>(0, (sum, item) => sum + item.feedback.frequencyRelevantRecordCount)}',
                ),
              ],
            ),
            if (lateFeedback > 0 ||
                overcrowdedFeedback > 0 ||
                didNotArriveFeedback > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Feedback breakdown',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (lateFeedback > 0) Text('Late: $lateFeedback'),
                  if (overcrowdedFeedback > 0)
                    Text('Overcrowded: $overcrowdedFeedback'),
                  if (didNotArriveFeedback > 0)
                    Text('Did Not Arrive: $didNotArriveFeedback'),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('view-evidence-details'),
                  onPressed: () => _showEvidenceDetails(context),
                  child: const Text('View Evidence Details'),
                ),
                if (_session.excludedRoutes.isNotEmpty)
                  OutlinedButton(
                    key: const Key('view-limited-routes'),
                    onPressed: () => _showLimitedRoutes(context),
                    child: const Text('View Limited / Excluded Routes'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _recommendationResult(
    BuildContext context,
    BusFrequencyRecommendationResult result,
  ) {
    final synthesis = result.synthesis;
    if (synthesis == null) {
      return Card(
        key: const Key('feature-recommendation-failure'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                result.status ==
                        BusFrequencyRecommendationStatus.invalidAiResponse
                    ? 'Invalid AI Response'
                    : 'Recommendation Temporarily Unavailable',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(_failureMessage(result.failure)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('retry-feature-recommendation'),
                onPressed: _analysing ? null : _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Recommendation'),
              ),
            ],
          ),
        ),
      );
    }
    final actionableGroups = synthesis.recommendationGroups;
    return Column(
      key: const Key('grouped-recommendation-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recommendation Results',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Card(
          key: const Key('overall-ai-summary'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Overall AI Summary',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(synthesis.overallSummary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (actionableGroups.isEmpty)
          const Text(
            'No actionable recommendations are available with the current evidence.',
            key: Key('no-actionable-frequency-recommendations'),
          )
        else
          for (final group in actionableGroups) ...[
            _groupCard(context, group),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _groupCard(
    BuildContext context,
    BusFrequencyRecommendationGroup group,
  ) => Card(
    key: Key('action-group-${group.action.name}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _actionLabel(group.action),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _routeCountLabel(group.routeIds.length),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(group.summary),
          const SizedBox(height: 16),
          for (final recommendation in ( _expandedGroups.contains(group.action.name)
              ? group.routeRecommendations
              : group.routeRecommendations.take(3)))
            _routeRecommendationCard(context, recommendation),
          if (group.routeRecommendations.length > 3)
            TextButton(
              onPressed: () => setState(() {
                if (!_expandedGroups.add(group.action.name)) {
                  _expandedGroups.remove(group.action.name);
                }
              }),
              child: Text(
                _expandedGroups.contains(group.action.name)
                    ? 'Show fewer'
                    : 'Show ${group.routeRecommendations.length - 3} more routes',
              ),
            ),
        ],
      ),
    ),
  );

  Widget _routeRecommendationCard(
    BuildContext context,
    BusFrequencyRouteRecommendationRecord recommendation,
  ) {
    final routeId = recommendation.routeId;
    final candidate = _candidate(routeId);
    if (candidate == null) return const SizedBox.shrink();
    final evidence = candidate.evidence;
    final scheduled = evidence.scheduledService;
    final headways = scheduled.directionGroups
        .expand((direction) => direction.headwaysSeconds)
        .toList(growable: false);
    final peakSummary = evidence.operational.peakOperationSummary;
    final peakBucket = peakSummary.peakBucket;
    return Card(
      key: Key('group-route-$routeId'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              candidate.route.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text('Current Service', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _conciseEvidence(
                  'Scheduled departures',
                  '${scheduled.scheduledDepartureCount}',
                ),
                _conciseEvidence(
                  'Current Headway',
                  _headwaySummary(headways),
                ),
                if (peakSummary.hasReliablePeak && peakBucket != null)
                  _conciseEvidence(
                    'Peak Period',
                    _peakPeriodLabel(
                      peakBucket.startMinute,
                      peakBucket.endMinute,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Supporting Evidence', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _conciseEvidence(
                  'Delayed trips',
                  '${evidence.operational.routePerformanceSummary.delayedTripCount}',
                ),
                _conciseEvidence(
                  'Relevant feedback',
                  '${evidence.feedback.frequencyRelevantRecordCount}',
                ),
                if ((evidence.feedback.countByIssueType[
                            BusFrequencyFeedbackIssueTypes.busWasLate] ??
                        0) >
                    0)
                  _conciseEvidence(
                    'Late feedback',
                    '${evidence.feedback.countByIssueType[BusFrequencyFeedbackIssueTypes.busWasLate]}',
                  ),
                if ((evidence.feedback.countByIssueType[
                            BusFrequencyFeedbackIssueTypes.busOvercrowded] ??
                        0) >
                    0)
                  _conciseEvidence(
                    'Overcrowded feedback',
                    '${evidence.feedback.countByIssueType[BusFrequencyFeedbackIssueTypes.busOvercrowded]}',
                  ),
                if ((evidence.feedback.countByIssueType[
                            BusFrequencyFeedbackIssueTypes.busDidNotArrive] ??
                        0) >
                    0)
                  _conciseEvidence(
                    'Did Not Arrive feedback',
                    '${evidence.feedback.countByIssueType[BusFrequencyFeedbackIssueTypes.busDidNotArrive]}',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('AI Rationale', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(recommendation.conciseRationale),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('view-route-evidence-$routeId'),
                onPressed: () => _showRouteEvidence(context, candidate),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('View Evidence'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conciseEvidence(String label, String value) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 150),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  BusFrequencyDashboardCandidate? _candidate(String routeId) => _session
      .candidates
      .where((candidate) => candidate.route.routeId == routeId)
      .firstOrNull;

  Widget _metric(String label, String value) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 135),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Future<void> _showEvidenceDetails(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => FractionallySizedBox(
          heightFactor: .85,
          child: ListView(
            key: const Key('frequency-evidence-details'),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Frequency Evidence Details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final candidate in _session.candidates)
                _evidenceCard(context, candidate),
            ],
          ),
        ),
      );

  Widget _evidenceCard(
    BuildContext context,
    BusFrequencyDashboardCandidate candidate,
  ) {
    final evidence = candidate.evidence;
    final scheduled = evidence.scheduledService;
    final headways = scheduled.directionGroups
        .expand((direction) => direction.headwaysSeconds)
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              candidate.route.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Scheduled departures: ${scheduled.scheduledDepartureCount}'),
            Text('Headway intervals: $headways'),
            Text(
              'Peak Operation observations: ${evidence.operational.peakOperationSummary.observationCount}',
            ),
            Text(
              'Route Performance observations: ${evidence.operational.routePerformanceSummary.totalObservations}',
            ),
            Text(
              'Frequency-related feedback: ${evidence.feedback.frequencyRelevantRecordCount}',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRouteEvidence(
    BuildContext context,
    BusFrequencyDashboardCandidate candidate,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final evidence = candidate.evidence;
      final scheduled = evidence.scheduledService;
      final peak = evidence.operational.peakOperationSummary;
      final performance = evidence.operational.routePerformanceSummary;
      return FractionallySizedBox(
        heightFactor: .85,
        child: ListView(
          key: Key('route-evidence-details-${candidate.route.routeId}'),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              candidate.route.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _evidenceSection(context, 'Scheduled Service', [
              'Status: ${_scheduledStatusLabel(scheduled.status)}',
              'Scheduled departures: ${scheduled.scheduledDepartureCount}',
              'Directions represented: ${scheduled.directionGroups.length}',
              for (final direction in scheduled.directionGroups)
                '${_directionLabel(direction.directionId)} headway: '
                    '${_headwaySummary(direction.headwaysSeconds)}',
            ]),
            _evidenceSection(context, 'Operational Observations', [
              'Peak Operation observations: ${peak.observationCount}',
              'Peak Operation coverage: '
                  '${peak.hasReliablePeak ? 'Available' : 'Limited'}',
              'Route Performance observations: '
                  '${performance.totalObservations}',
              'Complete Route Performance trips: '
                  '${performance.completeTrips.length}',
            ]),
            _evidenceSection(context, 'Passenger Feedback', [
              'Frequency-related feedback: '
                  '${evidence.feedback.frequencyRelevantRecordCount}',
              'Total feedback records: ${evidence.feedback.totalRecordCount}',
            ]),
            _evidenceSection(
              context,
              'Limitations',
              _deterministicLimitations(evidence),
            ),
          ],
        ),
      );
    },
  );

  Widget _evidenceSection(
    BuildContext context,
    String title,
    List<String> values,
  ) => Padding(
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

  List<String> _deterministicLimitations(BusFrequencyEvidence evidence) {
    final scheduled = evidence.scheduledService;
    final values = <String>[
      if (scheduled.status != ScheduledServiceEvidenceStatus.available)
        'Scheduled service evidence is '
            '${_scheduledStatusLabel(scheduled.status).toLowerCase()}.',
      if (!scheduled.hasCompleteDirectionData)
        'Direction-level scheduled service evidence is incomplete.',
      if (scheduled.incompleteTripIds.isNotEmpty)
        'Some scheduled trips have incomplete evidence.',
      if (!evidence.operational.peakOperationSummary.hasReliablePeak)
        'Peak Operation coverage cannot identify a reliable peak.',
      if (evidence.operational.routePerformanceSummary.completeTrips.isEmpty)
        'No complete Route Performance trips are available.',
      if (evidence.feedback.totalRecordCount == 0)
        'No feedback records are available; this does not confirm that service has no problems.',
    ];
    return values.isEmpty
        ? const ['No deterministic evidence limitations were recorded.']
        : values;
  }

  Future<void> _showLimitedRoutes(BuildContext context) =>
      showModalBottomSheet<void>(
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
              for (final item in _session.excludedRoutes)
                ListTile(
                  title: Text(item.route.displayName),
                  subtitle: Text(_exclusionReason(item.reason)),
                ),
            ],
          ),
        ),
      );

  Widget _messageCard(BuildContext context, String message) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
    ),
  );
}

String _actionLabel(BusFrequencyRecommendationAction action) =>
    switch (action) {
      BusFrequencyRecommendationAction.increasePeakHourFrequency =>
        'Increase Peak-Hour Frequency',
      BusFrequencyRecommendationAction.maintainService =>
        'Maintain Current Frequency',
      BusFrequencyRecommendationAction.decreaseService => 'Decrease Frequency',
      BusFrequencyRecommendationAction.insufficientEvidence =>
        'Needs More Evidence',
    };

String _routeCountLabel(int count) =>
    '$count ${count == 1 ? 'Route' : 'Routes'}';

String _headwaySummary(Iterable<int> seconds) {
  final values = seconds.toList(growable: false)..sort();
  if (values.isEmpty) return 'Unavailable';
  final minimum = _durationLabel(values.first);
  final maximum = _durationLabel(values.last);
  return minimum == maximum ? minimum : '$minimum–$maximum range';
}

String _durationLabel(int seconds) {
  final minutes = seconds / 60;
  return minutes == minutes.roundToDouble()
      ? '${minutes.toInt()} min'
      : '${minutes.toStringAsFixed(1)} min';
}

String _peakPeriodLabel(int startMinute, int endMinute) =>
    '${_clockLabel(startMinute)}–${_clockLabel(endMinute)}';

String _clockLabel(int minute) {
  final hour24 = minute ~/ 60;
  final minutePart = minute % 60;
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour:${minutePart.toString().padLeft(2, '0')} '
      '${hour24 >= 12 ? 'PM' : 'AM'}';
}

String _directionLabel(int? directionId) =>
    directionId == null ? 'Unspecified direction' : 'Direction $directionId';

String _scheduledStatusLabel(ScheduledServiceEvidenceStatus status) =>
    switch (status) {
      ScheduledServiceEvidenceStatus.available => 'Available',
      ScheduledServiceEvidenceStatus.insufficientForHeadway =>
        'Insufficient for headway',
      ScheduledServiceEvidenceStatus.noDepartures => 'No departures',
      ScheduledServiceEvidenceStatus.incomplete => 'Incomplete',
    };

String _exclusionReason(
  BusFrequencyDashboardExclusionReason reason,
) => switch (reason) {
  BusFrequencyDashboardExclusionReason.noScheduledDepartures =>
    'No current scheduled departures.',
  BusFrequencyDashboardExclusionReason.noSupportingEvidence =>
    'No headway, operational observation, or relevant feedback evidence is available.',
  BusFrequencyDashboardExclusionReason.evidenceLoadingFailure =>
    'Evidence could not be loaded.',
};

String _failureMessage(BusFrequencyRecommendationFailure? failure) =>
    switch (failure) {
      BusFrequencyRecommendationFailure.routeLimitExceeded =>
        'The analysis contains more than 20 eligible routes.',
      BusFrequencyRecommendationFailure.timeout =>
        'The recommendation request timed out.',
      BusFrequencyRecommendationFailure.rateLimited =>
        'The recommendation service is busy. Try again later.',
      BusFrequencyRecommendationFailure.authentication ||
      BusFrequencyRecommendationFailure.geminiNotConfigured =>
        'The recommendation service is not configured.',
      BusFrequencyRecommendationFailure.invalidResponse ||
      BusFrequencyRecommendationFailure.unknownRoute ||
      BusFrequencyRecommendationFailure.unknownEvidenceReference ||
      BusFrequencyRecommendationFailure.malformedResponse =>
        'The response did not pass evidence validation.',
      BusFrequencyRecommendationFailure.evidenceUnavailable =>
        'The retained evidence is unavailable.',
      BusFrequencyRecommendationFailure.network ||
      BusFrequencyRecommendationFailure.http ||
      null => 'The recommendation service could not complete the request.',
    };
