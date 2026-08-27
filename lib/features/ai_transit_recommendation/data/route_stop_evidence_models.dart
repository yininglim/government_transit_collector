import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';

class RouteStopEvidence {
  const RouteStopEvidence({
    required this.routeId,
    required this.periodStart,
    required this.periodEnd,
    required this.network,
    required this.operational,
    required this.feedback,
    required this.stopSpacingByTrip,
  });

  final String routeId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final AiRouteNetworkEvidence network;
  final AiOperationalEvidence operational;
  final RouteStopFeedbackEvidence feedback;
  final List<TripStopSpacingEvidence> stopSpacingByTrip;
}

class RouteStopFeedbackEvidence {
  const RouteStopFeedbackEvidence({
    required this.records,
    required this.countByIssueType,
    required this.routeStopRelevantRecords,
  });

  final List<AdminFeedbackRecord> records;
  final Map<String, int> countByIssueType;
  final List<AdminFeedbackRecord> routeStopRelevantRecords;

  int get totalRecordCount => records.length;
  int get routeStopRelevantRecordCount => routeStopRelevantRecords.length;
}

class TripStopSpacingEvidence {
  const TripStopSpacingEvidence({
    required this.tripId,
    required this.consecutiveStops,
  });

  final String tripId;
  final List<ConsecutiveStopSpacingEvidence> consecutiveStops;
}

class ConsecutiveStopSpacingEvidence {
  const ConsecutiveStopSpacingEvidence({
    required this.fromStopId,
    required this.fromStopSequence,
    required this.toStopId,
    required this.toStopSequence,
    required this.distanceMeters,
  });

  final String fromStopId;
  final int fromStopSequence;
  final String toStopId;
  final int toStopSequence;
  final double? distanceMeters;
}

abstract final class RouteStopFeedbackIssueTypes {
  static const missingBusStop = 'Missing bus stop';
  static const longWalkingDistance = 'Long walking distance';
  static const incorrectRouteInformation = 'Incorrect route information';

  static const routeStopRelevant = {
    missingBusStop,
    longWalkingDistance,
    incorrectRouteInformation,
  };
}
