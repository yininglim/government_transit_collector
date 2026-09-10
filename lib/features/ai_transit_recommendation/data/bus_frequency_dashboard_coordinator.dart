import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:timezone/timezone.dart' as timezone;

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
  Future<void>? preparation;
  int preparationVersion = 0;

  bool matchesPeriod(DateTime startUtc, DateTime endExclusiveUtc) =>
      periodStartUtc?.isAtSameMomentAs(startUtc) == true &&
      periodEndUtc?.isAtSameMomentAs(endExclusiveUtc) == true;

  void begin(DateTime startUtc, DateTime endExclusiveUtc) {
    preparationVersion++;
    periodStartUtc = startUtc;
    periodEndUtc = endExclusiveUtc;
    candidates.clear();
    excludedRoutes.clear();
    recommendationResult = null;
    empty = false;
    setupFailure = false;
    screeningComplete = false;
    routesAnalysed = 0;
    preparation = null;
  }

  void clear() {
    preparationVersion++;
    periodStartUtc = null;
    periodEndUtc = null;
    candidates.clear();
    excludedRoutes.clear();
    recommendationResult = null;
    empty = false;
    setupFailure = false;
    screeningComplete = false;
    routesAnalysed = 0;
    preparation = null;
  }
}

class BusFrequencyDashboardCoordinator {
  BusFrequencyDashboardCoordinator({
    RoutePerformanceRepository? routeRepository,
    BusFrequencyEvidenceRepository? evidenceRepository,
    BusFrequencyRecommendationRepository? recommendationRepository,
  }) {
    _recommendationRepository =
        recommendationRepository ??
        DefaultBusFrequencyRecommendationRepository();
    final sharedRouteRepository = _SharedRoutePerformanceRepository(
      routeRepository,
    );
    _routeRepository = sharedRouteRepository;
    _evidenceRepository = evidenceRepository;
  }

  late final RoutePerformanceRepository _routeRepository;
  BusFrequencyEvidenceRepository? _evidenceRepository;
  late final BusFrequencyRecommendationRepository _recommendationRepository;

  BusFrequencyEvidenceRepository get _resolvedEvidenceRepository =>
      _evidenceRepository ??= DefaultBusFrequencyEvidenceRepository(
        routeRepository: _routeRepository,
      );

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
    final outcomes =
        List<
          ({
            BusFrequencyDashboardCandidate? candidate,
            BusFrequencyDashboardExcludedRoute? excluded,
          })?
        >.filled(ordered.length, null);
    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= ordered.length) return;
        final route = ordered[index];
        try {
          final evidence = await _resolvedEvidenceRepository.loadEvidence(
            routeId: route.routeId,
            startUtc: startUtc,
            endExclusiveUtc: endExclusiveUtc,
          );
          if (isBusFrequencyDashboardEligible(evidence)) {
            outcomes[index] = (
              candidate: BusFrequencyDashboardCandidate(
                route: route,
                evidence: evidence,
              ),
              excluded: null,
            );
          } else {
            outcomes[index] = (
              candidate: null,
              excluded: BusFrequencyDashboardExcludedRoute(
                route: route,
                reason: busFrequencyDashboardExclusionReason(evidence),
                evidence: evidence,
              ),
            );
          }
        } on Object {
          outcomes[index] = (
            candidate: null,
            excluded: BusFrequencyDashboardExcludedRoute(
              route: route,
              reason:
                  BusFrequencyDashboardExclusionReason.evidenceLoadingFailure,
              evidence: null,
            ),
          );
        }
      }
    }

    final workerCount = ordered.length < 4 ? ordered.length : 4;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    final candidates = <BusFrequencyDashboardCandidate>[];
    final excludedRoutes = <BusFrequencyDashboardExcludedRoute>[];
    for (final outcome in outcomes) {
      final value = outcome!;
      if (value.candidate != null) {
        candidates.add(value.candidate!);
      } else {
        excludedRoutes.add(value.excluded!);
      }
    }
    return BusFrequencyDashboardScreeningResult(
      routesAnalysed: ordered.length,
      candidates: List.unmodifiable(candidates),
      excludedRoutes: List.unmodifiable(excludedRoutes),
    );
  }

  Future<void> prepareSession({
    required BusFrequencyDashboardSession session,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) {
    if (session.matchesPeriod(startUtc, endExclusiveUtc)) {
      if (session.screeningComplete) return Future.value();
      final existing = session.preparation;
      if (existing != null) return existing;
    }
    session.begin(startUtc, endExclusiveUtc);
    final version = session.preparationVersion;
    late final Future<void> work;
    work = () async {
      try {
        final result = await screenRoutes(
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        );
        if (session.preparationVersion != version ||
            !session.matchesPeriod(startUtc, endExclusiveUtc)) {
          return;
        }
        session.candidates.addAll(result.candidates);
        session.excludedRoutes.addAll(result.excludedRoutes);
        session.routesAnalysed = result.routesAnalysed;
        session.screeningComplete = true;
        session.empty = result.candidates.isEmpty;
      } on Object {
        if (session.preparationVersion == version) {
          session.setupFailure = true;
        }
      } finally {
        if (identical(session.preparation, work)) session.preparation = null;
      }
    }();
    session.preparation = work;
    return work;
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

class _SharedRoutePerformanceRepository implements RoutePerformanceRepository {
  _SharedRoutePerformanceRepository(this._delegate);

  RoutePerformanceRepository? _delegate;
  Future<List<RoutePerformanceRoute>>? _routesFuture;

  RoutePerformanceRepository get _resolvedDelegate =>
      _delegate ??= DefaultRoutePerformanceRepository();

  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() {
    final existing = _routesFuture;
    if (existing != null) return existing;
    final future = _resolvedDelegate.loadRoutes();
    _routesFuture = future;
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (identical(_routesFuture, future)) _routesFuture = null;
      },
    );
    return future;
  }

  @override
  Future<RoutePerformanceData> loadRoutePerformance({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) => _resolvedDelegate.loadRoutePerformance(
    routeId: routeId,
    startUtc: startUtc,
    endExclusiveUtc: endExclusiveUtc,
  );
}

({DateTime startUtc, DateTime endUtc}) busFrequencyAnalysisPeriod({
  DateTime Function()? now,
}) {
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
