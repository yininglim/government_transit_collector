import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_scenario.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:timezone/timezone.dart' as timezone;

const costDashboardBatchSize = 3;
const costDashboardMaximumConcurrency = 2;

({DateTime startUtc, DateTime endUtc, DateTime referenceDate})
costAnalysisPeriod({DateTime Function()? now}) {
  final current = currentTransitServiceDateTime(now: now);
  final today = timezone.TZDateTime(
    transitServiceLocation,
    current.year,
    current.month,
    current.day,
  );
  return (
    startUtc: today.subtract(const Duration(days: 29)).toUtc(),
    endUtc: today.add(const Duration(days: 1)).toUtc(),
    referenceDate: DateTime(current.year, current.month, current.day),
  );
}

class CostDashboardCandidate {
  const CostDashboardCandidate({required this.route, required this.evidence});

  final RoutePerformanceRoute route;
  final FuelCostCalculationEvidence evidence;
}

class CostDashboardEntry {
  const CostDashboardEntry({required this.route, required this.result});

  final RoutePerformanceRoute route;
  final CostRecommendationResult result;
}

class CostDashboardSession {
  final candidates = <CostDashboardCandidate>[];
  final entries = <CostDashboardEntry>[];
  DateTime? periodStartUtc;
  DateTime? periodEndUtc;
  DateTime? referenceDate;
  bool empty = false;
  bool setupFailure = false;
  bool screeningComplete = false;
  int completedInBatch = 0;
  int batchTotal = 0;
  int nextCandidateIndex = 0;
  String additionalBusesInput = '';
  String additionalDriversInput = '';
  String? additionalBusesError;
  String? additionalDriversError;
  String? selectedScenarioRouteId;
  String? costReportActionKey;
  bool resourceCostReady = false;
  CostPlanningContext? calculatedPlanningContext;
  Future<void>? preparationFuture;
  int preparationVersion = 0;

  bool get hasRetainedCompletedState =>
      selectedScenarioRouteId != null &&
      candidates.any(
        (candidate) => candidate.route.routeId == selectedScenarioRouteId,
      ) &&
      (calculatedPlanningContext != null || entries.isNotEmpty);

  bool matchesPeriod(
    DateTime startUtc,
    DateTime endExclusiveUtc,
    DateTime reference,
  ) =>
      periodStartUtc?.isAtSameMomentAs(startUtc) == true &&
      periodEndUtc?.isAtSameMomentAs(endExclusiveUtc) == true &&
      _sameDate(referenceDate, reference);

  void begin(DateTime startUtc, DateTime endExclusiveUtc, DateTime reference) {
    preparationVersion++;
    preparationFuture = null;
    periodStartUtc = startUtc;
    periodEndUtc = endExclusiveUtc;
    referenceDate = DateTime(reference.year, reference.month, reference.day);
    candidates.clear();
    entries.clear();
    empty = false;
    setupFailure = false;
    screeningComplete = false;
    completedInBatch = 0;
    batchTotal = 0;
    nextCandidateIndex = 0;
    additionalBusesInput = '';
    additionalDriversInput = '';
    additionalBusesError = null;
    additionalDriversError = null;
    selectedScenarioRouteId = null;
    costReportActionKey = null;
    resourceCostReady = false;
    calculatedPlanningContext = null;
  }

  void clear() {
    preparationVersion++;
    preparationFuture = null;
    periodStartUtc = null;
    periodEndUtc = null;
    referenceDate = null;
    candidates.clear();
    entries.clear();
    empty = false;
    setupFailure = false;
    screeningComplete = false;
    completedInBatch = 0;
    batchTotal = 0;
    nextCandidateIndex = 0;
    additionalBusesInput = '';
    additionalDriversInput = '';
    additionalBusesError = null;
    additionalDriversError = null;
    selectedScenarioRouteId = null;
    costReportActionKey = null;
    resourceCostReady = false;
    calculatedPlanningContext = null;
  }
}

bool _sameDate(DateTime? first, DateTime second) =>
    first != null &&
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

class CostDashboardCoordinator {
  CostDashboardCoordinator({
    RoutePerformanceRepository? routeRepository,
    FuelCostCalculationRepository? evidenceRepository,
    CostRecommendationRepository? recommendationRepository,
  }) : _routeRepository =
           routeRepository ?? DefaultRoutePerformanceRepository(),
       _evidenceRepository =
           evidenceRepository ?? DefaultFuelCostCalculationRepository(),
       _recommendationRepository =
           recommendationRepository ?? DefaultCostRecommendationRepository();

  final RoutePerformanceRepository _routeRepository;
  final FuelCostCalculationRepository _evidenceRepository;
  final CostRecommendationRepository _recommendationRepository;

  Future<void> prepareSession({
    required CostDashboardSession session,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  }) {
    if (session.matchesPeriod(startUtc, endExclusiveUtc, referenceDate) &&
        session.screeningComplete) {
      return Future<void>.value();
    }
    final current = session.preparationFuture;
    if (current != null &&
        session.matchesPeriod(startUtc, endExclusiveUtc, referenceDate)) {
      return current;
    }
    final version = ++session.preparationVersion;
    session.periodStartUtc = startUtc;
    session.periodEndUtc = endExclusiveUtc;
    session.referenceDate = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );
    session.candidates.clear();
    session.entries.clear();
    session.empty = false;
    session.setupFailure = false;
    session.screeningComplete = false;
    session.completedInBatch = 0;
    session.batchTotal = 0;
    session.nextCandidateIndex = 0;
    session.additionalBusesInput = '';
    session.additionalDriversInput = '';
    session.additionalBusesError = null;
    session.additionalDriversError = null;
    session.selectedScenarioRouteId = null;
    session.costReportActionKey = null;
    session.resourceCostReady = false;
    session.calculatedPlanningContext = null;
    final future = () async {
      try {
        final candidates = await screenCandidates(
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
          referenceDate: referenceDate,
        );
        if (session.preparationVersion != version) return;
        session.candidates
          ..clear()
          ..addAll(candidates);
        session.empty = candidates.isEmpty;
        session.batchTotal = candidates.length;
        session.screeningComplete = true;
      } on Object {
        if (session.preparationVersion == version) {
          session.setupFailure = true;
        }
      } finally {
        if (session.preparationVersion == version) {
          session.preparationFuture = null;
        }
      }
    }();
    session.preparationFuture = future;
    return future;
  }

  Future<List<CostDashboardCandidate>> screenCandidates({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  }) async {
    final routes = await _routeRepository.loadRoutes();
    final ordered = [...routes]..sort(_compareRoutes);
    final candidates = <CostDashboardCandidate>[];
    for (final route in ordered) {
      try {
        final evidence = await _evidenceRepository.calculate(
          routeId: route.routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
          referenceDate: referenceDate,
        );
        if (hasUsableCostRecommendationEvidence(evidence)) {
          candidates.add(
            CostDashboardCandidate(route: route, evidence: evidence),
          );
        }
      } on Object {
        continue;
      }
    }
    return candidates;
  }

  Future<List<CostDashboardEntry>> analyseBatch({
    required List<CostDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
    CostPlanningContext? planningContext,
    void Function(int completed, int total, CostDashboardEntry entry)?
    onCompleted,
  }) async {
    final batch = candidates.take(costDashboardBatchSize).toList();
    final entries = List<CostDashboardEntry?>.filled(batch.length, null);
    var nextIndex = 0;
    var nextCompletedIndex = 0;
    var completed = 0;

    void reportCompleted() {
      while (nextCompletedIndex < entries.length &&
          entries[nextCompletedIndex] != null) {
        completed++;
        onCompleted?.call(
          completed,
          batch.length,
          entries[nextCompletedIndex]!,
        );
        nextCompletedIndex++;
      }
    }

    Future<void> worker() async {
      while (nextIndex < batch.length) {
        final index = nextIndex++;
        final candidate = batch[index];
        CostRecommendationResult result;
        try {
          result = await _recommendationRepository.generate(
            routeId: candidate.route.routeId,
            startUtc: startUtc,
            endExclusiveUtc: endExclusiveUtc,
            referenceDate: referenceDate,
            evidence: candidate.evidence,
            planningContext:
                planningContext?.routeId == candidate.route.routeId
                ? planningContext
                : null,
          );
        } on Object {
          result = const CostRecommendationResult(
            status: CostRecommendationStatus.temporarilyUnavailable,
            recommendation: null,
            failure: CostRecommendationFailure.network,
            evidence: null,
            payload: null,
          );
        }
        final entry = CostDashboardEntry(
          route: candidate.route,
          result: result,
        );
        entries[index] = entry;
        reportCompleted();
      }
    }

    await Future.wait([
      for (
        var index = 0;
        index < batch.length && index < costDashboardMaximumConcurrency;
        index++
      )
        worker(),
    ]);
    return entries.cast<CostDashboardEntry>();
  }

  Future<CostDashboardEntry> retry({
    required CostDashboardCandidate candidate,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
    CostPlanningContext? planningContext,
  }) async {
    final result = await _recommendationRepository.generate(
      routeId: candidate.route.routeId,
      startUtc: startUtc,
      endExclusiveUtc: endExclusiveUtc,
      referenceDate: referenceDate,
      evidence: candidate.evidence,
      planningContext: planningContext?.routeId == candidate.route.routeId
          ? planningContext
          : null,
    );
    return CostDashboardEntry(route: candidate.route, result: result);
  }
}

int _compareRoutes(RoutePerformanceRoute first, RoutePerformanceRoute second) {
  final display = first.displayName.toLowerCase().compareTo(
    second.displayName.toLowerCase(),
  );
  return display != 0 ? display : first.routeId.compareTo(second.routeId);
}
