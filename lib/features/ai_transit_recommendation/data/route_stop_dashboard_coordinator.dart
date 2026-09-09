import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

class RouteStopDashboardCandidate {
  const RouteStopDashboardCandidate({
    required this.route,
    required this.evidence,
  });

  final RoutePerformanceRoute route;
  final DistrictRouteStopEvidence evidence;
}

enum RouteStopDashboardExclusionReason {
  unusableTripStructure,
  evidenceLoadingFailure,
}

class RouteStopDashboardExcludedRoute {
  const RouteStopDashboardExcludedRoute({
    required this.route,
    required this.reason,
    required this.evidence,
  });

  final RoutePerformanceRoute route;
  final RouteStopDashboardExclusionReason reason;
  final DistrictRouteStopEvidence? evidence;
}

class RouteStopDashboardScreeningResult {
  const RouteStopDashboardScreeningResult({
    required this.routesAnalysed,
    required this.candidates,
    required this.excludedRoutes,
  });

  final int routesAnalysed;
  final List<RouteStopDashboardCandidate> candidates;
  final List<RouteStopDashboardExcludedRoute> excludedRoutes;
}

class RouteStopDashboardSession {
  final candidates = <RouteStopDashboardCandidate>[];
  final excludedRoutes = <RouteStopDashboardExcludedRoute>[];
  RouteStopRecommendationResult? recommendationResult;
  DateTime? periodStartUtc;
  DateTime? periodEndUtc;
  bool empty = false;
  bool setupFailure = false;
  bool screeningComplete = false;
  int routesAnalysed = 0;
  String? selectedRouteId;

  bool matchesPeriod(DateTime startUtc, DateTime endExclusiveUtc) =>
      periodStartUtc?.isAtSameMomentAs(startUtc) == true &&
      periodEndUtc?.isAtSameMomentAs(endExclusiveUtc) == true;

  void begin(DateTime startUtc, DateTime endExclusiveUtc) {
    periodStartUtc = startUtc;
    periodEndUtc = endExclusiveUtc;
    candidates.clear();
    excludedRoutes.clear();
    recommendationResult = null;
    empty = false;
    setupFailure = false;
    screeningComplete = false;
    routesAnalysed = 0;
    selectedRouteId = null;
  }

  void clear() {
    periodStartUtc = null;
    periodEndUtc = null;
    candidates.clear();
    excludedRoutes.clear();
    recommendationResult = null;
    empty = false;
    setupFailure = false;
    screeningComplete = false;
    routesAnalysed = 0;
    selectedRouteId = null;
  }
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
    final result = await screenRoutes(
      startUtc: startUtc,
      endExclusiveUtc: endExclusiveUtc,
    );
    return result.candidates;
  }

  Future<RouteStopDashboardScreeningResult> screenRoutes({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    final routes = await _routeRepository.loadRoutes();
    final ordered = [...routes]..sort(_compareRoutes);
    final candidates = <RouteStopDashboardCandidate>[];
    final excludedRoutes = <RouteStopDashboardExcludedRoute>[];
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
        } else {
          excludedRoutes.add(
            RouteStopDashboardExcludedRoute(
              route: route,
              reason: RouteStopDashboardExclusionReason.unusableTripStructure,
              evidence: evidence,
            ),
          );
        }
      } on Object {
        excludedRoutes.add(
          RouteStopDashboardExcludedRoute(
            route: route,
            reason: RouteStopDashboardExclusionReason.evidenceLoadingFailure,
            evidence: null,
          ),
        );
      }
    }
    return RouteStopDashboardScreeningResult(
      routesAnalysed: ordered.length,
      candidates: List.unmodifiable(candidates),
      excludedRoutes: List.unmodifiable(excludedRoutes),
    );
  }

  Future<RouteStopRecommendationResult> analyse({
    required List<RouteStopDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    return _recommendationRepository.generate(
      evidence: candidates.map((candidate) => candidate.evidence).toList(),
      startUtc: startUtc,
      endExclusiveUtc: endExclusiveUtc,
    );
  }

  Future<RouteStopRecommendationResult> retry({
    required List<RouteStopDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    return _recommendationRepository.generate(
      evidence: candidates.map((candidate) => candidate.evidence).toList(),
      startUtc: startUtc,
      endExclusiveUtc: endExclusiveUtc,
    );
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
