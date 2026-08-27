import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/route_geometry.dart';

abstract interface class RouteStopEvidenceRepository {
  Future<RouteStopEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  });
}

class DefaultRouteStopEvidenceRepository
    implements RouteStopEvidenceRepository {
  DefaultRouteStopEvidenceRepository({
    RouteNetworkEvidenceRepository? routeNetworkRepository,
    OperationalEvidenceRepository? operationalRepository,
    AdminFeedbackRepository? feedbackRepository,
  }) : _routeNetworkRepository =
           routeNetworkRepository ?? DefaultRouteNetworkEvidenceRepository(),
       _operationalRepository =
           operationalRepository ?? DefaultOperationalEvidenceRepository(),
       _feedbackRepository =
           feedbackRepository ?? DefaultAdminFeedbackRepository();

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
        counts.update(
          record.issueType,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      final relevantRecords = records
          .where(
            (record) => RouteStopFeedbackIssueTypes.routeStopRelevant.contains(
              record.issueType,
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

class RouteStopEvidenceReadException implements Exception {
  const RouteStopEvidenceReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
