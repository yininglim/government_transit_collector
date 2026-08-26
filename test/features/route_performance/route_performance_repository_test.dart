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
}

class FakeSource implements RoutePerformanceDataSource {
  List<HistoricalVehicleObservation> observations = [];
  bool fullFirstPage = false;
  bool failure = false;
  String? routeId;
  DateTime? start;
  DateTime? end;
  final observationOffsets = <int>[];
  List<String> scheduleTripIds = [];

  @override
  Future<List<RoutePerformanceRoute>> fetchRoutes() async => const [
    RoutePerformanceRoute(
      routeId: 'route',
      shortName: 'J30',
      longName: 'Johor route',
    ),
  ];

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

HistoricalVehicleObservation row(String route) => HistoricalVehicleObservation(
  routeId: route,
  tripId: 'trip',
  vehicleId: 'bus',
  recordedAt: DateTime.utc(2026, 8, 26),
  latitude: 1,
  longitude: 103,
);
