import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';

const directRecommendation = DirectJourneyRecommendation(
  tripId: 'direct-trip',
  routeId: 'route-15',
  routeShortName: 'J15',
  originStopId: 'origin',
  destinationStopId: 'destination',
  serviceId: 'weekday',
  originStopSequence: 1,
  destinationStopSequence: 5,
  departureSeconds: 10 * 3600 + 30 * 60,
  arrivalSeconds: 11 * 3600 + 5 * 60,
);

const transferRecommendation = TransferJourneyRecommendation(
  firstTripId: 'first-trip',
  secondTripId: 'second-trip',
  firstRouteId: 'route-13',
  firstRouteShortName: 'J13',
  secondRouteId: 'route-10',
  secondRouteShortName: 'J10',
  originStopId: 'origin',
  transferStopId: 'transfer',
  transferStopName: 'JB Sentral',
  destinationStopId: 'destination',
  firstServiceId: 'weekday',
  secondServiceId: 'weekday',
  originStopSequence: 1,
  firstTransferStopSequence: 4,
  secondTransferStopSequence: 2,
  destinationStopSequence: 8,
  transferArrivalSeconds: 17 * 3600 + 10 * 60,
  secondDepartureSeconds: 17 * 3600 + 18 * 60,
  departureSeconds: 16 * 3600 + 48 * 60,
  arrivalSeconds: 18 * 3600 + 5 * 60,
);

void main() {
  test('direct model preserves exact trip, route, stops, and schedule', () {
    final journey = SelectedJourneyTracking.fromRecommendation(
      recommendation: directRecommendation,
      originStopName: 'Larkin Sentral',
      destinationStopName: 'City Square',
      travelDate: DateTime(2026, 8, 23),
    );

    expect(journey.type, SelectedJourneyType.direct);
    expect(journey.isTransfer, isFalse);
    expect(journey.originStopId, 'origin');
    expect(journey.originStopName, 'Larkin Sentral');
    expect(journey.destinationStopId, 'destination');
    expect(journey.destinationStopName, 'City Square');
    expect(journey.legs.single.tripId, 'direct-trip');
    expect(journey.legs.single.routeId, 'route-15');
    expect(journey.legs.single.routeName, 'J15');
    expect(journey.scheduledDeparture, DateTime(2026, 8, 23, 10, 30));
    expect(journey.scheduledArrival, DateTime(2026, 8, 23, 11, 5));
  });

  test('transfer model preserves both exact trips and transfer schedule', () {
    final journey = SelectedJourneyTracking.fromRecommendation(
      recommendation: transferRecommendation,
      originStopName: 'Origin Stop',
      destinationStopName: 'Destination Stop',
      travelDate: DateTime(2026, 8, 23),
    );

    expect(journey.type, SelectedJourneyType.transfer);
    expect(journey.isTransfer, isTrue);
    expect(journey.transferStopId, 'transfer');
    expect(journey.transferStopName, 'JB Sentral');
    expect(journey.legs.map((leg) => leg.tripId), [
      'first-trip',
      'second-trip',
    ]);
    expect(journey.legs.map((leg) => leg.routeName), ['J13', 'J10']);
    expect(journey.legs.first.toStopName, 'JB Sentral');
    expect(journey.legs.last.fromStopName, 'JB Sentral');
    expect(journey.legs.first.scheduledArrival, DateTime(2026, 8, 23, 17, 10));
    expect(journey.legs.last.scheduledDeparture, DateTime(2026, 8, 23, 17, 18));
  });
}
