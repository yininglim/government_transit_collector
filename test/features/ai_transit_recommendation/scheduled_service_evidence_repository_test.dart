import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

void main() {
  test('lean scheduled path preserves reference-stop semantics', () async {
    final result =
        await DefaultScheduledServiceEvidenceRepository(
          useLeanRouteLoader: true,
          routeRepository: FakeLeanRouteRepository(),
          leanDataSource: FakeLeanScheduledServiceDataSource(),
          dataSource: FakeScheduledServiceDataSource(
            metadata: [metadata('trip-a')],
          ),
        ).loadEvidence(
          routeId: 'J15',
          startUtc: localDayStartUtc,
          endExclusiveUtc: localDayEndUtc,
        );

    final departure = result.directionGroups.single.departures.single;
    expect(departure.tripId, 'trip-a');
    expect(departure.referenceStopId, 'first');
    expect(departure.referenceStopSequence, 1);
    expect(departure.departureSeconds, 8 * 3600);
    expect(
      result.status,
      ScheduledServiceEvidenceStatus.insufficientForHeadway,
    );
  });

  test('lean scheduled path reuses route metadata across routes', () async {
    final routes = FakeLeanRouteRepository(
      routes: const [
        RoutePerformanceRoute(
          routeId: 'J15',
          shortName: 'J15',
          longName: 'Johor route',
        ),
        RoutePerformanceRoute(
          routeId: 'J20',
          shortName: 'J20',
          longName: 'Second route',
        ),
      ],
    );
    final repository = DefaultScheduledServiceEvidenceRepository(
      useLeanRouteLoader: true,
      routeRepository: routes,
      leanDataSource: FakeLeanScheduledServiceDataSource(metadata: const []),
      dataSource: FakeScheduledServiceDataSource(),
    );

    final first = await repository.loadEvidence(
      routeId: 'J15',
      startUtc: localDayStartUtc,
      endExclusiveUtc: localDayEndUtc,
    );
    final second = await repository.loadEvidence(
      routeId: 'J20',
      startUtc: localDayStartUtc,
      endExclusiveUtc: localDayEndUtc,
    );

    expect(routes.loadRoutesCalls, 1);
    expect(first.route.routeId, 'J15');
    expect(first.route.shortName, 'J15');
    expect(first.route.longName, 'Johor route');
    expect(second.route.routeId, 'J20');
    expect(second.route.shortName, 'J20');
    expect(second.route.longName, 'Second route');
  });

  test('lean scheduled path batches stop times by 100 trip IDs', () async {
    final metadata = [
      for (var index = 0; index < 101; index++)
        ScheduledTripMetadata(
          tripId: 'trip-$index',
          serviceId: 'daily',
          directionId: 0,
        ),
    ];
    final source = FakeLeanScheduledServiceDataSource(
      metadata: metadata,
      stopTimes: const {},
    );
    final calendarSource = FakeScheduledServiceDataSource();

    final result =
        await DefaultScheduledServiceEvidenceRepository(
          useLeanRouteLoader: true,
          routeRepository: FakeLeanRouteRepository(),
          leanDataSource: source,
          dataSource: calendarSource,
        ).loadEvidence(
          routeId: 'J15',
          startUtc: localDayStartUtc,
          endExclusiveUtc: localDayEndUtc,
        );

    expect(source.metadataRequests, 1);
    expect(source.stopTimeBatchSizes, [100, 1]);
    expect(calendarSource.tripMetadataRequests, 0);
    expect(result.incompleteTripIds, hasLength(101));
  });

  test('lean scheduled path matches grouped scheduled outputs', () async {
    final trips = [
      trip('trip-a', 8 * 3600),
      trip('trip-b', 8 * 3600 + 30 * 60),
      trip('trip-c', 9 * 3600),
    ];
    final full = await repository(trips: trips).loadEvidence(
      routeId: 'J15',
      startUtc: localDayStartUtc,
      endExclusiveUtc: localDayEndUtc,
    );
    final lean = await leanRepository(trips).loadEvidence(
      routeId: 'J15',
      startUtc: localDayStartUtc,
      endExclusiveUtc: localDayEndUtc,
    );

    expect(lean.scheduledDepartureCount, full.scheduledDepartureCount);
    expect(lean.directionGroups.length, full.directionGroups.length);
    expect(
      lean.directionGroups.single.headwaysSeconds,
      full.directionGroups.single.headwaysSeconds,
    );
    expect(
      lean.directionGroups.single.hourlyBuckets.map(
        (bucket) => bucket.scheduledDepartureCount,
      ),
      full.directionGroups.single.hourlyBuckets.map(
        (bucket) => bucket.scheduledDepartureCount,
      ),
    );
    expect(lean.status, full.status);
    expect(lean.incompleteTripIds, full.incompleteTripIds);
  });

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

DefaultScheduledServiceEvidenceRepository leanRepository(
  List<AiRouteTripEvidence> trips,
) {
  return DefaultScheduledServiceEvidenceRepository(
    useLeanRouteLoader: true,
    routeRepository: FakeLeanRouteRepository(),
    leanDataSource: FakeLeanScheduledServiceDataSource(
      metadata: [for (final item in trips) metadata(item.tripId)],
      stopTimes: {
        for (final trip in trips)
          trip.tripId: [
            for (final stop in trip.stops)
              ScheduledStopTimeRecord(
                tripId: trip.tripId,
                stopId: stop.stopId,
                stopSequence: stop.stopSequence,
                arrivalSeconds: stop.scheduledArrivalSeconds,
                departureSeconds: stop.scheduledDepartureSeconds,
              ),
          ],
      },
    ),
    dataSource: FakeScheduledServiceDataSource(
      metadata: [for (final item in trips) metadata(item.tripId)],
    ),
  );
}

class FakeLeanRouteRepository implements RoutePerformanceRepository {
  FakeLeanRouteRepository({
    this.routes = const [
      RoutePerformanceRoute(
        routeId: 'J15',
        shortName: 'J15',
        longName: 'Johor route',
      ),
    ],
  });

  final List<RoutePerformanceRoute> routes;
  int loadRoutesCalls = 0;

  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() async {
    loadRoutesCalls++;
    return routes;
  }

  @override
  Future<RoutePerformanceData> loadRoutePerformance({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) => throw UnimplementedError();
}

class FakeLeanScheduledServiceDataSource
    implements LeanScheduledServiceDataSource {
  FakeLeanScheduledServiceDataSource({
    List<ScheduledTripMetadata>? metadata,
    Map<String, List<ScheduledStopTimeRecord>>? stopTimes,
  }) : metadata =
           metadata ??
           const [
             ScheduledTripMetadata(
               tripId: 'trip-a',
               serviceId: 'daily',
               directionId: 0,
             ),
           ],
       stopTimes =
           stopTimes ??
           const {
             'trip-a': [
               ScheduledStopTimeRecord(
                 tripId: 'trip-a',
                 stopId: 'second',
                 stopSequence: 2,
                 arrivalSeconds: 9 * 3600,
                 departureSeconds: 9 * 3600,
               ),
               ScheduledStopTimeRecord(
                 tripId: 'trip-a',
                 stopId: 'first',
                 stopSequence: 1,
                 arrivalSeconds: 8 * 3600,
                 departureSeconds: null,
               ),
             ],
           };

  final List<ScheduledTripMetadata> metadata;
  final Map<String, List<ScheduledStopTimeRecord>> stopTimes;
  int metadataRequests = 0;
  final List<int> stopTimeBatchSizes = [];

  @override
  Future<List<ScheduledTripMetadata>> fetchRouteTripMetadata({
    required String routeId,
    required int offset,
    required int limit,
  }) async {
    metadataRequests++;
    if (offset >= metadata.length) return const [];
    final end = (offset + limit).clamp(0, metadata.length);
    return metadata.sublist(offset, end);
  }

  @override
  Future<List<ScheduledStopTimeRecord>> fetchStopTimes({
    required List<String> tripIds,
    required int offset,
    required int limit,
  }) async {
    if (offset == 0) stopTimeBatchSizes.add(tripIds.length);
    final rows =
        <ScheduledStopTimeRecord>[
          for (final tripId in tripIds)
            ...(stopTimes[tripId] ?? const <ScheduledStopTimeRecord>[]),
        ]..sort((a, b) {
          final byTrip = a.tripId.compareTo(b.tripId);
          return byTrip != 0
              ? byTrip
              : a.stopSequence.compareTo(b.stopSequence);
        });
    if (offset >= rows.length) return const [];
    final end = (offset + limit).clamp(0, rows.length);
    return rows.sublist(offset, end);
  }
}

class FakeScheduledServiceDataSource implements ScheduledServiceDataSource {
  FakeScheduledServiceDataSource({
    List<ScheduledTripMetadata>? metadata,
    this.active = true,
  }) : metadata = metadata ?? const [];

  final List<ScheduledTripMetadata> metadata;
  final bool active;
  int tripMetadataRequests = 0;

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
  ) async {
    tripMetadataRequests++;
    return metadata;
  }
}
