import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recommendation_realtime_availability.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';

const direct = DirectJourneyRecommendation(
  tripId: 'direct-trip',
  routeId: 'route-a',
  routeShortName: 'A',
  originStopId: 'origin',
  destinationStopId: 'destination',
  serviceId: 'service',
  originStopSequence: 1,
  destinationStopSequence: 2,
  departureSeconds: 100,
  arrivalSeconds: 200,
);

const transfer = TransferJourneyRecommendation(
  firstTripId: 'first-trip',
  secondTripId: 'second-trip',
  firstRouteId: 'route-a',
  firstRouteShortName: 'A',
  secondRouteId: 'route-b',
  secondRouteShortName: 'B',
  originStopId: 'origin',
  transferStopId: 'transfer',
  transferStopName: 'Transfer',
  destinationStopId: 'destination',
  firstServiceId: 'service',
  secondServiceId: 'service',
  originStopSequence: 1,
  firstTransferStopSequence: 2,
  secondTransferStopSequence: 1,
  destinationStopSequence: 2,
  departureSeconds: 100,
  transferArrivalSeconds: 150,
  secondDepartureSeconds: 160,
  arrivalSeconds: 220,
);

RealtimeVehiclePosition vehicle(String tripId, String routeId) =>
    RealtimeVehiclePosition(
      vehicleId: tripId,
      tripId: tripId,
      routeId: routeId,
      latitude: 1,
      longitude: 103,
      timestampSeconds: 1,
    );

void main() {
  test('direct requires exact trip and rejects same-route different trip', () {
    final live = evaluateRecommendationRealtimeAvailability(
      recommendations: const [direct],
      vehicles: [vehicle('direct-trip', 'route-a')],
    );
    final sameRoute = evaluateRecommendationRealtimeAvailability(
      recommendations: const [direct],
      vehicles: [vehicle('other-trip', 'route-a')],
    );
    final missing = evaluateRecommendationRealtimeAvailability(
      recommendations: const [direct],
      vehicles: const [],
    );

    expect(live[recommendationAvailabilityKey(direct)]!.firstLegLive, isTrue);
    expect(
      sameRoute[recommendationAvailabilityKey(direct)]!.firstLegLive,
      isFalse,
    );
    expect(
      missing[recommendationAvailabilityKey(direct)]!.firstLegLive,
      isFalse,
    );
  });

  test('transfer legs are evaluated independently for every combination', () {
    for (final (firstLive, secondLive) in [
      (true, true),
      (true, false),
      (false, true),
      (false, false),
    ]) {
      final availability = evaluateRecommendationRealtimeAvailability(
        recommendations: const [transfer],
        vehicles: [
          if (firstLive) vehicle('first-trip', 'route-a'),
          if (secondLive) vehicle('second-trip', 'route-b'),
        ],
      )[recommendationAvailabilityKey(transfer)]!;
      expect(availability.firstLegLive, firstLive);
      expect(availability.secondLegLive, secondLive);
    }
  });

  test(
    'availability evaluation does not reorder or replace recommendations',
    () {
      const recommendations = <JourneyRecommendation>[transfer, direct];
      final originalKeys = recommendations
          .map(recommendationAvailabilityKey)
          .toList();
      evaluateRecommendationRealtimeAvailability(
        recommendations: recommendations,
        vehicles: [vehicle('direct-trip', 'route-a')],
      );
      expect(recommendations.map(recommendationAvailabilityKey), originalKeys);
      expect(
        (recommendations.last as DirectJourneyRecommendation).tripId,
        'direct-trip',
      );
    },
  );
}
