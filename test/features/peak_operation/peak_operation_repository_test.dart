import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_repository.dart';

void main() {
  test('loads friendly route metadata', () async {
    final routes = await DefaultPeakOperationRepository(
      dataSource: FakeSource(),
    ).loadRoutes();
    expect(routes.single.displayName, 'J15 — Friendly route');
  });

  test(
    'passes half-open date and route filters and excludes unrelated rows',
    () async {
      final source = FakeSource()..rows = [row('A'), row('B')];
      final start = DateTime.utc(2026, 8, 26);
      final end = DateTime.utc(2026, 8, 27);
      final result = await DefaultPeakOperationRepository(
        dataSource: source,
      ).loadObservations(startUtc: start, endExclusiveUtc: end, routeId: 'A');
      expect(source.start, start);
      expect(source.end, end);
      expect(source.route, 'A');
      expect(result.map((item) => item.routeId), ['A']);
    },
  );

  test('paginates 1000 row pages', () async {
    final source = FakeSource()..fullPage = true;
    await DefaultPeakOperationRepository(dataSource: source).loadObservations(
      startUtc: DateTime.utc(2026),
      endExclusiveUtc: DateTime.utc(2027),
    );
    expect(source.offsets, [0, 1000]);
  });

  test('converts source failures to read exception', () {
    final source = FakeSource()..fail = true;
    expect(
      () => DefaultPeakOperationRepository(dataSource: source).loadObservations(
        startUtc: DateTime.utc(2026),
        endExclusiveUtc: DateTime.utc(2027),
      ),
      throwsA(isA<PeakOperationReadException>()),
    );
  });
}

class FakeSource implements PeakOperationDataSource {
  List<PeakOperationObservation> rows = [];
  bool fullPage = false;
  bool fail = false;
  DateTime? start;
  DateTime? end;
  String? route;
  final offsets = <int>[];

  @override
  Future<List<PeakOperationRoute>> fetchRoutes() async => const [
    PeakOperationRoute(
      routeId: 'A',
      shortName: 'J15',
      longName: 'Friendly route',
    ),
  ];

  @override
  Future<List<PeakOperationObservation>> fetchObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required String? routeId,
    required int offset,
    required int limit,
  }) async {
    if (fail) throw Exception('failed');
    start = startUtc;
    end = endExclusiveUtc;
    route = routeId;
    offsets.add(offset);
    if (fullPage && offset == 0) return List.filled(limit, row('A'));
    if (fullPage) return const [];
    return offset == 0 ? rows : const [];
  }
}

PeakOperationObservation row(String route) => PeakOperationObservation(
  routeId: route,
  tripId: 'trip',
  vehicleId: 'bus',
  recordedAt: DateTime.utc(2026, 8, 26),
);
