import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:timezone/timezone.dart' as timezone;

class BusFrequencyRecommendationPage extends StatefulWidget {
  const BusFrequencyRecommendationPage({
    this.session,
    this.coordinator,
    this.recommendationRepository,
    this.evidenceRepository,
    this.routeRepository,
    this.now,
    super.key,
  });
  final BusFrequencyDashboardSession? session;
  final BusFrequencyDashboardCoordinator? coordinator;
  final BusFrequencyRecommendationRepository? recommendationRepository;
  final BusFrequencyEvidenceRepository? evidenceRepository;
  final RoutePerformanceRepository? routeRepository;
  final DateTime Function()? now;
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
        !_session.matchesPeriod(period.startUtc, period.endUtc))
      _session.clear();
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
    if (_screening || _analysing) return;
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
        _session.candidates.addAll(result.candidates);
        _session.excludedRoutes.addAll(result.excludedRoutes);
        _session.routesAnalysed = result.routesAnalysed;
        _session.screeningComplete = true;
        _session.empty = result.candidates.isEmpty;
        _screening = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _screening = false;
        _session.setupFailure = true;
      });
    }
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
        end == null)
      return;
    setState(() => _analysing = true);
    final result = await _coordinator.analyse(
      candidates: _session.candidates,
      startUtc: start,
      endExclusiveUtc: end,
    );
    if (!mounted) return;
    setState(() {
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
                onPressed: _screening || _analysing ? null : _prepareEvidence,
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
    return Card(
      key: const Key('frequency-evidence-overview'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Frequency Evidence Coverage',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric('Analysis Period', 'Past 30 Days'),
                _metric('Routes Analysed', '${_session.routesAnalysed}'),
                _metric('Eligible Routes', '${_session.candidates.length}'),
                _metric(
                  'Limited / Excluded Routes',
                  '${_session.excludedRoutes.length}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _coverageRow(
              'Scheduled Service',
              _coverage(
                evidence,
                (item) =>
                    item.scheduledService.status ==
                    ScheduledServiceEvidenceStatus.available,
              ),
            ),
            _coverageRow(
              'Headway Evidence',
              _coverage(
                evidence,
                (item) => item.scheduledService.directionGroups.any(
                  (direction) => direction.headwaysSeconds.isNotEmpty,
                ),
              ),
            ),
            _coverageRow(
              'Operational Evidence',
              _coverage(
                evidence,
                (item) =>
                    item.operational.peakOperationSummary.observationCount >
                        0 ||
                    item.operational.routePerformanceSummary.totalObservations >
                        0,
              ),
            ),
            _coverageRow(
              'Frequency-related Feedback',
              _coverage(
                evidence,
                (item) => item.feedback.frequencyRelevantRecordCount > 0,
              ),
            ),
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
    return Column(
      key: const Key('grouped-recommendation-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recommendation Results',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(synthesis.overallSummary),
        const SizedBox(height: 12),
        for (final group in synthesis.recommendationGroups) ...[
          _groupCard(context, group),
          const SizedBox(height: 12),
        ],
        if (synthesis.needsMoreEvidence != null)
          _needsEvidenceCard(context, synthesis.needsMoreEvidence!),
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
          Text(
            _actionLabel(group.action),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(group.summary),
          const SizedBox(height: 12),
          for (final routeId in group.routeIds)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• ${_routeDisplay(routeId)}',
                key: Key('group-route-$routeId'),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _needsEvidenceCard(
    BuildContext context,
    BusFrequencyRecommendationGroup group,
  ) => Card(
    key: const Key('post-gemini-needs-evidence'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Needs More Evidence',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(group.summary),
          const SizedBox(height: 8),
          for (final routeId in group.routeIds)
            Text('• ${_routeDisplay(routeId)}'),
        ],
      ),
    ),
  );

  String _routeDisplay(String routeId) =>
      _session.candidates
          .where((candidate) => candidate.route.routeId == routeId)
          .map((candidate) => candidate.route.displayName)
          .firstOrNull ??
      routeId;

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

  Widget _coverageRow(String label, String status) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            status,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  String _coverage(
    List<BusFrequencyEvidence> evidence,
    bool Function(BusFrequencyEvidence) available,
  ) {
    if (evidence.isEmpty) return 'Missing';
    final count = evidence.where(available).length;
    if (count == evidence.length) return 'Available';
    return count == 0 ? 'Missing' : 'Limited';
  }

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
