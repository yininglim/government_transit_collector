import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:timezone/timezone.dart' as timezone;

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
  RouteStopRecommendationAction? selectedRecommendationAction;
  RouteStopCandidateArea? selectedCandidateArea;
  List<String> selectedTargetStopIds = const [];
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
    selectedRouteId = null;
    selectedRecommendationAction = null;
    selectedCandidateArea = null;
    selectedTargetStopIds = const [];
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
    selectedRouteId = null;
    selectedRecommendationAction = null;
    selectedCandidateArea = null;
    selectedTargetStopIds = const [];
    preparation = null;
  }
}

class RouteStopDashboardCoordinator {
  RouteStopDashboardCoordinator({
    RoutePerformanceRepository? routeRepository,
    DistrictRouteStopEvidenceRepository? evidenceRepository,
    RouteStopRecommendationRepository? recommendationRepository,
  }) {
    _routeRepository = routeRepository;
    _evidenceRepository = evidenceRepository;
    _recommendationRepository =
        recommendationRepository ?? DefaultRouteStopRecommendationRepository();
  }

  late final RoutePerformanceRepository? _routeRepository;
  late final DistrictRouteStopEvidenceRepository? _evidenceRepository;
  late final RouteStopRecommendationRepository _recommendationRepository;

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
    late final RoutePerformanceRepository sharedRouteRepository;
    late final DistrictRouteStopEvidenceRepository evidenceRepository;
    if (_evidenceRepository case final injectedEvidence?) {
      sharedRouteRepository = _ScreeningRoutePerformanceRepository(
        _routeRepository ?? DefaultRoutePerformanceRepository(),
      );
      evidenceRepository = injectedEvidence;
    } else {
      final dataSource = SupabaseRoutePerformanceDataSource();
      sharedRouteRepository = _ScreeningRoutePerformanceRepository(
        ScreeningRoutePerformanceRepository(
          dataSource: dataSource,
          observationDataSource: dataSource,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        ),
      );
      evidenceRepository = DefaultDistrictRouteStopEvidenceRepository(
        routeStopRepository: DefaultRouteStopEvidenceRepository(
          routeRepository: sharedRouteRepository,
          feedbackRepository: ScreeningAdminFeedbackRepository(
            delegate: DefaultAdminFeedbackRepository(),
            startUtc: startUtc,
            endExclusiveUtc: endExclusiveUtc,
          ),
        ),
      );
    }
    final routes = await sharedRouteRepository.loadRoutes();
    final ordered = [...routes]..sort(_compareRoutes);
    final outcomes =
        List<
          ({
            RouteStopDashboardCandidate? candidate,
            RouteStopDashboardExcludedRoute? excluded,
          })?
        >.filled(ordered.length, null);
    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < ordered.length) {
        final index = nextIndex++;
        final route = ordered[index];
        RouteStopDashboardCandidate? candidate;
        RouteStopDashboardExcludedRoute? excluded;
        try {
          final evidence = await evidenceRepository.loadEvidence(
            routeId: route.routeId,
            startUtc: startUtc,
            endExclusiveUtc: endExclusiveUtc,
          );
          if (isRouteStopDashboardEligible(evidence)) {
            candidate = RouteStopDashboardCandidate(
              route: route,
              evidence: evidence,
            );
          } else {
            excluded = RouteStopDashboardExcludedRoute(
              route: route,
              reason: RouteStopDashboardExclusionReason.unusableTripStructure,
              evidence: evidence,
            );
          }
        } on Object {
          excluded = RouteStopDashboardExcludedRoute(
            route: route,
            reason: RouteStopDashboardExclusionReason.evidenceLoadingFailure,
            evidence: null,
          );
        }
        outcomes[index] = (candidate: candidate, excluded: excluded);
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
    final candidates = outcomes
        .map((outcome) => outcome?.candidate)
        .whereType<RouteStopDashboardCandidate>()
        .toList();
    final excludedRoutes = outcomes
        .map((outcome) => outcome?.excluded)
        .whereType<RouteStopDashboardExcludedRoute>()
        .toList();
    return RouteStopDashboardScreeningResult(
      routesAnalysed: ordered.length,
      candidates: List.unmodifiable(candidates),
      excludedRoutes: List.unmodifiable(excludedRoutes),
    );
  }

  Future<void> prepareSession({
    required RouteStopDashboardSession session,
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
        session.selectedRouteId = result.candidates.firstOrNull?.route.routeId;
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

class _ScreeningRoutePerformanceRepository
    implements RoutePerformanceRepository {
  _ScreeningRoutePerformanceRepository(this._delegate);

  final RoutePerformanceRepository _delegate;
  Future<List<RoutePerformanceRoute>>? _routesFuture;

  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() =>
      _routesFuture ??= _delegate.loadRoutes();

  @override
  Future<RoutePerformanceData> loadRoutePerformance({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) => _delegate.loadRoutePerformance(
    routeId: routeId,
    startUtc: startUtc,
    endExclusiveUtc: endExclusiveUtc,
  );
}

({DateTime startUtc, DateTime endUtc}) routeStopAnalysisPeriod({
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
