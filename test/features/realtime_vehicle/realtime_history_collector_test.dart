import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_history_collector.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';

const validVehicle = RealtimeVehiclePosition(
  entityId: 'entity-1',
  vehicleId: 'bus-1',
  tripId: 'trip-1',
  routeId: 'J10',
  latitude: 1.49,
  longitude: 103.74,
  timestampSeconds: 100,
);

const snapshot = RealtimeFeedSnapshot(
  vehicles: [validVehicle],
  feedTimestampSeconds: 101,
);

class SequenceRepository implements RealtimeVehicleRepository {
  SequenceRepository(this.results);
  final List<Object> results;
  var calls = 0;
  var active = 0;
  var overlapped = false;

  @override
  Future<RealtimeFeedSnapshot> fetchVehiclePositions() async {
    active++;
    if (active > 1) overlapped = true;
    final result = results[calls.clamp(0, results.length - 1)];
    calls++;
    await Future<void>.delayed(Duration.zero);
    active--;
    if (result is RealtimeFeedSnapshot) return result;
    throw result;
  }
}

class FakeStorage implements RealtimeHistoryStorage {
  FakeStorage({this.inserted, this.matched, this.unmatched = 0, this.error});
  final int? inserted;
  final int? matched;
  final int unmatched;
  final Object? error;
  var calls = 0;
  List<HistoricalObservation>? received;

  @override
  Future<HistoryStorageResult> insertSnapshot({
    required RealtimeFeedSnapshot snapshot,
    required List<HistoricalObservation> observations,
  }) async {
    calls++;
    received = observations;
    if (error != null) throw error!;
    final matchedCount = matched ?? observations.length;
    return HistoryStorageResult(
      staticTripsMatched: matchedCount,
      unmatchedStaticTrips: unmatched,
      inserted: inserted ?? matchedCount,
      unmatchedTripIdSample: unmatched == 0 ? const [] : const ['missing-trip'],
    );
  }
}

void main() {
  test('valid snapshot converts genuine fields', () {
    final result = validateHistoricalObservations([
      validVehicle,
    ], DateTime.utc(2026));
    expect(result.invalidCount, 0);
    expect(
      result.observations.single.toDatabaseRow('import-1'),
      containsPair('recorded_at', '1970-01-01T00:01:40.000Z'),
    );
  });

  test('invalid coordinate is skipped', () {
    final result = validateHistoricalObservations([
      const RealtimeVehiclePosition(
        entityId: 'e',
        vehicleId: 'v',
        tripId: 't',
        routeId: 'r',
        latitude: 91,
        longitude: 0,
        timestampSeconds: 1,
      ),
    ], DateTime.utc(2026));
    expect(result.observations, isEmpty);
    expect(result.invalidCount, 1);
  });

  test('missing required identity is skipped', () {
    final result = validateHistoricalObservations([
      const RealtimeVehiclePosition(
        entityId: 'e',
        vehicleId: null,
        tripId: 't',
        routeId: 'r',
        latitude: 1,
        longitude: 2,
        timestampSeconds: 1,
      ),
    ], DateTime.utc(2026));
    expect(result.invalidCount, 1);
  });

  test('same genuine observation has the same duplicate identity', () {
    final values = validateHistoricalObservations([
      validVehicle,
      validVehicle,
    ], DateTime.utc(2026)).observations;
    expect(values.first.duplicateKey, values.last.duplicateKey);
  });

  test('same coordinate at newer timestamp remains distinct', () {
    final values = validateHistoricalObservations([
      validVehicle,
      const RealtimeVehiclePosition(
        entityId: 'entity-1',
        vehicleId: 'bus-1',
        tripId: 'trip-1',
        routeId: 'J10',
        latitude: 1.49,
        longitude: 103.74,
        timestampSeconds: 101,
      ),
    ], DateTime.utc(2026)).observations;
    expect(values.first.duplicateKey, isNot(values.last.duplicateKey));
  });

  test('all realtime trip IDs match current static trips', () {
    final observations = validateHistoricalObservations([
      validVehicle,
    ], DateTime.utc(2026)).observations;
    final result = matchObservationsToStaticTrips(observations, {'trip-1'});
    expect(result.matchedObservations, hasLength(1));
    expect(result.unmatchedObservationCount, 0);
    expect(result.unmatchedTripIds, isEmpty);
  });

  test('missing static trips are tracked and skipped separately', () {
    final observations = validateHistoricalObservations([
      validVehicle,
      const RealtimeVehiclePosition(
        entityId: 'entity-2',
        vehicleId: 'bus-2',
        tripId: 'missing-trip',
        routeId: 'J30',
        latitude: 1.5,
        longitude: 103.8,
        timestampSeconds: 100,
      ),
    ], DateTime.utc(2026)).observations;
    final result = matchObservationsToStaticTrips(observations, {'trip-1'});
    expect(result.matchedObservations.single.tripId, 'trip-1');
    expect(result.unmatchedObservationCount, 1);
    expect(result.unmatchedTripIds, ['missing-trip']);
  });

  test('valid snapshot is passed to storage as one batch', () async {
    final storage = FakeStorage();
    final result = await RealtimeHistoryCollector(
      repository: SequenceRepository([snapshot]),
      storage: storage,
      once: true,
      log: (_) {},
    ).collectOnce();
    expect(storage.calls, 1);
    expect(storage.received, hasLength(1));
    expect(result.inserted, 1);
    expect(result.staticTripsMatched, 1);
  });

  test('one missing static trip does not fail matched row insertion', () async {
    final result = await RealtimeHistoryCollector(
      repository: SequenceRepository([snapshot]),
      storage: FakeStorage(inserted: 1, matched: 1, unmatched: 1),
      once: true,
      log: (_) {},
    ).collectOnce();
    expect(result.error, isNull);
    expect(result.inserted, 1);
    expect(result.unmatchedStaticTrips, 1);
    expect(result.invalid, 0);
  });

  test(
    'duplicate handling is based only on static-trip-matched rows',
    () async {
      final result = await RealtimeHistoryCollector(
        repository: SequenceRepository([snapshot]),
        storage: FakeStorage(inserted: 0, matched: 1, unmatched: 2),
        once: true,
        log: (_) {},
      ).collectOnce();
      expect(result.duplicates, 1);
      expect(result.unmatchedStaticTrips, 2);
    },
  );

  test('API failure does not prevent a later cycle', () async {
    final repository = SequenceRepository([Exception('offline'), snapshot]);
    late RealtimeHistoryCollector collector;
    var waits = 0;
    collector = RealtimeHistoryCollector(
      repository: repository,
      storage: FakeStorage(),
      log: (_) {},
      wait: (_) async {
        if (++waits == 2) collector.requestStop();
      },
    );
    await collector.run();
    expect(repository.calls, 2);
    expect(collector.totals.inserted, 1);
  });

  test('storage failure is contained in the cycle result', () async {
    final result = await RealtimeHistoryCollector(
      repository: SequenceRepository([snapshot]),
      storage: FakeStorage(error: Exception('database unavailable')),
      once: true,
      log: (_) {},
    ).collectOnce();
    expect(result.error, isNotNull);
    expect(result.inserted, 0);
  });

  test(
    'static-trip lookup failure prevents insertion and fails cycle',
    () async {
      final storage = FakeStorage(error: Exception('static lookup failed'));
      final result = await RealtimeHistoryCollector(
        repository: SequenceRepository([snapshot]),
        storage: storage,
        once: true,
        log: (_) {},
      ).collectOnce();
      expect(storage.calls, 1);
      expect(result.error.toString(), contains('static lookup failed'));
      expect(result.inserted, 0);
    },
  );

  test('continuous mode recovers after static-trip lookup failure', () async {
    final repository = SequenceRepository([snapshot]);
    final storage = _SequenceStorage([
      Exception('static lookup failed'),
      const HistoryStorageResult(
        staticTripsMatched: 1,
        unmatchedStaticTrips: 0,
        inserted: 1,
      ),
    ]);
    late RealtimeHistoryCollector collector;
    var waits = 0;
    collector = RealtimeHistoryCollector(
      repository: repository,
      storage: storage,
      log: (_) {},
      wait: (_) async {
        if (++waits == 2) collector.requestStop();
      },
    );
    await collector.run();
    expect(storage.calls, 2);
    expect(collector.totals.inserted, 1);
  });

  test('cycles execute sequentially without overlap', () async {
    final repository = SequenceRepository([snapshot]);
    late RealtimeHistoryCollector collector;
    var waits = 0;
    collector = RealtimeHistoryCollector(
      repository: repository,
      storage: FakeStorage(),
      log: (_) {},
      wait: (_) async {
        if (++waits == 2) collector.requestStop();
      },
    );
    await collector.run();
    expect(repository.overlapped, isFalse);
  });

  test('stop requested after a cycle prevents a new cycle', () async {
    final repository = SequenceRepository([snapshot]);
    late RealtimeHistoryCollector collector;
    collector = RealtimeHistoryCollector(
      repository: repository,
      storage: FakeStorage(),
      log: (_) {},
      wait: (_) async => collector.requestStop(),
    );

    await collector.run();

    expect(repository.calls, 1);
    expect(collector.totals.cycles, 1);
  });

  test('--once behavior performs exactly one cycle', () async {
    final repository = SequenceRepository([snapshot]);
    await RealtimeHistoryCollector(
      repository: repository,
      storage: FakeStorage(),
      once: true,
      log: (_) {},
    ).run();
    expect(repository.calls, 1);
  });

  test('--dry-run does not access storage', () async {
    final storage = FakeStorage();
    await RealtimeHistoryCollector(
      repository: SequenceRepository([snapshot]),
      storage: storage,
      dryRun: true,
      log: (_) {},
    ).run();
    expect(storage.calls, 0);
  });
}

class _SequenceStorage implements RealtimeHistoryStorage {
  _SequenceStorage(this.results);
  final List<Object> results;
  var calls = 0;

  @override
  Future<HistoryStorageResult> insertSnapshot({
    required RealtimeFeedSnapshot snapshot,
    required List<HistoricalObservation> observations,
  }) async {
    final result = results[calls++];
    if (result is HistoryStorageResult) return result;
    throw result;
  }
}
