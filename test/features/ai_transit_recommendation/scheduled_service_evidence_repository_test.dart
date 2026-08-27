import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

void main() {
  test(
    'orders scheduled departures and calculates consecutive headways',
    () async {
      final result =
          await repository(
            trips: [
              trip('trip-c', 9 * 3600 + 30 * 60),
              trip('trip-a', 8 * 3600),
              trip('trip-b', 8 * 3600 + 30 * 60),
            ],
          ).loadEvidence(
            routeId: 'J15',
            startUtc: localDayStartUtc,
            endExclusiveUtc: localDayEndUtc,
          );
      final direction = result.directionGroups.single;

      expect(direction.departures.map((item) => item.tripId), [
        'trip-a',
        'trip-b',
        'trip-c',
      ]);
      expect(direction.headwaysSeconds, [30 * 60, 60 * 60]);
      expect(direction.averageHeadwaySeconds, 45 * 60);
      expect(direction.medianHeadwaySeconds, 45 * 60);
      expect(direction.minimumHeadwaySeconds, 30 * 60);
      expect(direction.maximumHeadwaySeconds, 60 * 60);
      expect(result.status, ScheduledServiceEvidenceStatus.available);
    },
  );

  test('calculates deterministic hourly service rates', () async {
    final result =
        await repository(
          trips: [
            trip('trip-a', 8 * 3600),
            trip('trip-b', 8 * 3600 + 30 * 60),
            trip('trip-c', 9 * 3600 + 30 * 60),
          ],
        ).loadEvidence(
          routeId: 'J15',
          startUtc: localDayStartUtc,
          endExclusiveUtc: localDayEndUtc,
        );
    final buckets = result.directionGroups.single.hourlyBuckets;

    expect(buckets.map((bucket) => bucket.startMinute), [8 * 60, 9 * 60]);
    expect(buckets.map((bucket) => bucket.scheduledDepartureCount), [2, 1]);
    expect(buckets.map((bucket) => bucket.scheduledTripsPerHour), [2.0, 1.0]);
    expect(result.scheduledDepartureCount, 3);
  });

  test('keeps opposite and unknown directions separate', () async {
    final source = FakeScheduledServiceDataSource(
      metadata: [
        metadata('outbound-a', directionId: 0),
        metadata('outbound-b', directionId: 0),
        metadata('inbound-a', directionId: 1),
        metadata('unknown', directionId: null),
      ],
    );
    final result =
        await repository(
          trips: [
            trip('outbound-a', 8 * 3600),
            trip('inbound-a', 8 * 3600 + 10 * 60),
            trip('outbound-b', 8 * 3600 + 30 * 60),
            trip('unknown', 8 * 3600 + 20 * 60),
          ],
          source: source,
        ).loadEvidence(
          routeId: 'J15',
          startUtc: localDayStartUtc,
          endExclusiveUtc: localDayEndUtc,
        );

    expect(result.directionGroups.map((group) => group.directionId), [
      0,
      1,
      null,
    ]);
    expect(result.directionGroups.first.headwaysSeconds, [30 * 60]);
    expect(result.directionGroups[1].headwaysSeconds, isEmpty);
    expect(result.directionGroups[2].headwaysSeconds, isEmpty);
    expect(result.hasCompleteDirectionData, isFalse);
  });

  test('one departure does not fabricate a headway', () async {
    final result = await repository(trips: [trip('trip-a', 8 * 3600)])
        .loadEvidence(
          routeId: 'J15',
          startUtc: localDayStartUtc,
          endExclusiveUtc: localDayEndUtc,
        );
    final direction = result.directionGroups.single;

    expect(direction.departures, hasLength(1));
    expect(direction.headwaysSeconds, isEmpty);
    expect(direction.averageHeadwaySeconds, isNull);
    expect(direction.medianHeadwaySeconds, isNull);
    expect(direction.minimumHeadwaySeconds, isNull);
    expect(direction.maximumHeadwaySeconds, isNull);
    expect(
      result.status,
      ScheduledServiceEvidenceStatus.insufficientForHeadway,
    );
  });

  test('no active departures does not fabricate frequency evidence', () async {
    final source = FakeScheduledServiceDataSource(
      metadata: [metadata('trip-a')],
      active: false,
    );
    final result =
        await repository(
          trips: [trip('trip-a', 8 * 3600)],
          source: source,
        ).loadEvidence(
          routeId: 'J15',
          startUtc: localDayStartUtc,
          endExclusiveUtc: localDayEndUtc,
        );

    expect(result.scheduledDepartureCount, 0);
    expect(result.directionGroups, isEmpty);
    expect(result.status, ScheduledServiceEvidenceStatus.noDepartures);
  });

  test('supports a prior service-day departure beyond 24 hours', () async {
    final result = await repository(trips: [trip('late-trip', 25 * 3600)])
        .loadEvidence(
          routeId: 'J15',
          startUtc: DateTime.utc(2026, 8, 21, 16),
          endExclusiveUtc: DateTime.utc(2026, 8, 22, 16),
        );
    final departure = result.directionGroups.single.departures.single;

    expect(departure.serviceDate, DateTime(2026, 8, 21));
    expect(departure.departureSeconds, 25 * 3600);
    expect(departure.scheduledAt, DateTime.utc(2026, 8, 21, 17));
  });

  test('uses the lowest stop sequence as the departure reference', () async {
    final scheduledTrip = AiRouteTripEvidence(
      tripId: 'trip-a',
      shapeId: null,
      stops: const [
        AiRouteStopEvidence(
          stopId: 'second',
          stopName: 'Second',
          stopSequence: 2,
          coordinate: null,
          scheduledArrivalSeconds: 9 * 3600,
          scheduledDepartureSeconds: 9 * 3600,
        ),
        AiRouteStopEvidence(
          stopId: 'first',
          stopName: 'First',
          stopSequence: 1,
          coordinate: null,
          scheduledArrivalSeconds: 8 * 3600,
          scheduledDepartureSeconds: 8 * 3600,
        ),
      ],
      shapePoints: const [],
      routeDistanceMeters: null,
    );
    final result = await repository(trips: [scheduledTrip]).loadEvidence(
      routeId: 'J15',
      startUtc: localDayStartUtc,
      endExclusiveUtc: localDayEndUtc,
    );
    final departure = result.directionGroups.single.departures.single;

    expect(departure.referenceStopId, 'first');
    expect(departure.referenceStopSequence, 1);
    expect(departure.departureSeconds, 8 * 3600);
  });

  test('keeps missing stop-time information explicit', () async {
    final incomplete = AiRouteTripEvidence(
      tripId: 'trip-a',
      shapeId: null,
      stops: const [],
      shapePoints: const [],
      routeDistanceMeters: null,
    );
    final result = await repository(trips: [incomplete]).loadEvidence(
      routeId: 'J15',
      startUtc: localDayStartUtc,
      endExclusiveUtc: localDayEndUtc,
    );

    expect(result.scheduledDepartureCount, 0);
    expect(result.incompleteTripIds, ['trip-a']);
    expect(result.status, ScheduledServiceEvidenceStatus.incomplete);
  });
}

final localDayStartUtc = DateTime.utc(2026, 8, 20, 16);
final localDayEndUtc = DateTime.utc(2026, 8, 21, 16);

DefaultScheduledServiceEvidenceRepository repository({
  required List<AiRouteTripEvidence> trips,
  FakeScheduledServiceDataSource? source,
}) {
  return DefaultScheduledServiceEvidenceRepository(
    routeNetworkRepository: FakeRouteNetworkRepository(trips),
    dataSource:
        source ??
        FakeScheduledServiceDataSource(
          metadata: [for (final item in trips) metadata(item.tripId)],
        ),
  );
}

AiRouteTripEvidence trip(String tripId, int departureSeconds) {
  return AiRouteTripEvidence(
    tripId: tripId,
    shapeId: null,
    stops: [
      AiRouteStopEvidence(
        stopId: 'first-stop',
        stopName: 'First Stop',
        stopSequence: 1,
        coordinate: null,
        scheduledArrivalSeconds: departureSeconds,
        scheduledDepartureSeconds: departureSeconds,
      ),
    ],
    shapePoints: const [],
    routeDistanceMeters: null,
  );
}

ScheduledTripMetadata metadata(String tripId, {int? directionId = 0}) {
  return ScheduledTripMetadata(
    tripId: tripId,
    serviceId: 'daily',
    directionId: directionId,
  );
}

class FakeRouteNetworkRepository implements RouteNetworkEvidenceRepository {
  FakeRouteNetworkRepository(this.trips);

  final List<AiRouteTripEvidence> trips;

  @override
  Future<AiRouteNetworkEvidence> loadRoute(String routeId) async {
    return AiRouteNetworkEvidence(
      route: RoutePerformanceRoute(
        routeId: routeId,
        shortName: routeId,
        longName: 'Johor route',
      ),
      trips: trips,
    );
  }
}

class FakeScheduledServiceDataSource implements ScheduledServiceDataSource {
  FakeScheduledServiceDataSource({
    List<ScheduledTripMetadata>? metadata,
    this.active = true,
  }) : metadata = metadata ?? const [];

  final List<ScheduledTripMetadata> metadata;
  final bool active;

  @override
  Future<List<GtfsServiceCalendar>> loadCalendars(
    List<String> serviceIds,
  ) async {
    return [
      GtfsServiceCalendar(
        serviceId: 'daily',
        startDate: DateTime(2020),
        endDate: DateTime(2100),
        weekdays: List.filled(7, active),
      ),
    ];
  }

  @override
  Future<List<ScheduledTripMetadata>> loadTripMetadata(
    List<String> tripIds,
  ) async => metadata;
}
