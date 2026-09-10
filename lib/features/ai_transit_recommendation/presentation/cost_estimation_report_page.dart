import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_scenario.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/numeric_display.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

class CostEstimationReportPage extends StatefulWidget {
  const CostEstimationReportPage({
    this.session,
    this.coordinator,
    this.recommendationRepository,
    this.evidenceRepository,
    this.routeRepository,
    this.now,
    this.preparationScheduler,
    this.busFrequencySession,
    this.preserveRetainedSession = false,
    super.key,
  });

  final CostDashboardSession? session;
  final CostDashboardCoordinator? coordinator;
  final CostRecommendationRepository? recommendationRepository;
  final FuelCostCalculationRepository? evidenceRepository;
  final RoutePerformanceRepository? routeRepository;
  final DateTime Function()? now;
  final Future<void> Function()? preparationScheduler;
  final BusFrequencyDashboardSession? busFrequencySession;
  final bool preserveRetainedSession;

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
  final _additionalBusesController = TextEditingController();
  final _additionalDriversController = TextEditingController();
  final _additionalBusesFocusNode = FocusNode();
  final _additionalDriversFocusNode = FocusNode();

  String? get _additionalBusesError => _session.additionalBusesError;
  set _additionalBusesError(String? value) =>
      _session.additionalBusesError = value;
  String? get _additionalDriversError => _session.additionalDriversError;
  set _additionalDriversError(String? value) =>
      _session.additionalDriversError = value;
  String? get _selectedScenarioRouteId => _session.selectedScenarioRouteId;
  set _selectedScenarioRouteId(String? value) =>
      _session.selectedScenarioRouteId = value;
  String? get _costReportActionKey => _session.costReportActionKey;
  set _costReportActionKey(String? value) =>
      _session.costReportActionKey = value;
  bool get _resourceCostReady => _session.resourceCostReady;
  set _resourceCostReady(bool value) => _session.resourceCostReady = value;

  @override
  void dispose() {
    _additionalBusesController.dispose();
    _additionalDriversController.dispose();
    _additionalBusesFocusNode.dispose();
    _additionalDriversFocusNode.dispose();
    super.dispose();
  }

  List<CostDashboardCandidate> get _candidates => _session.candidates;
  List<CostDashboardEntry> get _entries => _session.entries;
  DateTime? get _periodStartUtc => _session.periodStartUtc;
  DateTime? get _periodEndUtc => _session.periodEndUtc;
  DateTime? get _referenceDate => _session.referenceDate;
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
    _additionalBusesController.text = _session.additionalBusesInput;
    _additionalDriversController.text = _session.additionalDriversInput;
    _additionalBusesFocusNode.addListener(() {
      if (!_additionalBusesFocusNode.hasFocus) {
        _validateResourceField(
          _additionalBusesController,
          'Additional buses',
          maxAdditionalBusPlanningCount,
          (error) => _additionalBusesError = error,
        );
      }
    });
    _additionalDriversFocusNode.addListener(() {
      if (!_additionalDriversFocusNode.hasFocus) {
        _validateResourceField(
          _additionalDriversController,
          'Additional drivers',
          maxAdditionalDriverPlanningCount,
          (error) => _additionalDriversError = error,
        );
      }
    });
    _coordinator =
        widget.coordinator ??
        CostDashboardCoordinator(
          routeRepository: widget.routeRepository,
          evidenceRepository: widget.evidenceRepository,
          recommendationRepository: widget.recommendationRepository,
        );
    final period = _newPeriod();
    if (!widget.preserveRetainedSession &&
        _session.periodStartUtc != null &&
        !_session.matchesPeriod(
          period.startUtc,
          period.endUtc,
          period.referenceDate,
        )) {
      _session.clear();
    }
  }

  ({DateTime startUtc, DateTime endUtc, DateTime referenceDate}) _newPeriod() {
    return costAnalysisPeriod(now: widget.now);
  }

  Future<void> _startAnalysis() async {
    if (_screening || _analysing || _retryingRouteId != null) return;
    final period = _newPeriod();
    setState(() {
      _session.clear();
      _selectedScenarioRouteId = null;
      _costReportActionKey = null;
      _resourceCostReady = false;
      _additionalBusesController.clear();
      _additionalDriversController.clear();
      _session.additionalBusesInput = '';
      _session.additionalDriversInput = '';
      _additionalBusesError = null;
      _additionalDriversError = null;
      _screening = true;
    });
    try {
      await (widget.preparationScheduler?.call() ??
          _coordinator.prepareSession(
            session: _session,
            startUtc: period.startUtc,
            endExclusiveUtc: period.endUtc,
            referenceDate: period.referenceDate,
          ));
      if (!mounted) return;
      final candidates = _candidates.toList(growable: false);
      setState(() {
        _screening = false;
        _empty = candidates.isEmpty;
      });
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
    final selectedRouteId = _selectedScenarioRouteId ??
        _frequencyRecommendations.firstOrNull?.routeId;
    final scopedCandidates = selectedRouteId == null
        ? const <CostDashboardCandidate>[]
        : _candidates
              .where((candidate) =>
                  candidate.route.routeId == selectedRouteId)
              .toList(growable: false);
    final remaining = scopedCandidates
        .skip(_nextCandidateIndex)
        .toList();
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
      planningContext: _planningContext,
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
        planningContext: _planningContext,
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

  FuelCostCalculationEvidence? _evidenceFor(CostDashboardEntry entry) =>
      entry.result.evidence ??
      _candidates
          .where((candidate) => candidate.route.routeId == entry.route.routeId)
          .firstOrNull
          ?.evidence;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cost Estimation Report')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(),
          const SizedBox(height: 16),
          _analysisCard(),
          if (_frequencyRecommendations.isEmpty) ...[
            const SizedBox(height: 16),
            _messageCard(
              'No Bus Frequency Recommendation Yet',
              'Generate a Bus Frequency Recommendation first to estimate the cost impact of a frequency change.',
            ),
          ] else ...[
            const SizedBox(height: 16),
            _selectionCard(),
            if (_selectedCostCandidate case final selected?) ...[
              const SizedBox(height: 16),
              _evidenceOverview(selected.evidence),
              const SizedBox(height: 16),
              _costPlanCard(selected),
              if (_hasValidScenarioForInsight) ...[
                const SizedBox(height: 16),
                _aiCostInsightSection(),
              ],
            ] else if (_setupFailure) ...[
              const SizedBox(height: 16),
              _messageCard(
                'Cost evidence could not be prepared.',
                'Start a new analysis when the data service is available.',
              ),
            ] else if (!_session.screeningComplete || _screening) ...[
              const SizedBox(height: 16),
              _messageCard(
                'Preparing selected route cost evidence...',
                'The current route evidence is still being prepared.',
              ),
            ] else ...[
              const SizedBox(height: 16),
              _messageCard(
                'Cost Evidence Unavailable',
                'The selected route does not have enough deterministic cost evidence for this report.',
              ),
            ],
          ],
          if (_analysing && !_hasValidScenarioForInsight) ...[
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
              'Cost Estimation Report',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Estimate supported costs for the selected Bus Frequency Recommendation.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _analysisCard() => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      key: const Key('analyse-routes'),
      onPressed: _screening || _analysing || _retryingRouteId != null
          ? null
          : _startAnalysis,
      icon: const Icon(Icons.refresh),
      label: const Text('Start New Analysis'),
    ),
  );

  Widget _evidenceOverview(FuelCostCalculationEvidence evidence) {
    final analysisDays = evidence.periodEnd.difference(evidence.periodStart).inDays;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cost Estimation Evidence',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _detail(
              '$analysisDays-Day Scheduled Departures',
              displayCount(evidence.totalScheduledDepartureCount),
            ),
            _detail(
              '$analysisDays-Day Scheduled Vehicle-km',
              '${displayDecimal(evidence.scheduledVehicleKilometres)} km',
            ),
            if (evidence.dieselPrice.rmPerLitre case final price?)
              _detail('Diesel Price Used', '${displayMoney(price)} / L'),
            const SizedBox(height: 16),
            ..._currentServiceEvidence(evidence),
          ],
        ),
      ),
    );
  }

  Widget _aiCostInsightSection() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Cost Insight',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_entries.isNotEmpty) ...[
            for (final entry in _entries) _resultCard(entry),
          ] else if (_analysing) ...[
            const LinearProgressIndicator(key: Key('cost-insight-progress')),
            const SizedBox(height: 8),
            const Text('Generating AI Cost Insight...'),
          ] else
            FilledButton.icon(
              key: const Key('generate-cost-insight'),
              onPressed: _canGenerateInsight ? _analyseNextBatch : null,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate AI Cost Insight'),
            ),
        ],
      ),
    ),
  );

  BusFrequencyRouteRecommendationRecord? get _selectedFrequencyRecommendation {
    final recommendations = _frequencyRecommendations;
    if (recommendations.isEmpty) return null;
    return recommendations
            .where((record) => record.routeId == _selectedScenarioRouteId)
            .firstOrNull ??
        recommendations.first;
  }

  CostDashboardCandidate? get _selectedCostCandidate {
    final recommendation = _selectedFrequencyRecommendation;
    if (recommendation == null) return null;
    return _candidates
        .where(
          (candidate) => candidate.route.routeId == recommendation.routeId,
        )
        .firstOrNull;
  }

  Widget _selectionCard() {
    final recommendations = _frequencyRecommendations;
    final selectedRecommendation = _selectedFrequencyRecommendation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Selected Recommendation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedRecommendation?.routeId,
              menuMaxHeight: 240,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Select Bus Frequency Recommendation',
              ),
              items: [
                for (final record in recommendations)
                  DropdownMenuItem(
                    value: record.routeId,
                    child: Text(
                      '${_routeName(record.routeId)} \u2014 ${_frequencyActionLabel(record.action)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _selectRecommendation,
            ),
            if (selectedRecommendation != null) ...[
              const SizedBox(height: 8),
              _detail('Route', _routeName(selectedRecommendation.routeId)),
              _detail(
                'Recommendation',
                _frequencyActionLabel(selectedRecommendation.action),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _selectRecommendation(String? routeId) {
    setState(() {
      _selectedScenarioRouteId = routeId;
      _resourceCostReady = false;
      _costReportActionKey = null;
      _session.calculatedPlanningContext = null;
      _additionalBusesController.clear();
      _additionalDriversController.clear();
      _session.additionalBusesInput = '';
      _session.additionalDriversInput = '';
      _additionalBusesError = null;
      _additionalDriversError = null;
      _entries.clear();
      _nextCandidateIndex = 0;
      _completedInBatch = 0;
      _batchTotal = 0;
    });
  }

  Widget _costPlanCard(CostDashboardCandidate selected) {
    final recommendation = _selectedFrequencyRecommendation;
    if (recommendation == null) {
      return _messageCard(
        'Cost Scenario Unavailable',
        'The selected Bus Frequency Recommendation is no longer available.',
      );
    }
    final isIncrease =
        recommendation.action ==
        BusFrequencyRecommendationAction.increasePeakHourFrequency;
    final isDecrease =
        recommendation.action ==
        BusFrequencyRecommendationAction.decreaseService;
    final reportReady = _isCostReportReady(recommendation);
    final calculated = _session.calculatedPlanningContext;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isIncrease) ...[
              Text(
                'Planning Assumptions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _resourceField(
                _additionalBusesController,
                'Additional Buses',
                focusNode: _additionalBusesFocusNode,
                errorText: _additionalBusesError,
              ),
              _resourceField(
                _additionalDriversController,
                'Additional Drivers',
                focusNode: _additionalDriversFocusNode,
                errorText: _additionalDriversError,
              ),
              const Text(
                'Planning bases: RM 700,000 per diesel bus; RM 2,500\u2013RM 3,500 per driver per month.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('calculate-cost'),
                onPressed: () => _calculateResourceCosts(
                  selected,
                  recommendation,
                ),
                child: const Text('Calculate Cost'),
              ),
            ],
            if (reportReady) ...[
              if (isIncrease) const SizedBox(height: 20),
              Text(
                'Estimated Cost',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (isIncrease) ...[
                const SizedBox(height: 12),
                Text(
                  'One-off',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                _detail(
                  'Estimated Bus Acquisition Cost',
                  calculated?.estimatedBusAcquisitionCostRm == null
                      ? 'Unavailable'
                      : displayMoney(
                          calculated!.estimatedBusAcquisitionCostRm!,
                        ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Recurring',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                _detail(
                  'Estimated Monthly Driver Cost',
                  calculated?.lowMonthlyDriverCostRm == null ||
                          calculated?.highMonthlyDriverCostRm == null
                      ? 'Unavailable'
                      : '${displayMoney(calculated!.lowMonthlyDriverCostRm!)} \u2013 ${displayMoney(calculated!.highMonthlyDriverCostRm!)} / month',
                ),
              ],
              const SizedBox(height: 12),
              Text('Fuel', style: Theme.of(context).textTheme.titleSmall),
              _detail('Estimated Fuel Cost', _fuelRange(selected.evidence)),
              const SizedBox(height: 8),
              const Text(
                'Based on current scheduled service over the 30-day analysis period and the applicable diesel price.',
              ),
              if (isDecrease) ...[
                const SizedBox(height: 12),
                const Text(
                  'Exact fuel savings cannot be estimated until a specific service reduction is defined.',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  bool _isCostReportReady(
    BusFrequencyRouteRecommendationRecord recommendation,
  ) {
    if (recommendation.action !=
        BusFrequencyRecommendationAction.increasePeakHourFrequency) {
      return true;
    }
    return _resourceCostReady &&
        _costReportActionKey == recommendation.action.name &&
        _selectedScenarioRouteId == recommendation.routeId &&
        _session.calculatedPlanningContext?.routeId == recommendation.routeId &&
        _session.calculatedPlanningContext?.busFrequencyAction ==
            recommendation.action.name;
  }

  void _calculateResourceCosts(
    CostDashboardCandidate selected,
    BusFrequencyRouteRecommendationRecord recommendation,
  ) {
    final buses = parseNonNegativeResource(
      _additionalBusesController.text,
      'Additional buses',
      maximum: maxAdditionalBusPlanningCount,
    );
    final drivers = parseNonNegativeResource(
      _additionalDriversController.text,
      'Additional drivers',
      maximum: maxAdditionalDriverPlanningCount,
    );
    setState(() {
      _additionalBusesError = buses.error;
      _additionalDriversError = drivers.error;
      if (buses.error != null || drivers.error != null) {
        _resourceCostReady = false;
        _costReportActionKey = null;
        _session.calculatedPlanningContext = null;
        return;
      }
      _selectedScenarioRouteId = selected.route.routeId;
      _resourceCostReady = true;
      _costReportActionKey = recommendation.action.name;
      _session.calculatedPlanningContext = CostPlanningContext(
        routeId: selected.route.routeId,
        busFrequencyAction: recommendation.action.name,
        additionalBuses: buses.value,
        additionalDrivers: drivers.value,
        estimatedBusAcquisitionCostRm: buses.value == null
            ? null
            : buses.value! * additionalDieselBusCostRm,
        lowMonthlyDriverCostRm: drivers.value == null
            ? null
            : drivers.value! * lowMonthlyDriverCostRm,
        highMonthlyDriverCostRm: drivers.value == null
            ? null
            : drivers.value! * highMonthlyDriverCostRm,
      );
      _entries.clear();
      _nextCandidateIndex = 0;
    });
  }

  List<Widget> _currentServiceEvidence(
    FuelCostCalculationEvidence evidence,
  ) {
    if (evidence.directionGroups.isEmpty) return const [];
    return [
      Text('Current Service', style: Theme.of(context).textTheme.titleSmall),
      for (var index = 0; index < evidence.directionGroups.length; index++)
        _directionEvidence(evidence.directionGroups[index], index),
    ];
  }

  Widget _directionEvidence(
    DirectionFuelCalculationEvidence group,
    int index,
  ) {
    final label =
        group.directionLabel ?? 'Direction ${group.directionId ?? index}';
    final minimum = group.minimumHeadwaySeconds;
    final maximum = group.maximumHeadwaySeconds;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (group.currentHeadwayMinutes case final current?)
            _detail('Current Headway', '${displayDecimal(current)} min'),
          if (minimum != null && maximum != null && minimum == maximum)
            _detail(
              'Scheduled Headway',
              '${displayDecimal(minimum / 60)} min',
            ),
          if (minimum != null && maximum != null && minimum != maximum)
            _detail(
              'Scheduled Headway Range',
              '${displayDecimal(minimum / 60)}\u2013${displayDecimal(maximum / 60)} min',
            ),
        ],
      ),
    );
  }

  Widget _resourceField(
    TextEditingController controller,
    String label, {
    required FocusNode focusNode,
    required String? errorText,
  }) => TextField(
    controller: controller,
    focusNode: focusNode,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: '$label (planning assumption)',
      errorText: errorText,
      errorMaxLines: 3,
    ),
    onChanged: (_) => setState(() {
      _session.additionalBusesInput = _additionalBusesController.text;
      _session.additionalDriversInput = _additionalDriversController.text;
      _resourceCostReady = false;
      _costReportActionKey = null;
      _session.calculatedPlanningContext = null;
      _entries.clear();
      _nextCandidateIndex = 0;
      if (controller == _additionalBusesController) {
        _additionalBusesError = null;
      } else {
        _additionalDriversError = null;
      }
    }),
  );

  void _validateResourceField(
    TextEditingController controller,
    String label,
    int maximum,
    void Function(String?) setError,
  ) {
    final validation = parseNonNegativeResource(
      controller.text,
      label,
      maximum: maximum,
    );
    if (!mounted) return;
    setState(() {
      setError(validation.error);
    });
  }

  bool get _canGenerateInsight =>
      !_screening && !_analysing && _hasValidScenarioForInsight;

  bool get _hasValidScenarioForInsight {
    final recommendation = _selectedFrequencyRecommendation;
    final candidate = _selectedCostCandidate;
    if (_screening || recommendation == null || candidate == null) return false;
    return _isCostReportReady(recommendation);
  }

  CostPlanningContext? get _planningContext {
    final recommendation = _selectedFrequencyRecommendation;
    final candidate = _selectedCostCandidate;
    if (recommendation == null || candidate == null) return null;
    final calculated = _session.calculatedPlanningContext;
    if (calculated != null &&
        calculated.routeId == candidate.route.routeId &&
        calculated.busFrequencyAction == recommendation.action.name) {
      return calculated;
    }
    final buses = parseNonNegativeResource(
      _additionalBusesController.text,
      'Additional buses',
      maximum: maxAdditionalBusPlanningCount,
    );
    final drivers = parseNonNegativeResource(
      _additionalDriversController.text,
      'Additional drivers',
      maximum: maxAdditionalDriverPlanningCount,
    );
    final busCount = buses.error == null ? buses.value : null;
    final driverCount = drivers.error == null ? drivers.value : null;
    return CostPlanningContext(
      routeId: candidate.route.routeId,
      busFrequencyAction: recommendation.action.name,
      additionalBuses: busCount,
      additionalDrivers: driverCount,
      estimatedBusAcquisitionCostRm:
          busCount == null ? null : busCount * additionalDieselBusCostRm,
      lowMonthlyDriverCostRm:
          driverCount == null ? null : driverCount * lowMonthlyDriverCostRm,
      highMonthlyDriverCostRm:
          driverCount == null ? null : driverCount * highMonthlyDriverCostRm,
    );
  }

  List<BusFrequencyRouteRecommendationRecord> get _frequencyRecommendations {
    final records = widget.busFrequencySession?.recommendationResult?.synthesis
        ?.routeRecommendations;
    if (records == null) return const [];
    return records
        .where((record) =>
            record.action !=
            BusFrequencyRecommendationAction.insufficientEvidence)
        .toList(growable: false);
  }

  String _routeName(String routeId) => _candidates
      .where((candidate) => candidate.route.routeId == routeId)
      .firstOrNull
      ?.route
      .displayName ?? routeId;

  String _frequencyActionLabel(BusFrequencyRecommendationAction action) => switch (action) {
    BusFrequencyRecommendationAction.increasePeakHourFrequency => 'Increase Peak-Hour Frequency',
    BusFrequencyRecommendationAction.maintainService => 'Maintain Current Frequency',
    BusFrequencyRecommendationAction.decreaseService => 'Decrease Frequency',
    BusFrequencyRecommendationAction.insufficientEvidence => 'Needs More Evidence',
  };

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
                'Estimated Fuel Cost',
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
                    label: const Text('Retry AI Cost Insight'),
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
                _section('AI Cost Insight', recommendation.rationale),
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
              if (_planningBasisDetails(entry).isNotEmpty) ...[
                _section('Estimation Bases', _planningBasisDetails(entry)),
                const SizedBox(height: 12),
              ],
              _detail(
                'Diesel Price',
                '${displayMoney(evidence.dieselPrice.rmPerLitre!)} per litre',
              ),
              _detail(
                'Diesel Effective Date',
                _date(evidence.dieselPrice.effectiveDate!),
              ),
              _detail(
                'Scheduled Vehicle-km',
                displayDecimal(evidence.scheduledVehicleKilometres),
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

  List<String> _planningBasisDetails(CostDashboardEntry entry) {
    final context = entry.result.payload?.toJson()['planning_context'];
    if (context is! Map<String, dynamic>) return const [];
    return [
      if (context['additional_buses'] != null)
        'Bus acquisition: ${displayMoney(additionalDieselBusCostRm)} per additional diesel bus. $additionalDieselBusCostSource.',
      if (context['additional_drivers'] != null)
        'Driver cost: ${displayMoney(lowMonthlyDriverCostRm)}\u2013${displayMoney(highMonthlyDriverCostRm)} per additional driver per month. $monthlyDriverCostSource.',
    ];
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
        Padding(padding: const EdgeInsets.only(top: 4), child: Text('\u2022 $item')),
    ],
  );
}

String _fuelRange(FuelCostCalculationEvidence evidence) {
  final low = evidence.lowEstimatedFuelCostRm;
  final high = evidence.highEstimatedFuelCostRm;
  if (low == null || high == null) return 'Unavailable';
  return '${displayMoney(low)} \u2013 ${displayMoney(high)}';
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
