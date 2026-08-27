import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/route_geometry.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

void main() {
  test('forwards the selected route and same half-open period', () async {
    final networkRepository = FakeNetworkRepository(networkEvidence());
    final operationalRepository = FakeOperationalRepository(
      operationalEvidence(),
    );
    final feedbackRepository = FakeFeedbackRepository(const []);

    await repository(
      networkRepository: networkRepository,
      operationalRepository: operationalRepository,
      feedbackRepository: feedbackRepository,
    ).loadEvidence(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );

    expect(networkRepository.routeId, 'J15');
    for (final call in [operationalRepository.call, feedbackRepository.call]) {
      expect(call?.routeId, 'J15');
      expect(call?.startUtc, same(periodStart));
      expect(call?.endExclusiveUtc, same(periodEnd));
    }
  });

  test('retains network variants and operational evidence unchanged', () async {
    final network = networkEvidence();
    final operational = operationalEvidence();
    final result =
        await repository(
          networkRepository: FakeNetworkRepository(network),
          operationalRepository: FakeOperationalRepository(operational),
        ).loadEvidence(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(result.network, same(network));
    expect(result.operational, same(operational));
    expect(result.network.trips.map((trip) => trip.tripId), [
      'trip-a',
      'trip-b',
    ]);
    expect(result.network.trips.map((trip) => trip.shapeId), [
      'shape-a',
      'shape-b',
    ]);
    expect(result.network.trips.first.stops.map((stop) => stop.stopSequence), [
      1,
      2,
      3,
    ]);
    expect(result.network.trips.first.stops[1].coordinate?.latitude, 1.46);
    expect(
      result.network.trips.last.shapePoints.single.coordinate.longitude,
      103.8,
    );
    expect(result.operational.peakOperationSummary.hasLimitedCoverage, isTrue);
    expect(
      result.operational.routePerformanceSummary.delayFrequencyPercent,
      isNull,
    );
  });

  test(
    'uses geographic utility and keeps missing coordinates explicit',
    () async {
      final network = networkEvidence();
      final result =
          await repository(
            networkRepository: FakeNetworkRepository(network),
          ).loadEvidence(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );
      final spacing = result.stopSpacingByTrip.first.consecutiveStops;
      final expected = geographicDistanceMeters(
        network.trips.first.stops[0].coordinate!,
        network.trips.first.stops[1].coordinate!,
      );

      expect(spacing, hasLength(2));
      expect(spacing.first.distanceMeters, expected);
      expect(spacing.first.fromStopSequence, 1);
      expect(spacing.first.toStopSequence, 2);
      expect(spacing.last.distanceMeters, isNull);
      expect(result.network.trips.first.stops.last.coordinate, isNull);
      expect(result.network.trips.last.shapePoints, hasLength(1));
      expect(result.network.trips.last.routeDistanceMeters, isNull);
    },
  );

  test(
    'counts exact route-stop issue types and preserves all records',
    () async {
      final records = [
        feedback('one', 'Missing bus stop'),
        feedback('two', 'Missing bus stop'),
        feedback('three', 'Long walking distance'),
        feedback('four', 'Incorrect route information'),
        feedback('five', 'Other'),
        feedback('six', 'Unexpected stored value'),
      ];
      final result =
          await repository(
            feedbackRepository: FakeFeedbackRepository(records),
          ).loadEvidence(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );

      expect(result.feedback.totalRecordCount, 6);
      expect(result.feedback.countByIssueType['Missing bus stop'], 2);
      expect(result.feedback.countByIssueType['Other'], 1);
      expect(result.feedback.countByIssueType['Unexpected stored value'], 1);
      expect(result.feedback.routeStopRelevantRecordCount, 4);
      expect(
        result.feedback.routeStopRelevantRecords.map(
          (record) => record.feedbackId,
        ),
        ['one', 'two', 'three', 'four'],
      );
      expect(result.feedback.records, hasLength(6));
    },
  );

  test(
    'zero feedback and missing network details remain valid evidence',
    () async {
      final network = AiRouteNetworkEvidence(
        route: route,
        trips: const [
          AiRouteTripEvidence(
            tripId: 'incomplete',
            shapeId: null,
            stops: [],
            shapePoints: [],
            routeDistanceMeters: null,
          ),
        ],
      );
      final result =
          await repository(
            networkRepository: FakeNetworkRepository(network),
          ).loadEvidence(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );

      expect(result.feedback.totalRecordCount, 0);
      expect(result.feedback.routeStopRelevantRecords, isEmpty);
      expect(result.network.trips.single.shapeId, isNull);
      expect(result.network.trips.single.shapePoints, isEmpty);
      expect(result.network.trips.single.routeDistanceMeters, isNull);
      expect(result.stopSpacingByTrip.single.consecutiveStops, isEmpty);
    },
  );
}

final periodStart = DateTime.utc(2026, 8, 20);
final periodEnd = DateTime.utc(2026, 8, 27);

const route = RoutePerformanceRoute(
  routeId: 'J15',
  shortName: 'J15',
  longName: 'Johor Bahru route',
);

DefaultRouteStopEvidenceRepository repository({
  FakeNetworkRepository? networkRepository,
  FakeOperationalRepository? operationalRepository,
  FakeFeedbackRepository? feedbackRepository,
}) {
  return DefaultRouteStopEvidenceRepository(
    routeNetworkRepository:
        networkRepository ?? FakeNetworkRepository(networkEvidence()),
    operationalRepository:
        operationalRepository ??
        FakeOperationalRepository(operationalEvidence()),
    feedbackRepository: feedbackRepository ?? FakeFeedbackRepository(const []),
  );
}

AiRouteNetworkEvidence networkEvidence() {
  return AiRouteNetworkEvidence(
    route: route,
    trips: const [
      AiRouteTripEvidence(
        tripId: 'trip-a',
        shapeId: 'shape-a',
        stops: [
          AiRouteStopEvidence(
            stopId: 'stop-a',
            stopName: 'Stop A',
            stopSequence: 1,
            coordinate: MapCoordinate(1.45, 103.75),
            scheduledArrivalSeconds: 8 * 3600,
            scheduledDepartureSeconds: 8 * 3600,
          ),
          AiRouteStopEvidence(
            stopId: 'stop-b',
            stopName: 'Stop B',
            stopSequence: 2,
            coordinate: MapCoordinate(1.46, 103.76),
            scheduledArrivalSeconds: 8 * 3600 + 600,
            scheduledDepartureSeconds: 8 * 3600 + 600,
          ),
          AiRouteStopEvidence(
            stopId: 'stop-c',
            stopName: null,
            stopSequence: 3,
            coordinate: null,
            scheduledArrivalSeconds: null,
            scheduledDepartureSeconds: null,
          ),
        ],
        shapePoints: [
          ShapePoint(sequence: 1, coordinate: MapCoordinate(1.45, 103.75)),
          ShapePoint(sequence: 2, coordinate: MapCoordinate(1.46, 103.76)),
        ],
        routeDistanceMeters: 1500,
      ),
      AiRouteTripEvidence(
        tripId: 'trip-b',
        shapeId: 'shape-b',
        stops: [],
        shapePoints: [
          ShapePoint(sequence: 1, coordinate: MapCoordinate(1.5, 103.8)),
        ],
        routeDistanceMeters: null,
      ),
    ],
  );
}

AiOperationalEvidence operationalEvidence() {
  return AiOperationalEvidence(
    route: route,
    periodStart: periodStart,
    periodEnd: periodEnd,
    peakOperationSummary: PeakOperationSummary(
      routeId: 'J15',
      periodStart: periodStart,
      periodEnd: periodEnd,
      observationCount: 0,
      distinctTripOccurrences: 0,
      observedDayCount: 0,
      routesRepresented: 0,
      bucketBreakdown: const [],
      peakBuckets: const [],
      averageActivity: 0,
      activityDifferencePercent: 0,
      dailyActivity: const [],
      routeActivity: const [],
      observedWindowStart: null,
      observedWindowEnd: null,
      hasReliablePeak: false,
      hasLimitedCoverage: true,
    ),
    routePerformanceSummary: const RoutePerformanceSummary(
      trips: [],
      totalObservations: 0,
      averageTravelTime: null,
      delayedTripCount: 0,
      delayFrequencyPercent: null,
      scheduleAdherencePercent: null,
    ),
  );
}

AdminFeedbackRecord feedback(String id, String issueType) {
  return AdminFeedbackRecord(
    feedbackId: id,
    routeId: 'J15',
    tripId: null,
    stopId: 'stop-a',
    issueType: issueType,
    comment: '',
    createdAt: periodStart,
  );
}

class RepositoryCall {
  const RepositoryCall(this.routeId, this.startUtc, this.endExclusiveUtc);

  final String routeId;
  final DateTime startUtc;
  final DateTime endExclusiveUtc;
}

class FakeNetworkRepository implements RouteNetworkEvidenceRepository {
  FakeNetworkRepository(this.result);

  final AiRouteNetworkEvidence result;
  String? routeId;

  @override
  Future<AiRouteNetworkEvidence> loadRoute(String routeId) async {
    this.routeId = routeId;
    return result;
  }
}

class FakeOperationalRepository implements OperationalEvidenceRepository {
  FakeOperationalRepository(this.result);

  final AiOperationalEvidence result;
  RepositoryCall? call;

  @override
  Future<AiOperationalEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    call = RepositoryCall(routeId, startUtc, endExclusiveUtc);
    return result;
  }
}

class FakeFeedbackRepository implements AdminFeedbackRepository {
  FakeFeedbackRepository(this.result);

  final List<AdminFeedbackRecord> result;
  RepositoryCall? call;

  @override
  Future<List<AdminFeedbackRecord>> loadFeedback({
    String? routeId,
    String? issueType,
    DateTime? startUtc,
    DateTime? endExclusiveUtc,
  }) async {
    call = RepositoryCall(routeId!, startUtc!, endExclusiveUtc!);
    return result;
  }
}
