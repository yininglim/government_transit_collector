import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';

enum JourneyStage {
  waitingForFirstLeg,
  trackingFirstLeg,
  approachingTransfer,
  waitingForSecondLeg,
  trackingSecondLeg,
  approachingDestination,
  completed,
}

class JourneyStageResult {
  const JourneyStageResult({required this.stage, required this.activeLegIndex});

  factory JourneyStageResult.initial() => const JourneyStageResult(
    stage: JourneyStage.waitingForFirstLeg,
    activeLegIndex: 0,
  );

  final JourneyStage stage;
  final int activeLegIndex;
}

/// Advances a selected journey using exact-trip availability and Step 4's
/// already-stabilized stop progress. The returned stage never regresses.
JourneyStageResult detectJourneyStage({
  required SelectedJourneyTracking journey,
  required JourneyStageResult previous,
  required List<bool> exactVehicleAvailableByLeg,
  required List<JourneyProgressState?> progressByLeg,
}) {
  final candidate = journey.isTransfer
      ? _detectTransfer(
          journey: journey,
          previous: previous,
          exactVehicleAvailableByLeg: exactVehicleAvailableByLeg,
          progressByLeg: progressByLeg,
        )
      : _detectDirect(
          journey: journey,
          previous: previous,
          exactVehicleAvailable:
              exactVehicleAvailableByLeg.firstOrNull ?? false,
          progress: progressByLeg.firstOrNull,
        );
  return _rank(candidate.stage) >= _rank(previous.stage) ? candidate : previous;
}

JourneyStageResult _detectDirect({
  required SelectedJourneyTracking journey,
  required JourneyStageResult previous,
  required bool exactVehicleAvailable,
  required JourneyProgressState? progress,
}) {
  final destinationId = journey.destinationStopId;
  if (_completed(progress, destinationId) ||
      _atRouteEnd(progress, destinationId)) {
    return const JourneyStageResult(
      stage: JourneyStage.completed,
      activeLegIndex: 0,
    );
  }
  if (_next(progress, destinationId) && exactVehicleAvailable) {
    return const JourneyStageResult(
      stage: JourneyStage.approachingDestination,
      activeLegIndex: 0,
    );
  }
  if (exactVehicleAvailable) {
    return const JourneyStageResult(
      stage: JourneyStage.trackingFirstLeg,
      activeLegIndex: 0,
    );
  }
  return previous;
}

JourneyStageResult _detectTransfer({
  required SelectedJourneyTracking journey,
  required JourneyStageResult previous,
  required List<bool> exactVehicleAvailableByLeg,
  required List<JourneyProgressState?> progressByLeg,
}) {
  final firstAvailable = exactVehicleAvailableByLeg.firstOrNull ?? false;
  final secondAvailable = exactVehicleAvailableByLeg.length > 1
      ? exactVehicleAvailableByLeg[1]
      : false;
  final firstProgress = progressByLeg.firstOrNull;
  final secondProgress = progressByLeg.length > 1 ? progressByLeg[1] : null;
  final transferId = journey.transferStopId!;
  final destinationId = journey.destinationStopId;

  if (_completed(secondProgress, destinationId) ||
      _atRouteEnd(secondProgress, destinationId)) {
    return const JourneyStageResult(
      stage: JourneyStage.completed,
      activeLegIndex: 1,
    );
  }

  final transferReached = _completed(firstProgress, transferId);
  final alreadyOnSecondLeg = previous.activeLegIndex == 1;
  if (transferReached || alreadyOnSecondLeg) {
    if (_next(secondProgress, destinationId) && secondAvailable) {
      return const JourneyStageResult(
        stage: JourneyStage.approachingDestination,
        activeLegIndex: 1,
      );
    }
    if (secondAvailable) {
      return const JourneyStageResult(
        stage: JourneyStage.trackingSecondLeg,
        activeLegIndex: 1,
      );
    }
    return JourneyStageResult(
      stage: previous.activeLegIndex == 1
          ? previous.stage
          : JourneyStage.waitingForSecondLeg,
      activeLegIndex: 1,
    );
  }

  if (_next(firstProgress, transferId) && firstAvailable) {
    return const JourneyStageResult(
      stage: JourneyStage.approachingTransfer,
      activeLegIndex: 0,
    );
  }
  if (firstAvailable) {
    return const JourneyStageResult(
      stage: JourneyStage.trackingFirstLeg,
      activeLegIndex: 0,
    );
  }
  return previous;
}

bool _completed(JourneyProgressState? progress, String stopId) =>
    progress?.availability == JourneyProgressAvailability.available &&
    progress!.completedStops.any((stop) => stop.stopId == stopId);

bool _next(JourneyProgressState? progress, String stopId) =>
    progress?.availability == JourneyProgressAvailability.available &&
    progress!.nextStop?.stopId == stopId;

bool _atRouteEnd(JourneyProgressState? progress, String stopId) =>
    progress?.availability == JourneyProgressAvailability.available &&
    progress!.nearestStop?.stopId == stopId &&
    (progress.progressFraction ?? 0) >= 0.999;

int _rank(JourneyStage stage) => switch (stage) {
  JourneyStage.waitingForFirstLeg => 0,
  JourneyStage.trackingFirstLeg => 1,
  JourneyStage.approachingTransfer => 2,
  JourneyStage.waitingForSecondLeg => 3,
  JourneyStage.trackingSecondLeg => 4,
  JourneyStage.approachingDestination => 5,
  JourneyStage.completed => 6,
};
