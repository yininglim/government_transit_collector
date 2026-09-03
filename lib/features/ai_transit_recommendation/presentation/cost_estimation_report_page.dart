import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:timezone/timezone.dart' as timezone;

class CostEstimationReportPage extends StatefulWidget {
  const CostEstimationReportPage({
    this.session,
    this.coordinator,
    this.recommendationRepository,
    this.evidenceRepository,
    this.routeRepository,
    this.now,
    super.key,
  });

  final CostDashboardSession? session;
  final CostDashboardCoordinator? coordinator;
  final CostRecommendationRepository? recommendationRepository;
  final FuelCostCalculationRepository? evidenceRepository;
  final RoutePerformanceRepository? routeRepository;
  final DateTime Function()? now;

  @override
  State<CostEstimationReportPage> createState() =>
      _CostEstimationReportPageState();
}

class _CostEstimationReportPageState extends State<CostEstimationReportPage> {
  late final CostDashboardCoordinator _coordinator;
  late final CostDashboardSession _session;
  bool _screening = false;
  bool _analysing = false;
  String? _retryingRouteId;

  List<CostDashboardCandidate> get _candidates => _session.candidates;
  List<CostDashboardEntry> get _entries => _session.entries;
  DateTime? get _periodStartUtc => _session.periodStartUtc;
  DateTime? get _periodEndUtc => _session.periodEndUtc;
  DateTime? get _referenceDate => _session.referenceDate;
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
    _session = widget.session ?? CostDashboardSession();
    _coordinator =
        widget.coordinator ??
        CostDashboardCoordinator(
          routeRepository: widget.routeRepository,
          evidenceRepository: widget.evidenceRepository,
          recommendationRepository: widget.recommendationRepository,
        );
    final period = _newPeriod();
    if (_session.periodStartUtc != null &&
        !_session.matchesPeriod(
          period.startUtc,
          period.endUtc,
          period.referenceDate,
        )) {
      _session.clear();
    }
  }

  ({DateTime startUtc, DateTime endUtc, DateTime referenceDate}) _newPeriod() {
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
      referenceDate: DateTime(now.year, now.month, now.day),
    );
  }

  Future<void> _startAnalysis() async {
    if (_screening || _analysing || _retryingRouteId != null) return;
    final period = _newPeriod();
    setState(() {
      _session.begin(period.startUtc, period.endUtc, period.referenceDate);
      _screening = true;
    });
    try {
      final candidates = await _coordinator.screenCandidates(
        startUtc: period.startUtc,
        endExclusiveUtc: period.endUtc,
        referenceDate: period.referenceDate,
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
    final reference = _referenceDate;
    if (_analysing ||
        _retryingRouteId != null ||
        start == null ||
        end == null ||
        reference == null)
      return;
    final remaining = _candidates.skip(_nextCandidateIndex).toList();
    if (remaining.isEmpty) return;
    final total = remaining.length.clamp(0, costDashboardBatchSize);
    setState(() {
      _analysing = true;
      _completedInBatch = 0;
      _batchTotal = total;
    });
    await _coordinator.analyseBatch(
      candidates: remaining,
      startUtc: start,
      endExclusiveUtc: end,
      referenceDate: reference,
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

  Future<void> _retry(CostDashboardEntry entry) async {
    if (_screening || _analysing || _retryingRouteId != null) return;
    final start = _periodStartUtc;
    final end = _periodEndUtc;
    final reference = _referenceDate;
    final candidate = _candidates
        .where((item) => item.route.routeId == entry.route.routeId)
        .firstOrNull;
    if (start == null || end == null || reference == null || candidate == null)
      return;
    setState(() => _retryingRouteId = entry.route.routeId);
    try {
      final replacement = await _coordinator.retry(
        candidate: candidate,
        startUtc: start,
        endExclusiveUtc: end,
        referenceDate: reference,
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

  FuelCostCalculationEvidence? _evidenceFor(CostDashboardEntry entry) =>
      entry.result.evidence ??
      _candidates
          .where((candidate) => candidate.route.routeId == entry.route.routeId)
          .firstOrNull
          ?.evidence;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cost Recommendations')),
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
                  ? 'Screening routes using deterministic cost evidence...'
                  : 'Analysing route ${(_completedInBatch + 1).clamp(1, _batchTotal)} of $_batchTotal',
              key: const Key('analysis-progress-label'),
              textAlign: TextAlign.center,
            ),
          ],
          if (_setupFailure) ...[
            const SizedBox(height: 16),
            _messageCard(
              'Cost evidence could not be prepared.',
              'Start a new analysis when the data service is available.',
            ),
          ],
          if (_empty) ...[
            const SizedBox(height: 16),
            _messageCard(
              'No eligible routes',
              'No routes currently have enough deterministic fuel-cost evidence for AI analysis over the past 30 days.',
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
        Icons.request_quote_outlined,
        size: 40,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cost Recommendations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Review evidence-grounded fuel-cost actions across eligible routes.',
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

  Widget _resultCard(CostDashboardEntry entry) {
    final recommendation = entry.result.recommendation;
    final evidence = _evidenceFor(entry);
    final failure =
        entry.result.status ==
            CostRecommendationStatus.temporarilyUnavailable ||
        entry.result.status == CostRecommendationStatus.invalidAiResponse;
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
                  ? _failureTitle(entry.result)
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
            if (evidence != null) ...[
              const SizedBox(height: 12),
              Text(
                'Deterministic Fuel Expenditure Range',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(_fuelRange(evidence)),
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

  Future<void> _showDetails(
    CostDashboardEntry entry,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final evidence = _evidenceFor(entry);
      return DraggableScrollableSheet(
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
              _detail('Recommendation', _failureTitle(entry.result)),
              const SizedBox(height: 12),
              Text(_failureMessage(entry.result.failure)),
            ],
            if (evidence != null) ...[
              const Divider(height: 32),
              Text(
                'Deterministic Cost Evidence',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_unavailableCategories(entry).isNotEmpty) ...[
                const SizedBox(height: 12),
                _section(
                  'Unavailable Cost Categories',
                  _unavailableCategories(entry),
                ),
                const SizedBox(height: 12),
              ],
              _detail(
                'Diesel Price',
                'RM ${evidence.dieselPrice.rmPerLitre!.toStringAsFixed(2)} per litre',
              ),
              _detail(
                'Diesel Effective Date',
                _date(evidence.dieselPrice.effectiveDate!),
              ),
              _detail(
                'Scheduled Vehicle-km',
                evidence.scheduledVehicleKilometres.toStringAsFixed(2),
              ),
              _detail('Fuel Expenditure Range', _fuelRange(evidence)),
              _detail(
                'Costable Departures',
                '${evidence.costableScheduledDepartureCount}',
              ),
              _detail(
                'Uncostable Departures',
                '${evidence.uncostableDepartures.length}',
              ),
              const SizedBox(height: 12),
              const Text(
                'Fuel expenditure is only one component of operating cost.',
              ),
            ],
          ],
        ),
      );
    },
  );

  List<String> _unavailableCategories(CostDashboardEntry entry) {
    final values = entry.result.payload
        ?.toJson()['unavailable_cost_categories'];
    if (values is! List<dynamic>) return const [];
    return values
        .whereType<String>()
        .map(_categoryLabel)
        .toList(growable: false);
  }

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
          width: 150,
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

String _fuelRange(FuelCostCalculationEvidence evidence) {
  final low = evidence.lowEstimatedFuelCostRm;
  final high = evidence.highEstimatedFuelCostRm;
  if (low == null || high == null) return 'Unavailable';
  return 'RM ${low.toStringAsFixed(2)} – RM ${high.toStringAsFixed(2)}';
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _actionLabel(CostRecommendationAction action) => switch (action) {
  CostRecommendationAction.costEfficiencyReview => 'Cost Efficiency Review',
  CostRecommendationAction.fuelCostConcern => 'Fuel Cost Concern',
  CostRecommendationAction.maintainCurrentCostProfile =>
    'Maintain Current Cost Profile',
  CostRecommendationAction.insufficientEvidence => 'Insufficient Evidence',
};

String _sufficiencyLabel(CostEvidenceSufficiency value) => switch (value) {
  CostEvidenceSufficiency.sufficient => 'Sufficient',
  CostEvidenceSufficiency.limited => 'Limited',
  CostEvidenceSufficiency.insufficient => 'Insufficient',
};

String _failureTitle(CostRecommendationResult result) =>
    result.status == CostRecommendationStatus.invalidAiResponse
    ? 'Response Could Not Be Validated'
    : 'Recommendation Temporarily Unavailable';

String _failureMessage(CostRecommendationFailure? failure) => switch (failure) {
  CostRecommendationFailure.timeout =>
    'The request timed out. Retry manually when ready.',
  CostRecommendationFailure.network => 'The AI service could not be reached.',
  CostRecommendationFailure.http =>
    'The AI service returned an unavailable response.',
  CostRecommendationFailure.rateLimited =>
    'The AI service rate limit was reached.',
  CostRecommendationFailure.authentication =>
    'The AI service is unavailable with the current configuration.',
  CostRecommendationFailure.geminiNotConfigured =>
    'AI recommendation is not configured.',
  CostRecommendationFailure.evidenceUnavailable =>
    'Cost evidence could not be prepared.',
  _ => 'The AI response could not be validated. Please try again.',
};

String _evidenceLabel(String reference) {
  if (reference.startsWith('cost.direction.'))
    return 'Direction-level scheduled service evidence';
  return switch (reference) {
    'cost.diesel_price' => 'Official diesel price evidence',
    'cost.fuel_consumption_benchmark' => 'Fuel-consumption benchmark evidence',
    'cost.scheduled_vehicle_km' => 'Scheduled vehicle-km evidence',
    'cost.fuel_range' => 'Deterministic fuel-expenditure range',
    _ => 'Evidence reference',
  };
}

String _categoryLabel(String value) => switch (value) {
  'driver_staff_cost' => 'Driver and staff cost',
  'maintenance_cost' => 'Maintenance cost',
  'bus_acquisition_cost' => 'Bus acquisition cost',
  'bus_stop_construction_cost' => 'Bus stop construction cost',
  'total_implementation_cost' => 'Total implementation cost',
  _ => value,
};
