import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/johor_bahru_boundary_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

final priorityPeriodStart = DateTime.utc(2026, 8, 1);
final priorityPeriodEnd = DateTime.utc(2026, 8, 31);

BusFrequencyEvidence busPriorityEvidence({
  int delayedTrips = 0,
  bool reliablePeak = false,
  int feedbackCount = 0,
}) {
  const route = RoutePerformanceRoute(
    routeId: 'J10',
    shortName: 'J10',
    longName: 'City Route',
  );
  final feedback = List.generate(
    feedbackCount,
    (index) => _feedback('J10', index, 'Bus was late'),
  );
  return BusFrequencyEvidence(
    routeId: 'J10',
    periodStart: priorityPeriodStart,
    periodEnd: priorityPeriodEnd,
    scheduledService: ScheduledServiceEvidence(
      route: route,
      periodStart: priorityPeriodStart,
      periodEnd: priorityPeriodEnd,
      directionGroups: const [],
      incompleteTripIds: const [],
      status: ScheduledServiceEvidenceStatus.insufficientForHeadway,
      hasCompleteDirectionData: false,
    ),
    operational: _operational(
      route,
      delayedTrips: delayedTrips,
      reliablePeak: reliablePeak,
    ),
    feedback: BusFrequencyFeedbackEvidence(
      records: feedback,
      countByIssueType: feedbackCount == 0
          ? const {}
          : {'Bus was late': feedbackCount},
      frequencyRelevantRecords: feedback,
    ),
  );
}

DistrictRouteStopEvidence routeStopPriorityEvidence({
  int delayedTrips = 0,
  int feedbackCount = 0,
}) {
  const route = RoutePerformanceRoute(
    routeId: 'J20',
    shortName: 'J20',
    longName: 'Cross Town',
  );
  final feedback = List.generate(
    feedbackCount,
    (index) => _feedback('J20', index, 'Missing bus stop'),
  );
  return DistrictRouteStopEvidence(
    routeStopEvidence: RouteStopEvidence(
      routeId: 'J20',
      periodStart: priorityPeriodStart,
      periodEnd: priorityPeriodEnd,
      network: const AiRouteNetworkEvidence(route: route, trips: []),
      operational: _operational(route, delayedTrips: delayedTrips),
      feedback: RouteStopFeedbackEvidence(
        records: feedback,
        countByIssueType: feedbackCount == 0
            ? const {}
            : {'Missing bus stop': feedbackCount},
        routeStopRelevantRecords: feedback,
      ),
      stopSpacingByTrip: const [],
    ),
    boundary: const DistrictBoundaryEvidence(
      status: DistrictBoundaryStatus.unavailable,
      geometry: null,
      source: johorBahruDistrictBoundarySource,
    ),
    tripStopMembership: const [],
    stopOccurrenceCounts: const DistrictMembershipCounts(
      insideJohorBahruDistrict: 0,
      outsideJohorBahruDistrict: 0,
      unverifiable: 0,
    ),
    uniqueStopCounts: const DistrictMembershipCounts(
      insideJohorBahruDistrict: 0,
      outsideJohorBahruDistrict: 0,
      unverifiable: 0,
    ),
  );
}

AiOperationalEvidence _operational(
  RoutePerformanceRoute route, {
  int delayedTrips = 0,
  bool reliablePeak = false,
}) => AiOperationalEvidence(
  route: route,
  periodStart: priorityPeriodStart,
  periodEnd: priorityPeriodEnd,
  peakOperationSummary: PeakOperationSummary(
    routeId: route.routeId,
    periodStart: priorityPeriodStart,
    periodEnd: priorityPeriodEnd,
    observationCount: reliablePeak ? 1 : 0,
    distinctTripOccurrences: reliablePeak ? 1 : 0,
    observedDayCount: reliablePeak ? 1 : 0,
    routesRepresented: reliablePeak ? 1 : 0,
    bucketBreakdown: const [],
    peakBuckets: const [],
    averageActivity: 0,
    activityDifferencePercent: 0,
    dailyActivity: const [],
    routeActivity: const [],
    observedWindowStart: null,
    observedWindowEnd: null,
    hasReliablePeak: reliablePeak,
    hasLimitedCoverage: !reliablePeak,
  ),
  routePerformanceSummary: RoutePerformanceSummary(
    trips: const [],
    totalObservations: delayedTrips,
    averageTravelTime: null,
    delayedTripCount: delayedTrips,
    delayFrequencyPercent: null,
    scheduleAdherencePercent: null,
  ),
);

AdminFeedbackRecord _feedback(String routeId, int index, String issueType) =>
    AdminFeedbackRecord(
      feedbackId: 'feedback-$index',
      routeId: routeId,
      tripId: null,
      stopId: 'stop-$index',
      issueType: issueType,
      comment: '',
      createdAt: priorityPeriodStart,
    );
