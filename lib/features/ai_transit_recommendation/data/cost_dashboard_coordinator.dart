import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

const costDashboardBatchSize = 3;
const costDashboardMaximumConcurrency = 2;

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
  int completedInBatch = 0;
  int batchTotal = 0;
  int nextCandidateIndex = 0;

  bool matchesPeriod(
    DateTime startUtc,
    DateTime endExclusiveUtc,
    DateTime reference,
  ) =>
      periodStartUtc?.isAtSameMomentAs(startUtc) == true &&
      periodEndUtc?.isAtSameMomentAs(endExclusiveUtc) == true &&
      _sameDate(referenceDate, reference);

  void begin(DateTime startUtc, DateTime endExclusiveUtc, DateTime reference) {
    periodStartUtc = startUtc;
    periodEndUtc = endExclusiveUtc;
    referenceDate = DateTime(reference.year, reference.month, reference.day);
    candidates.clear();
    entries.clear();
    empty = false;
    setupFailure = false;
    completedInBatch = 0;
    batchTotal = 0;
    nextCandidateIndex = 0;
  }

  void clear() {
    periodStartUtc = null;
    periodEndUtc = null;
    referenceDate = null;
    candidates.clear();
    entries.clear();
    empty = false;
    setupFailure = false;
    completedInBatch = 0;
    batchTotal = 0;
    nextCandidateIndex = 0;
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
  }) async {
    final result = await _recommendationRepository.generate(
      routeId: candidate.route.routeId,
      startUtc: startUtc,
      endExclusiveUtc: endExclusiveUtc,
      referenceDate: referenceDate,
      evidence: candidate.evidence,
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
