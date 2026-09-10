import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

void main() {
  test('loads route metadata', () async {
    final source = FakeSource();
    final routes = await DefaultRoutePerformanceRepository(
      dataSource: source,
    ).loadRoutes();
    expect(routes.single.displayName, 'J30 — Johor route');
  });

  test('loads only routes with observations in the requested period', () async {
    final source = FakeSource()
      ..routes = const [
        RoutePerformanceRoute(
          routeId: 'route',
          shortName: 'J30',
          longName: null,
        ),
        RoutePerformanceRoute(
          routeId: 'other',
          shortName: 'J50',
          longName: null,
        ),
      ]
      ..observedRouteIds = ['route', 'route'];
    final start = DateTime.utc(2026, 8, 26);
    final end = DateTime.utc(2026, 8, 27);

    final routes = await DefaultRoutePerformanceRepository(
      dataSource: source,
    ).loadRoutesWithObservations(startUtc: start, endExclusiveUtc: end);

    expect(routes.map((route) => route.routeId), ['route']);
    expect(source.availabilityStart, start);
    expect(source.availabilityEnd, end);
  });

  test(
    'applies route and timestamp range and excludes unrelated route rows',
    () async {
      final source = FakeSource();
      source.observations = [row('route'), row('other')];
      final start = DateTime.utc(2026, 8, 26);
      final end = DateTime.utc(2026, 8, 27);
      final data = await DefaultRoutePerformanceRepository(dataSource: source)
          .loadRoutePerformance(
            routeId: 'route',
            startUtc: start,
            endExclusiveUtc: end,
          );
      expect(source.routeId, 'route');
      expect(source.start, start);
      expect(source.end, end);
      expect(data.observations.map((item) => item.routeId), ['route']);
    },
  );

  test('paginates observation queries', () async {
    final source = FakeSource()..fullFirstPage = true;
    await DefaultRoutePerformanceRepository(
      dataSource: source,
    ).loadRoutePerformance(
      routeId: 'route',
      startUtc: DateTime.utc(2026),
      endExclusiveUtc: DateTime.utc(2027),
    );
    expect(source.observationOffsets, [0, 1000]);
  });

  test('builds exact-trip schedule from first and last stop', () async {
    final source = FakeSource()..observations = [row('route')];
    final data = await DefaultRoutePerformanceRepository(dataSource: source)
        .loadRoutePerformance(
          routeId: 'route',
          startUtc: DateTime.utc(2026),
          endExclusiveUtc: DateTime.utc(2027),
        );
    expect(source.scheduleTripIds, ['trip']);
    expect(
      data.schedulesByTripId['trip']!.scheduledDuration,
      const Duration(minutes: 30),
    );
  });

  test('propagates a stable read exception', () async {
    final source = FakeSource()..failure = true;
    expect(
      () => DefaultRoutePerformanceRepository(dataSource: source)
          .loadRoutePerformance(
            routeId: 'route',
            startUtc: DateTime.utc(2026),
            endExclusiveUtc: DateTime.utc(2027),
          ),
      throwsA(isA<RoutePerformanceReadException>()),
    );
  });

  test(
    'screening shares one period fetch and partitions exact routes',
    () async {
      final source = FakePeriodSource()
        ..periodObservations = [row('A'), row('B'), row('A')];
      final start = DateTime.utc(2026, 8, 26);
      final end = DateTime.utc(2026, 8, 27);
      final repository = ScreeningRoutePerformanceRepository(
        dataSource: source,
        observationDataSource: source,
        startUtc: start,
        endExclusiveUtc: end,
      );

      final results = await Future.wait([
        for (final routeId in ['A', 'B', 'C', 'D'])
          repository.loadRoutePerformance(
            routeId: routeId,
            startUtc: start,
            endExclusiveUtc: end,
          ),
      ]);

      expect(source.periodFetches, 1);
      expect(results[0].observations.map((item) => item.routeId), ['A', 'A']);
      expect(results[1].observations.map((item) => item.routeId), ['B']);
      expect(results[2].observations, isEmpty);
      expect(results[3].observations, isEmpty);
    },
  );

  test(
    'independent screening repositories perform independent fetches',
    () async {
      final source = FakePeriodSource()..periodObservations = [row('A')];
      final start = DateTime.utc(2026);
      final end = DateTime.utc(2027);

      for (var screening = 0; screening < 2; screening++) {
        await ScreeningRoutePerformanceRepository(
          dataSource: source,
          observationDataSource: source,
          startUtc: start,
          endExclusiveUtc: end,
        ).loadRoutePerformance(
          routeId: 'A',
          startUtc: start,
          endExclusiveUtc: end,
        );
      }

      expect(source.periodFetches, 2);
    },
  );

  test('screening data preserves existing route performance input', () async {
    final observations = [row('route')];
    final legacySource = FakeSource()..observations = observations;
    final screeningSource = FakePeriodSource()
      ..periodObservations = observations;
    final start = DateTime.utc(2026);
    final end = DateTime.utc(2027);

    final legacy =
        await DefaultRoutePerformanceRepository(
          dataSource: legacySource,
        ).loadRoutePerformance(
          routeId: 'route',
          startUtc: start,
          endExclusiveUtc: end,
        );
    final screening =
        await ScreeningRoutePerformanceRepository(
          dataSource: screeningSource,
          observationDataSource: screeningSource,
          startUtc: start,
          endExclusiveUtc: end,
        ).loadRoutePerformance(
          routeId: 'route',
          startUtc: start,
          endExclusiveUtc: end,
        );

    expect(screening.observations, legacy.observations);
    expect(screening.schedulesByTripId.keys, legacy.schedulesByTripId.keys);
    expect(
      screening.schedulesByTripId['trip']!.scheduledDuration,
      legacy.schedulesByTripId['trip']!.scheduledDuration,
    );
  });
}

class FakeSource implements RoutePerformanceDataSource {
  List<RoutePerformanceRoute> routes = const [
    RoutePerformanceRoute(
      routeId: 'route',
      shortName: 'J30',
      longName: 'Johor route',
    ),
  ];
  List<String> observedRouteIds = [];
  List<HistoricalVehicleObservation> observations = [];
  bool fullFirstPage = false;
  bool failure = false;
  String? routeId;
  DateTime? start;
  DateTime? end;
  final observationOffsets = <int>[];
  List<String> scheduleTripIds = [];
  DateTime? availabilityStart;
  DateTime? availabilityEnd;

  @override
  Future<List<RoutePerformanceRoute>> fetchRoutes() async => routes;

  @override
  Future<List<String>> fetchObservedRouteIds({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    availabilityStart = startUtc;
    availabilityEnd = endExclusiveUtc;
    return observedRouteIds;
  }

  @override
  Future<List<HistoricalVehicleObservation>> fetchObservations({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required int offset,
    required int limit,
  }) async {
    if (failure) throw Exception('network');
    this.routeId = routeId;
    start = startUtc;
    end = endExclusiveUtc;
    observationOffsets.add(offset);
    if (fullFirstPage && offset == 0) return List.filled(limit, row('route'));
    if (fullFirstPage) return const [];
    return offset == 0 ? observations : const [];
  }

  @override
  Future<List<RouteScheduleStopRecord>> fetchScheduleStops({
    required List<String> tripIds,
    required int offset,
    required int limit,
  }) async {
    scheduleTripIds = tripIds;
    if (offset > 0 || tripIds.isEmpty) return const [];
    return const [
      RouteScheduleStopRecord(
        tripId: 'trip',
        stopSequence: 2,
        arrivalSeconds: 30600,
        departureSeconds: 30600,
        latitude: 1.1,
        longitude: 103.1,
      ),
      RouteScheduleStopRecord(
        tripId: 'trip',
        stopSequence: 1,
        arrivalSeconds: 28800,
        departureSeconds: 28800,
        latitude: 1,
        longitude: 103,
      ),
    ];
  }
}

class FakePeriodSource extends FakeSource
    implements PeriodHistoricalObservationDataSource {
  List<HistoricalVehicleObservation> periodObservations = [];
  int periodFetches = 0;

  @override
  Future<List<HistoricalVehicleObservation>> fetchPeriodObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required int offset,
    required int limit,
  }) async {
    periodFetches++;
    await Future<void>.delayed(Duration.zero);
    if (offset >= periodObservations.length) return const [];
    final end = (offset + limit).clamp(0, periodObservations.length);
    return periodObservations.sublist(offset, end);
  }
}

HistoricalVehicleObservation row(String route) => HistoricalVehicleObservation(
  routeId: route,
  tripId: 'trip',
  vehicleId: 'bus',
  recordedAt: DateTime.utc(2026, 8, 26),
  latitude: 1,
  longitude: 103,
);
