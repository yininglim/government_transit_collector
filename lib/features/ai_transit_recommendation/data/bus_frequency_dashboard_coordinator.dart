import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';

class BusFrequencyDashboardCandidate {
  const BusFrequencyDashboardCandidate({
    required this.route,
    required this.evidence,
  });

  final RoutePerformanceRoute route;
  final BusFrequencyEvidence evidence;
}

enum BusFrequencyDashboardExclusionReason {
  noScheduledDepartures,
  noSupportingEvidence,
  evidenceLoadingFailure,
}

class BusFrequencyDashboardExcludedRoute {
  const BusFrequencyDashboardExcludedRoute({
    required this.route,
    required this.reason,
    required this.evidence,
  });

  final RoutePerformanceRoute route;
  final BusFrequencyDashboardExclusionReason reason;
  final BusFrequencyEvidence? evidence;
}

class BusFrequencyDashboardScreeningResult {
  const BusFrequencyDashboardScreeningResult({
    required this.routesAnalysed,
    required this.candidates,
    required this.excludedRoutes,
  });

  final int routesAnalysed;
  final List<BusFrequencyDashboardCandidate> candidates;
  final List<BusFrequencyDashboardExcludedRoute> excludedRoutes;
}

class BusFrequencyDashboardSession {
  final candidates = <BusFrequencyDashboardCandidate>[];
  final excludedRoutes = <BusFrequencyDashboardExcludedRoute>[];
  BusFrequencyRecommendationResult? recommendationResult;
  DateTime? periodStartUtc;
  DateTime? periodEndUtc;
  bool empty = false;
  bool setupFailure = false;
  bool screeningComplete = false;
  int routesAnalysed = 0;

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
  }
}

class BusFrequencyDashboardCoordinator {
  BusFrequencyDashboardCoordinator({
    RoutePerformanceRepository? routeRepository,
    BusFrequencyEvidenceRepository? evidenceRepository,
    BusFrequencyRecommendationRepository? recommendationRepository,
  }) : _routeRepository =
           routeRepository ?? DefaultRoutePerformanceRepository(),
       _evidenceRepository =
           evidenceRepository ?? DefaultBusFrequencyEvidenceRepository(),
       _recommendationRepository =
           recommendationRepository ??
           DefaultBusFrequencyRecommendationRepository();

  final RoutePerformanceRepository _routeRepository;
  final BusFrequencyEvidenceRepository _evidenceRepository;
  final BusFrequencyRecommendationRepository _recommendationRepository;

  Future<List<BusFrequencyDashboardCandidate>> screenCandidates({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    final result = await screenRoutes(
      startUtc: startUtc,
      endExclusiveUtc: endExclusiveUtc,
    );
    return result.candidates;
  }

  Future<BusFrequencyDashboardScreeningResult> screenRoutes({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    final routes = await _routeRepository.loadRoutes();
    final ordered = [...routes]..sort(_compareRoutes);
    final candidates = <BusFrequencyDashboardCandidate>[];
    final excludedRoutes = <BusFrequencyDashboardExcludedRoute>[];
    for (final route in ordered) {
      try {
        final evidence = await _evidenceRepository.loadEvidence(
          routeId: route.routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        );
        if (isBusFrequencyDashboardEligible(evidence)) {
          candidates.add(
            BusFrequencyDashboardCandidate(route: route, evidence: evidence),
          );
        } else {
          excludedRoutes.add(
            BusFrequencyDashboardExcludedRoute(
              route: route,
              reason: busFrequencyDashboardExclusionReason(evidence),
              evidence: evidence,
            ),
          );
        }
      } on Object {
        excludedRoutes.add(
          BusFrequencyDashboardExcludedRoute(
            route: route,
            reason: BusFrequencyDashboardExclusionReason.evidenceLoadingFailure,
            evidence: null,
          ),
        );
      }
    }
    return BusFrequencyDashboardScreeningResult(
      routesAnalysed: ordered.length,
      candidates: List.unmodifiable(candidates),
      excludedRoutes: List.unmodifiable(excludedRoutes),
    );
  }

  Future<BusFrequencyRecommendationResult> analyse({
    required List<BusFrequencyDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    return _recommendationRepository.generate(
      evidence: candidates.map((candidate) => candidate.evidence).toList(),
      startUtc: startUtc,
      endExclusiveUtc: endExclusiveUtc,
    );
  }

  Future<BusFrequencyRecommendationResult> retry({
    required List<BusFrequencyDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) => _recommendationRepository.generate(
    evidence: candidates.map((candidate) => candidate.evidence).toList(),
    startUtc: startUtc,
    endExclusiveUtc: endExclusiveUtc,
  );
}

bool isBusFrequencyDashboardEligible(BusFrequencyEvidence evidence) {
  final scheduled = evidence.scheduledService;
  if (scheduled.scheduledDepartureCount == 0 ||
      scheduled.status == ScheduledServiceEvidenceStatus.noDepartures) {
    return false;
  }
  final hasHeadway = scheduled.directionGroups.any(
    (group) => group.headwaysSeconds.isNotEmpty,
  );
  final hasOperationalEvidence =
      evidence.operational.peakOperationSummary.observationCount > 0 ||
      evidence.operational.routePerformanceSummary.totalObservations > 0;
  final hasRelevantFeedback =
      evidence.feedback.frequencyRelevantRecordCount > 0;
  return hasHeadway || hasOperationalEvidence || hasRelevantFeedback;
}

BusFrequencyDashboardExclusionReason busFrequencyDashboardExclusionReason(
  BusFrequencyEvidence evidence,
) {
  final scheduled = evidence.scheduledService;
  if (scheduled.scheduledDepartureCount == 0 ||
      scheduled.status == ScheduledServiceEvidenceStatus.noDepartures) {
    return BusFrequencyDashboardExclusionReason.noScheduledDepartures;
  }
  return BusFrequencyDashboardExclusionReason.noSupportingEvidence;
}

int _compareRoutes(RoutePerformanceRoute first, RoutePerformanceRoute second) {
  final display = first.displayName.toLowerCase().compareTo(
    second.displayName.toLowerCase(),
  );
  return display != 0 ? display : first.routeId.compareTo(second.routeId);
}
