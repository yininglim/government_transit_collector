import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

const routeStopDashboardBatchSize = 3;
const routeStopDashboardMaximumConcurrency = 2;

class RouteStopDashboardCandidate {
  const RouteStopDashboardCandidate({
    required this.route,
    required this.evidence,
  });

  final RoutePerformanceRoute route;
  final DistrictRouteStopEvidence evidence;
}

class RouteStopDashboardEntry {
  const RouteStopDashboardEntry({required this.route, required this.result});

  final RoutePerformanceRoute route;
  final RouteStopRecommendationResult result;
}

class RouteStopDashboardCoordinator {
  RouteStopDashboardCoordinator({
    RoutePerformanceRepository? routeRepository,
    DistrictRouteStopEvidenceRepository? evidenceRepository,
    RouteStopRecommendationRepository? recommendationRepository,
  }) : _routeRepository =
           routeRepository ?? DefaultRoutePerformanceRepository(),
       _evidenceRepository =
           evidenceRepository ?? DefaultDistrictRouteStopEvidenceRepository(),
       _recommendationRepository =
           recommendationRepository ??
           DefaultRouteStopRecommendationRepository();

  final RoutePerformanceRepository _routeRepository;
  final DistrictRouteStopEvidenceRepository _evidenceRepository;
  final RouteStopRecommendationRepository _recommendationRepository;

  Future<List<RouteStopDashboardCandidate>> screenCandidates({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    final routes = await _routeRepository.loadRoutes();
    final ordered = [...routes]..sort(_compareRoutes);
    final candidates = <RouteStopDashboardCandidate>[];
    for (final route in ordered) {
      try {
        final evidence = await _evidenceRepository.loadEvidence(
          routeId: route.routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        );
        if (isRouteStopDashboardEligible(evidence)) {
          candidates.add(
            RouteStopDashboardCandidate(route: route, evidence: evidence),
          );
        }
      } on Object {
        continue;
      }
    }
    return candidates;
  }

  Future<List<RouteStopDashboardEntry>> analyseBatch({
    required List<RouteStopDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    void Function(int completed, int total, RouteStopDashboardEntry entry)?
    onCompleted,
  }) async {
    final batch = candidates.take(routeStopDashboardBatchSize).toList();
    final entries = List<RouteStopDashboardEntry?>.filled(batch.length, null);
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
        RouteStopRecommendationResult result;
        try {
          result = await _recommendationRepository.generate(
            routeId: candidate.route.routeId,
            startUtc: startUtc,
            endExclusiveUtc: endExclusiveUtc,
            evidence: candidate.evidence,
          );
        } on Object {
          result = const RouteStopRecommendationResult(
            status: RouteStopRecommendationStatus.temporarilyUnavailable,
            recommendation: null,
            failure: RouteStopRecommendationFailure.network,
            evidence: null,
            payload: null,
          );
        }
        final entry = RouteStopDashboardEntry(
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
        index < batch.length && index < routeStopDashboardMaximumConcurrency;
        index++
      )
        worker(),
    ]);
    return entries.cast<RouteStopDashboardEntry>();
  }

  Future<RouteStopDashboardEntry> retry({
    required RouteStopDashboardCandidate candidate,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    final result = await _recommendationRepository.generate(
      routeId: candidate.route.routeId,
      startUtc: startUtc,
      endExclusiveUtc: endExclusiveUtc,
      evidence: candidate.evidence,
    );
    return RouteStopDashboardEntry(route: candidate.route, result: result);
  }
}

bool isRouteStopDashboardEligible(DistrictRouteStopEvidence evidence) {
  final source = evidence.routeStopEvidence;
  if (source.routeId.trim().isEmpty ||
      source.network.route.routeId.trim().isEmpty) {
    return false;
  }
  return source.network.trips.any(
    (trip) =>
        trip.tripId.trim().isNotEmpty &&
        trip.stops.where((stop) => stop.stopId.trim().isNotEmpty).length >= 2,
  );
}

int _compareRoutes(RoutePerformanceRoute first, RoutePerformanceRoute second) {
  final display = first.displayName.toLowerCase().compareTo(
    second.displayName.toLowerCase(),
  );
  return display != 0 ? display : first.routeId.compareTo(second.routeId);
}
