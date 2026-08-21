import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/static_trip_matcher.dart';

class FakeStaticTripDataSource implements StaticTripDataSource {
  FakeStaticTripDataSource(this.knownIds);
  final Set<String> knownIds;
  final List<List<String>> calls = [];

  @override
  Future<Set<String>> findKnownTripIds(List<String> tripIds) async {
    calls.add([...tripIds]);
    return tripIds.where(knownIds.contains).toSet();
  }
}

void main() {
  test('returns matching GTFS Static trip IDs only', () async {
    final source = FakeStaticTripDataSource({'trip-1'});
    final result = await SupabaseStaticTripMatcher(
      dataSource: source,
    ).findKnownTripIds(['trip-1', 'unknown']);

    expect(result, {'trip-1'});
  });

  test('deduplicates IDs and batches lookup requests', () async {
    final source = FakeStaticTripDataSource({'trip-1', 'trip-3'});
    final result = await SupabaseStaticTripMatcher(
      dataSource: source,
      batchSize: 2,
    ).findKnownTripIds(['trip-1', 'trip-1', 'trip-2', 'trip-3']);

    expect(source.calls, [
      ['trip-1', 'trip-2'],
      ['trip-3'],
    ]);
    expect(result, {'trip-1', 'trip-3'});
  });

  test('missing and blank realtime trip IDs do not query the source', () async {
    final source = FakeStaticTripDataSource({});
    final result = await SupabaseStaticTripMatcher(
      dataSource: source,
    ).findKnownTripIds(['', '  ']);

    expect(result, isEmpty);
    expect(source.calls, isEmpty);
  });
}
