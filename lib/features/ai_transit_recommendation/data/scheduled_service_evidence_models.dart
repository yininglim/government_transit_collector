import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

enum ScheduledServiceEvidenceStatus {
  available,
  insufficientForHeadway,
  noDepartures,
  incomplete,
}

class ScheduledServiceEvidence {
  const ScheduledServiceEvidence({
    required this.route,
    required this.periodStart,
    required this.periodEnd,
    required this.directionGroups,
    required this.incompleteTripIds,
    required this.status,
    required this.hasCompleteDirectionData,
  });

  final RoutePerformanceRoute route;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<ScheduledDirectionEvidence> directionGroups;
  final List<String> incompleteTripIds;
  final ScheduledServiceEvidenceStatus status;
  final bool hasCompleteDirectionData;

  int get scheduledDepartureCount => directionGroups.fold(
    0,
    (total, group) => total + group.departures.length,
  );
}

class ScheduledDirectionEvidence {
  const ScheduledDirectionEvidence({
    required this.directionId,
    required this.departures,
    required this.headwaysSeconds,
    required this.hourlyBuckets,
    required this.averageHeadwaySeconds,
    required this.medianHeadwaySeconds,
    required this.minimumHeadwaySeconds,
    required this.maximumHeadwaySeconds,
  });

  final int? directionId;
  final List<ScheduledDepartureEvidence> departures;
  final List<int> headwaysSeconds;
  final List<ScheduledServiceHourBucket> hourlyBuckets;
  final double? averageHeadwaySeconds;
  final double? medianHeadwaySeconds;
  final int? minimumHeadwaySeconds;
  final int? maximumHeadwaySeconds;
}

class ScheduledDepartureEvidence {
  const ScheduledDepartureEvidence({
    required this.tripId,
    required this.serviceDate,
    required this.departureSeconds,
    required this.scheduledAt,
    required this.referenceStopId,
    required this.referenceStopSequence,
  });

  final String tripId;
  final DateTime serviceDate;
  final int departureSeconds;
  final DateTime scheduledAt;
  final String referenceStopId;
  final int referenceStopSequence;
}

class ScheduledServiceHourBucket {
  const ScheduledServiceHourBucket({
    required this.serviceDate,
    required this.startMinute,
    required this.scheduledDepartureCount,
    required this.scheduledTripsPerHour,
  });

  final DateTime serviceDate;
  final int startMinute;
  final int scheduledDepartureCount;
  final double scheduledTripsPerHour;
}
