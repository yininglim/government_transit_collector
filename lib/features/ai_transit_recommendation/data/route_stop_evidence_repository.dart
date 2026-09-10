import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/route_geometry.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

abstract interface class RouteStopEvidenceRepository {
  Future<RouteStopEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  });
}

class DefaultRouteStopEvidenceRepository
    implements RouteStopEvidenceRepository {
  factory DefaultRouteStopEvidenceRepository({
    RouteNetworkEvidenceRepository? routeNetworkRepository,
    OperationalEvidenceRepository? operationalRepository,
    AdminFeedbackRepository? feedbackRepository,
    RoutePerformanceRepository? routeRepository,
  }) {
    final sharedRouteRepository =
        routeRepository ??
        _SharedRoutePerformanceRepository(DefaultRoutePerformanceRepository());
    return DefaultRouteStopEvidenceRepository._(
      routeNetworkRepository:
          routeNetworkRepository ??
          DefaultRouteNetworkEvidenceRepository(
            routeRepository: sharedRouteRepository,
          ),
      operationalRepository:
          operationalRepository ??
          DefaultOperationalEvidenceRepository(
            routePerformanceRepository: sharedRouteRepository,
          ),
      feedbackRepository: feedbackRepository ?? DefaultAdminFeedbackRepository(),
    );

  }

  DefaultRouteStopEvidenceRepository._({
    required RouteNetworkEvidenceRepository routeNetworkRepository,
    required OperationalEvidenceRepository operationalRepository,
    required AdminFeedbackRepository feedbackRepository,
  }) : _routeNetworkRepository = routeNetworkRepository,
       _operationalRepository = operationalRepository,
       _feedbackRepository = feedbackRepository;

  final RouteNetworkEvidenceRepository _routeNetworkRepository;
  final OperationalEvidenceRepository _operationalRepository;
  final AdminFeedbackRepository _feedbackRepository;

  @override
  Future<RouteStopEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    if (!endExclusiveUtc.isAfter(startUtc)) {
      throw const RouteStopEvidenceReadException(
        'The analysis period is invalid.',
      );
    }
    try {
      final results = await Future.wait([
        _routeNetworkRepository.loadRoute(routeId),
        _operationalRepository.loadEvidence(
          routeId: routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        ),
        _feedbackRepository.loadFeedback(
          routeId: routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        ),
      ]);
      final network = results[0] as AiRouteNetworkEvidence;
      final operational = results[1] as AiOperationalEvidence;
      final records = results[2] as List<AdminFeedbackRecord>;
      final counts = <String, int>{};
      for (final record in records) {
        for (final issue in record.issueTypes) {
          counts.update(issue, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      final relevantRecords = records
          .where(
            (record) => record.issueTypes.any(
              RouteStopFeedbackIssueTypes.routeStopRelevant.contains,
            ),
          )
          .toList(growable: false);

      return RouteStopEvidence(
        routeId: routeId,
        periodStart: startUtc,
        periodEnd: endExclusiveUtc,
        network: network,
        operational: operational,
        feedback: RouteStopFeedbackEvidence(
          records: List.unmodifiable(records),
          countByIssueType: Map.unmodifiable(counts),
          routeStopRelevantRecords: relevantRecords,
        ),
        stopSpacingByTrip: network.trips
            .map(_calculateStopSpacing)
            .toList(growable: false),
      );
    } on RouteStopEvidenceReadException {
      rethrow;
    } on Object {
      throw const RouteStopEvidenceReadException(
        'Unable to load route and stop evidence.',
      );
    }
  }

  TripStopSpacingEvidence _calculateStopSpacing(AiRouteTripEvidence trip) {
    final spacing = <ConsecutiveStopSpacingEvidence>[];
    for (var index = 1; index < trip.stops.length; index++) {
      final from = trip.stops[index - 1];
      final to = trip.stops[index];
      final fromCoordinate = from.coordinate;
      final toCoordinate = to.coordinate;
      spacing.add(
        ConsecutiveStopSpacingEvidence(
          fromStopId: from.stopId,
          fromStopSequence: from.stopSequence,
          toStopId: to.stopId,
          toStopSequence: to.stopSequence,
          distanceMeters: fromCoordinate == null || toCoordinate == null
              ? null
              : geographicDistanceMeters(fromCoordinate, toCoordinate),
        ),
      );
    }
    return TripStopSpacingEvidence(
      tripId: trip.tripId,
      consecutiveStops: spacing,
    );
  }
}

class _SharedRoutePerformanceRepository implements RoutePerformanceRepository {
  _SharedRoutePerformanceRepository(this._delegate);

  final RoutePerformanceRepository _delegate;
  Future<List<RoutePerformanceRoute>>? _routesFuture;

  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() {
    final existing = _routesFuture;
    if (existing != null) return existing;
    final future = _delegate.loadRoutes();
    _routesFuture = future;
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {
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
  }) =>
      _delegate.loadRoutePerformance(
        routeId: routeId,
        startUtc: startUtc,
        endExclusiveUtc: endExclusiveUtc,
      );
}

class RouteStopEvidenceReadException implements Exception {
  const RouteStopEvidenceReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
