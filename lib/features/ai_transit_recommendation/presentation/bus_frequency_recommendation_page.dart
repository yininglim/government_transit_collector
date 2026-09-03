import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_repository.dart';
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
  String? _retryingRouteId;

  List<BusFrequencyDashboardCandidate> get _candidates => _session.candidates;
  List<BusFrequencyDashboardEntry> get _entries => _session.entries;
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

  Future<void> _startAnalysis() async {
    if (_screening || _analysing || _retryingRouteId != null) return;
    final period = _newPeriod();
    setState(() {
      _session.begin(period.startUtc, period.endUtc);
      _screening = true;
    });
    try {
      final candidates = await _coordinator.screenCandidates(
        startUtc: period.startUtc,
        endExclusiveUtc: period.endUtc,
      );
      if (!mounted) return;
      setState(() {
        _candidates.addAll(candidates);
        _screening = false;
        _empty = candidates.isEmpty;
      });
      if (candidates.isNotEmpty) await _analyseNextBatch();
    } on Object {
      if (!mounted) return;
      setState(() {
        _screening = false;
        _setupFailure = true;
      });
    }
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
    final total = remaining.length.clamp(0, busFrequencyDashboardBatchSize);
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

  Future<void> _retry(BusFrequencyDashboardEntry entry) async {
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
    appBar: AppBar(title: const Text('Bus Frequency Recommendations')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(),
          const SizedBox(height: 16),
          _analysisCard(),
          if (_screening || _analysing) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(key: Key('analysis-progress')),
            const SizedBox(height: 8),
            Text(
              _screening
                  ? 'Screening routes using deterministic evidence…'
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
              'No routes currently have enough deterministic evidence for AI frequency analysis over the past 30 days.',
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
                onPressed: _analysing || _screening || _retryingRouteId != null
                    ? null
                    : _analyseNextBatch,
                icon: const Icon(Icons.navigate_next),
                label: Text('Analyse Next Routes ($_remainingCount remaining)'),
              ),
            ],
          ],
        ],
      ),
    ),
  );

  Widget _header() => Row(
    children: [
      Icon(
        Icons.schedule,
        size: 40,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bus Frequency Recommendations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Review evidence-grounded service actions across eligible routes.',
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
                : _startAnalysis,
            icon: const Icon(Icons.auto_awesome),
            label: Text(
              _entries.isEmpty ? 'Analyse Routes' : 'Start New Analysis',
            ),
          ),
        ],
      ),
    ),
  );

  Widget _resultCard(BusFrequencyDashboardEntry entry) {
    final recommendation = entry.result.recommendation;
    final failure =
        entry.result.status ==
            BusFrequencyRecommendationStatus.temporarilyUnavailable ||
        entry.result.status ==
            BusFrequencyRecommendationStatus.invalidAiResponse;
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

  Future<void> _showDetails(BusFrequencyDashboardEntry entry) =>
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

String _actionLabel(BusFrequencyRecommendationAction action) =>
    switch (action) {
      BusFrequencyRecommendationAction.increaseService => 'Increase Service',
      BusFrequencyRecommendationAction.maintainService => 'Maintain Service',
      BusFrequencyRecommendationAction.decreaseService => 'Decrease Service',
      BusFrequencyRecommendationAction.insufficientEvidence =>
        'Insufficient Evidence',
    };

String _sufficiencyLabel(BusFrequencyEvidenceSufficiency value) =>
    switch (value) {
      BusFrequencyEvidenceSufficiency.sufficient => 'Sufficient',
      BusFrequencyEvidenceSufficiency.limited => 'Limited',
      BusFrequencyEvidenceSufficiency.insufficient => 'Insufficient',
    };

String _routeFailureTitle(BusFrequencyRecommendationResult result) =>
    result.status == BusFrequencyRecommendationStatus.invalidAiResponse
    ? 'Response Could Not Be Validated'
    : 'Recommendation Temporarily Unavailable';

String _failureMessage(BusFrequencyRecommendationFailure? failure) =>
    switch (failure) {
      BusFrequencyRecommendationFailure.timeout =>
        'The request timed out. Retry manually when ready.',
      BusFrequencyRecommendationFailure.network =>
        'The AI service could not be reached.',
      BusFrequencyRecommendationFailure.http =>
        'The AI service returned an unavailable response.',
      BusFrequencyRecommendationFailure.rateLimited =>
        'The AI service rate limit was reached.',
      BusFrequencyRecommendationFailure.authentication =>
        'The AI service is unavailable with the current configuration.',
      BusFrequencyRecommendationFailure.geminiNotConfigured =>
        'AI recommendation is not configured.',
      BusFrequencyRecommendationFailure.evidenceUnavailable =>
        'Route evidence could not be prepared.',
      _ => 'The AI response could not be validated. Please try again.',
    };

String _evidenceLabel(String reference) {
  if (reference == 'scheduled.summary') return 'Scheduled service summary';
  if (reference.startsWith('scheduled.direction.')) {
    return 'Scheduled direction evidence';
  }
  return switch (reference) {
    'operational.peak_operation' => 'Peak operation evidence',
    'operational.route_performance' => 'Route performance evidence',
    'feedback.bus_was_late' => 'Late bus feedback',
    'feedback.bus_overcrowded' => 'Overcrowding feedback',
    'feedback.bus_did_not_arrive' => 'Bus non-arrival feedback',
    _ => 'Evidence reference',
  };
}
