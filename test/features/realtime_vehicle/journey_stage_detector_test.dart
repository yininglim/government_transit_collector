import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/journey_stage_detector.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';

import 'selected_journey_tracking_test.dart' as fixtures;

SelectedJourneyTracking transferJourney() =>
    SelectedJourneyTracking.fromRecommendation(
      recommendation: fixtures.transferRecommendation,
      originStopName: 'Origin Stop',
      destinationStopName: 'Destination Stop',
      travelDate: DateTime(2026, 8, 23),
    );

SelectedJourneyTracking directJourney() =>
    SelectedJourneyTracking.fromRecommendation(
      recommendation: fixtures.directRecommendation,
      originStopName: 'Origin Stop',
      destinationStopName: 'Destination Stop',
      travelDate: DateTime(2026, 8, 23),
    );

TrackedTripStop stop(String id) => TrackedTripStop(
  stopId: id,
  stopName: id,
  stopSequence: 1,
  coordinate: null,
  scheduledArrivalSeconds: null,
  scheduledDepartureSeconds: null,
);

JourneyProgressState progress({
  String? next,
  String? nearest,
  double? fraction,
  List<String> completed = const [],
}) => JourneyProgressState(
  activeTripId: 'trip',
  availability: JourneyProgressAvailability.available,
  completedStops: completed.map(stop).toList(),
  nearestStop: nearest == null ? null : stop(nearest),
  nextStop: next == null ? null : stop(next),
  upcomingStops: const [],
  timestamp: DateTime.utc(2026),
  progressFraction: fraction,
);

JourneyStageResult detectTransfer({
  JourneyStageResult? previous,
  bool firstVehicle = false,
  bool secondVehicle = false,
  JourneyProgressState? firstProgress,
  JourneyProgressState? secondProgress,
}) => detectJourneyStage(
  journey: transferJourney(),
  previous: previous ?? JourneyStageResult.initial(),
  exactVehicleAvailableByLeg: [firstVehicle, secondVehicle],
  progressByLeg: [firstProgress, secondProgress],
);

JourneyStageResult detectDirect({
  JourneyStageResult? previous,
  bool vehicle = false,
  JourneyProgressState? routeProgress,
}) => detectJourneyStage(
  journey: directJourney(),
  previous: previous ?? JourneyStageResult.initial(),
  exactVehicleAvailableByLeg: [vehicle],
  progressByLeg: [routeProgress],
);

void main() {
  group('transfer journey', () {
    test('initially waits on Leg 1', () {
      final result = detectTransfer();
      expect(result.stage, JourneyStage.waitingForFirstLeg);
      expect(result.activeLegIndex, 0);
    });

    test('tracks exact Leg 1 vehicle', () {
      expect(
        detectTransfer(firstVehicle: true).stage,
        JourneyStage.trackingFirstLeg,
      );
    });

    test('visible exact Leg 2 vehicle does not cause an early switch', () {
      final result = detectTransfer(firstVehicle: true, secondVehicle: true);
      expect(result.stage, JourneyStage.trackingFirstLeg);
      expect(result.activeLegIndex, 0);
    });

    test('transfer as next stop means approaching transfer', () {
      final result = detectTransfer(
        firstVehicle: true,
        firstProgress: progress(next: 'transfer'),
      );
      expect(result.stage, JourneyStage.approachingTransfer);
      expect(result.activeLegIndex, 0);
    });

    test('completed transfer advances to Leg 2 waiting state', () {
      final result = detectTransfer(
        firstProgress: progress(completed: ['transfer']),
      );
      expect(result.stage, JourneyStage.waitingForSecondLeg);
      expect(result.activeLegIndex, 1);
    });

    test('completed transfer with exact Leg 2 vehicle tracks Leg 2', () {
      final result = detectTransfer(
        secondVehicle: true,
        firstProgress: progress(completed: ['transfer']),
      );
      expect(result.stage, JourneyStage.trackingSecondLeg);
      expect(result.activeLegIndex, 1);
    });

    test('Leg 1 disappearance before transfer does not advance', () {
      final tracking = detectTransfer(firstVehicle: true);
      final missing = detectTransfer(previous: tracking);
      expect(missing.stage, JourneyStage.trackingFirstLeg);
      expect(missing.activeLegIndex, 0);
    });

    test('failed refresh preserves the prior reducer result', () {
      final prior = detectTransfer(firstVehicle: true);
      final afterFailure = prior;
      expect(afterFailure.stage, JourneyStage.trackingFirstLeg);
      expect(afterFailure.activeLegIndex, 0);
    });

    test('jitter or stale earlier evidence cannot regress stage', () {
      final approaching = detectTransfer(
        firstVehicle: true,
        firstProgress: progress(next: 'transfer'),
      );
      final jittered = detectTransfer(
        previous: approaching,
        firstVehicle: true,
        firstProgress: progress(next: 'earlier-stop'),
      );
      expect(jittered.stage, JourneyStage.approachingTransfer);
    });

    test('automatic Leg 2 progression never returns to Leg 1', () {
      final second = detectTransfer(
        secondVehicle: true,
        firstProgress: progress(completed: ['transfer']),
      );
      final stale = detectTransfer(
        previous: second,
        firstVehicle: true,
        firstProgress: progress(next: 'transfer'),
      );
      expect(stale.stage, JourneyStage.trackingSecondLeg);
      expect(stale.activeLegIndex, 1);
    });

    test('destination as next stop means approaching destination', () {
      final result = detectTransfer(
        previous: const JourneyStageResult(
          stage: JourneyStage.trackingSecondLeg,
          activeLegIndex: 1,
        ),
        secondVehicle: true,
        secondProgress: progress(next: 'destination'),
      );
      expect(result.stage, JourneyStage.approachingDestination);
    });

    test('completed destination completes journey', () {
      final result = detectTransfer(
        previous: const JourneyStageResult(
          stage: JourneyStage.trackingSecondLeg,
          activeLegIndex: 1,
        ),
        secondProgress: progress(completed: ['destination']),
      );
      expect(result.stage, JourneyStage.completed);
    });

    test('destination at the exact route end completes conservatively', () {
      final result = detectTransfer(
        previous: const JourneyStageResult(
          stage: JourneyStage.approachingDestination,
          activeLegIndex: 1,
        ),
        secondVehicle: true,
        secondProgress: progress(
          next: 'destination',
          nearest: 'destination',
          fraction: 1,
        ),
      );
      expect(result.stage, JourneyStage.completed);
    });

    test('vehicle disappearance near destination does not complete', () {
      const approaching = JourneyStageResult(
        stage: JourneyStage.approachingDestination,
        activeLegIndex: 1,
      );
      final result = detectTransfer(previous: approaching);
      expect(result.stage, JourneyStage.approachingDestination);
    });
  });

  group('direct journey', () {
    test('waits initially and tracks only when exact vehicle is available', () {
      expect(detectDirect().stage, JourneyStage.waitingForFirstLeg);
      expect(detectDirect(vehicle: true).stage, JourneyStage.trackingFirstLeg);
    });

    test('approaches and completes destination from progress evidence', () {
      final approaching = detectDirect(
        vehicle: true,
        routeProgress: progress(next: 'destination'),
      );
      expect(approaching.stage, JourneyStage.approachingDestination);
      final completed = detectDirect(
        previous: approaching,
        routeProgress: progress(completed: ['destination']),
      );
      expect(completed.stage, JourneyStage.completed);
    });

    test('vehicle disappearance and failed refresh preserve stage', () {
      final tracking = detectDirect(vehicle: true);
      final missing = detectDirect(previous: tracking);
      expect(missing.stage, JourneyStage.trackingFirstLeg);
      expect(missing, same(missing));
    });
  });
}
