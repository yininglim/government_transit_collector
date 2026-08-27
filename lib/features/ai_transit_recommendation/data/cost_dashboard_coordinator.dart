import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

const costDashboardBatchSize = 3;

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
    final entries = <CostDashboardEntry>[];
    for (var index = 0; index < batch.length; index++) {
      final candidate = batch[index];
      CostRecommendationResult result;
      try {
        result = await _recommendationRepository.generate(
          routeId: candidate.route.routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
          referenceDate: referenceDate,
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
      final entry = CostDashboardEntry(route: candidate.route, result: result);
      entries.add(entry);
      onCompleted?.call(index + 1, batch.length, entry);
    }
    return entries;
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
