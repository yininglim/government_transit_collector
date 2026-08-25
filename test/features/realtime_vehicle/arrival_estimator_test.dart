import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/arrival_estimator.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';

const nextStop = TrackedTripStop(
  stopId: 'next',
  stopName: 'Next Stop',
  stopSequence: 2,
  coordinate: MapCoordinate(1.5, 103.75),
  scheduledArrivalSeconds: 25 * 3600,
  scheduledDepartureSeconds: 25 * 3600,
);

RealtimeMovementSample sample(
  double progress,
  int seconds, {
  String tripId = 'trip',
  String? vehicleId = 'bus',
}) => RealtimeMovementSample(
  tripId: tripId,
  vehicleId: vehicleId,
  routeProgressMeters: progress,
  timestamp: DateTime.utc(2026, 8, 25, 12).add(Duration(seconds: seconds)),
  latitude: 1.49,
  longitude: 103.74,
);

ArrivalEstimate estimate({
  List<RealtimeMovementSample> samples = const [],
  bool live = true,
  bool reliable = true,
  double currentProgress = 900,
  double nextProgress = 1200,
  DateTime? scheduled,
  DateTime? now,
  ArrivalEstimate? previous,
}) => const ArrivalEstimator().estimate(
  nextStop: nextStop,
  currentProgressMeters: currentProgress,
  nextStopProgressMeters: nextProgress,
  samples: samples,
  currentTransitTime: now ?? DateTime(2026, 8, 26, 0, 55),
  scheduledArrival: scheduled ?? DateTime(2026, 8, 26, 1),
  realtimeVehicleAvailable: live,
  routeProjectionReliable: reliable,
  previous: previous,
);

void main() {
  group('realtime speed', () {
    const estimator = ArrivalEstimator();

    test('uses two valid genuine observations', () {
      expect(
        estimator.stabilizedSpeedMetersPerSecond([
          sample(100, 0),
          sample(250, 30),
        ]),
        5,
      );
    });

    test('uses median across multiple observations', () {
      expect(
        estimator.stabilizedSpeedMetersPerSecond([
          sample(0, 0),
          sample(30, 10),
          sample(130, 20),
          sample(170, 30),
        ]),
        4,
      );
    });

    test('rejects non-advancing timestamps and zero intervals', () {
      expect(
        estimator.stabilizedSpeedMetersPerSecond([
          sample(0, 10),
          sample(30, 10),
          sample(60, 5),
        ]),
        isNull,
      );
    });

    test('rejects backward progress, stationary and unreasonable speed', () {
      expect(
        estimator.stabilizedSpeedMetersPerSecond([
          sample(100, 0),
          sample(90, 10),
          sample(90, 20),
          sample(1000, 30),
        ]),
        isNull,
      );
    });

    test(
      'history accepts only advancing genuine snapshots and resets identity',
      () {
        final history = RealtimeMovementHistory(maximumSamples: 3);
        expect(history.add(sample(0, 0)), isTrue);
        expect(history.add(sample(5, 0)), isFalse);
        expect(history.add(sample(10, 15)), isTrue);
        expect(history.samples, hasLength(2));
        expect(
          history.add(sample(20, 30, vehicleId: 'replacement-bus')),
          isTrue,
        );
        expect(history.samples, hasLength(1));
      },
    );
  });

  group('arrival estimate', () {
    test('produces a conservative realtime-adjusted ETA', () {
      final result = estimate(samples: [sample(700, 0), sample(900, 30)]);
      expect(result.source, ArrivalEstimateSource.realtimeAdjusted);
      expect(result.estimatedArrivalDuration, isNotNull);
      expect(result.generatedFromVehicleTimestamp, sample(900, 30).timestamp);
    });

    test('falls back to schedule with insufficient or stopped samples', () {
      for (final samples in [
        [sample(900, 0)],
        [sample(900, 0), sample(900, 30)],
      ]) {
        final result = estimate(samples: samples);
        expect(result.source, ArrivalEstimateSource.scheduledFallback);
        expect(result.estimatedArrivalDuration, const Duration(minutes: 5));
      }
    });

    test('no vehicle and unreliable projection do not claim live ETA', () {
      expect(
        estimate(live: false).source,
        ArrivalEstimateSource.scheduledFallback,
      );
      expect(
        estimate(reliable: false).source,
        ArrivalEstimateSource.scheduledFallback,
      );
    });

    test('clamps next-stop distance when the bus is just beyond it', () {
      final result = estimate(
        currentProgress: 1205,
        samples: [sample(1100, 0), sample(1205, 30)],
      );
      expect(result.source, ArrivalEstimateSource.realtimeAdjusted);
      expect(
        result.estimatedArrivalDuration!.compareTo(Duration.zero),
        greaterThanOrEqualTo(0),
      );
    });

    test('supports destination as the same next-stop model', () {
      final result = estimate(samples: [sample(800, 0), sample(900, 30)]);
      expect(result.nextStop?.stopId, 'next');
    });

    test('supports service-day schedule after 24:00', () {
      final result = estimate(
        live: false,
        now: DateTime(2026, 8, 26, 0, 55),
        scheduled: DateTime(2026, 8, 25).add(const Duration(hours: 25)),
      );
      expect(result.estimatedArrivalDuration, const Duration(minutes: 5));
    });

    test('a passed schedule is safely clamped to zero', () {
      final result = estimate(
        live: false,
        now: DateTime(2026, 8, 26, 1, 5),
        scheduled: DateTime(2026, 8, 26, 1),
      );
      expect(result.estimatedArrivalDuration, Duration.zero);
    });

    test('small evidence changes cannot make ETA jump excessively', () {
      final previous = estimate(samples: [sample(700, 0), sample(900, 30)]);
      final changed = estimate(
        currentProgress: 950,
        samples: [sample(700, 0), sample(950, 30)],
        previous: previous,
        scheduled: DateTime(2026, 8, 26, 2),
      );
      expect(
        (changed.estimatedArrivalDuration! - previous.estimatedArrivalDuration!)
            .abs(),
        lessThanOrEqualTo(defaultMaximumEtaChangePerObservation),
      );
    });

    test('missing stop or timetable is unavailable', () {
      final result = const ArrivalEstimator().estimate(
        nextStop: null,
        currentProgressMeters: 0,
        nextStopProgressMeters: 10,
        samples: const [],
        currentTransitTime: DateTime(2026),
        scheduledArrival: null,
        realtimeVehicleAvailable: false,
        routeProjectionReliable: false,
      );
      expect(result.source, ArrivalEstimateSource.unavailable);
    });

    test('rounds passenger display to practical minutes', () {
      expect(
        formatApproximateArrivalDuration(const Duration(seconds: 20)),
        '< 1 min',
      );
      expect(
        formatApproximateArrivalDuration(const Duration(seconds: 130)),
        '~2 min',
      );
      expect(
        formatApproximateArrivalDuration(const Duration(seconds: 340)),
        '~6 min',
      );
    });
  });
}
