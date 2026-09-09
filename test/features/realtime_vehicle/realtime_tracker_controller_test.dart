import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/static_trip_matcher.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_tracker_controller.dart';

RealtimeFeedSnapshot snapshot(String vehicleId, {double latitude = 1.49}) =>
    RealtimeFeedSnapshot(
      vehicles: [
        RealtimeVehiclePosition(
          vehicleId: vehicleId,
          tripId: 'trip-1',
          routeId: 'J10',
          latitude: latitude,
          longitude: 103.74,
          timestampSeconds: 100,
        ),
      ],
      feedTimestampSeconds: 101,
    );

class QueueRepository implements RealtimeVehicleRepository {
  QueueRepository(this.responses);
  final List<Future<RealtimeFeedSnapshot> Function()> responses;
  int calls = 0;

  @override
  Future<RealtimeFeedSnapshot> fetchVehiclePositions() {
    final index = calls.clamp(0, responses.length - 1);
    calls++;
    return responses[index]();
  }
}

class MatchAllTrips implements StaticTripMatcher {
  @override
  Future<Set<String>> findKnownTripIds(Iterable<String> ids) async =>
      ids.toSet();
}

RealtimeTrackerController controller(
  QueueRepository repository, {
  Duration interval = const Duration(seconds: 15),
}) => RealtimeTrackerController(
  repository: repository,
  tripMatcher: MatchAllTrips(),
  pollingInterval: interval,
);

void main() {
  testWidgets('initial start fetches and periodic polling refreshes', (
    tester,
  ) async {
    final repository = QueueRepository([() async => snapshot('bus-1')]);
    final tracker = controller(repository);
    tracker.startPolling();
    await tester.pump();
    expect(repository.calls, 1);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(repository.calls, 2);
    tracker.dispose();
  });

  testWidgets('manual refresh immediately requests a feed', (tester) async {
    final repository = QueueRepository([() async => snapshot('bus-1')]);
    final tracker = controller(repository);

    await tracker.refresh();
    expect(repository.calls, 1);
    tracker.dispose();
  });

  testWidgets('overlapping periodic and manual requests are prevented', (
    tester,
  ) async {
    final pending = Completer<RealtimeFeedSnapshot>();
    final repository = QueueRepository([() => pending.future]);
    final tracker = controller(repository);
    tracker.startPolling();
    await tester.pump();

    await tracker.refresh();
    await tester.pump(const Duration(seconds: 15));
    expect(repository.calls, 1);
    pending.complete(snapshot('bus-1'));
    await tester.pump();
    tracker.dispose();
  });

  testWidgets('stopping polling cancels future timer requests', (tester) async {
    final repository = QueueRepository([() async => snapshot('bus-1')]);
    final tracker = controller(repository);
    tracker.startPolling();
    await tester.pump();
    tracker.stopPolling();

    await tester.pump(const Duration(seconds: 45));
    expect(repository.calls, 1);
    tracker.dispose();
  });

  testWidgets('successful refresh replaces rather than appends snapshot', (
    tester,
  ) async {
    final repository = QueueRepository([
      () async => snapshot('old-bus'),
      () async => snapshot('new-bus', latitude: 1.51),
    ]);
    final tracker = controller(repository);

    await tracker.refresh();
    await tracker.refresh();
    expect(tracker.snapshot!.vehicles, hasLength(1));
    expect(tracker.snapshot!.vehicles.single.vehicleId, 'new-bus');
    expect(tracker.snapshot!.vehicles.single.latitude, 1.51);
    tracker.dispose();
  });

  testWidgets('refresh failure retains previous successful vehicles', (
    tester,
  ) async {
    final repository = QueueRepository([
      () async => snapshot('bus-1'),
      () => Future.error(
        const RealtimeVehicleReadException('Network unavailable'),
      ),
    ]);
    final tracker = controller(repository);

    await tracker.refresh();
    await tracker.refresh();
    expect(tracker.snapshot!.vehicles.single.vehicleId, 'bus-1');
    expect(tracker.refreshWarning, realtimeRefreshWarning);
    tracker.dispose();
  });

  testWidgets('HTTP 429 after success remains an inline refresh warning', (
    tester,
  ) async {
    final repository = QueueRepository([
      () async => snapshot('bus-1'),
      () => Future.error(
        const RealtimeVehicleReadException(
          'Realtime service returned HTTP 429.',
        ),
      ),
    ]);
    final tracker = controller(repository);

    await tracker.refresh();
    await tracker.refresh();

    expect(tracker.snapshot!.vehicles.single.vehicleId, 'bus-1');
    expect(tracker.initialError, isNull);
    expect(tracker.refreshWarning, realtimeRefreshWarning);
    tracker.dispose();
  });

  testWidgets('failure preserves successful check time and success resets it', (
    tester,
  ) async {
    final firstCheck = DateTime.utc(2026, 9, 9, 10, 30);
    var now = firstCheck;
    final repository = QueueRepository([
      () async => snapshot('bus-1'),
      () => Future.error(
        const RealtimeVehicleReadException(
          'Realtime service returned HTTP 429.',
        ),
      ),
      () async => snapshot('bus-1', latitude: 1.52),
    ]);
    final tracker = RealtimeTrackerController(
      repository: repository,
      tripMatcher: MatchAllTrips(),
      now: () => now,
    );

    await tracker.refresh();
    expect(tracker.lastSuccessfulRefreshAt, firstCheck);
    now = firstCheck.add(const Duration(seconds: 10));
    await tracker.refresh();
    expect(tracker.lastSuccessfulRefreshAt, firstCheck);
    expect(tracker.refreshWarning, realtimeRefreshWarning);

    now = firstCheck.add(const Duration(seconds: 12));
    await tracker.refresh();
    expect(tracker.lastSuccessfulRefreshAt, now);
    expect(tracker.refreshWarning, isNull);
    expect(tracker.snapshot!.vehicles.single.latitude, 1.52);
    tracker.dispose();
  });

  testWidgets(
    'successful retry clears transient warning and records check time',
    (tester) async {
      final checkedAt = DateTime.utc(2026, 9, 9, 1, 2, 3);
      final repository = QueueRepository([
        () async => snapshot('bus-1'),
        () => Future.error(
          const RealtimeVehicleReadException('Temporary failure'),
        ),
        () async => snapshot('bus-1'),
      ]);
      final tracker = RealtimeTrackerController(
        repository: repository,
        tripMatcher: MatchAllTrips(),
        now: () => checkedAt,
      );

      await tracker.refresh();
      await tracker.refresh();
      expect(tracker.refreshWarning, isNotNull);
      await tracker.refresh();

      expect(tracker.refreshWarning, isNull);
      expect(tracker.lastSuccessfulRefreshAt, checkedAt);
      tracker.dispose();
    },
  );

  testWidgets('dispose cancels timer without later repository calls', (
    tester,
  ) async {
    final repository = QueueRepository([() async => snapshot('bus-1')]);
    final tracker = controller(repository);
    tracker.startPolling();
    await tester.pump();
    tracker.dispose();

    await tester.pump(const Duration(seconds: 30));
    expect(repository.calls, 1);
  });
}
