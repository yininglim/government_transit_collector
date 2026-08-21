import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/direct_trip_repository.dart';

DirectTripMatch trip({
  required String tripId,
  required String routeId,
  required int origin,
  required int destination,
}) {
  return DirectTripMatch(
    tripId: tripId,
    routeId: routeId,
    routeShortName: routeId,
    routeLongName: 'Test route $routeId',
    tripHeadsign: 'Terminal',
    directionId: 0,
    originStopSequence: origin,
    destinationStopSequence: destination,
  );
}

void main() {
  test('accepts origin before destination', () {
    final result = matchTripsInTravelOrder(
      candidates: [
        trip(tripId: 't1', routeId: 'J10', origin: 2, destination: 8),
      ],
    );
    expect(result.map((item) => item.tripId), ['t1']);
  });

  test('rejects destination before origin', () {
    final result = matchTripsInTravelOrder(
      candidates: [
        trip(tripId: 't1', routeId: 'J10', origin: 8, destination: 2),
      ],
    );
    expect(result, isEmpty);
  });

  test('returns no route when there are no matching trips', () {
    expect(groupDirectTripsByRoute(const []), isEmpty);
  });

  test('groups trips by route and preserves matching trip IDs', () {
    final results = groupDirectTripsByRoute([
      trip(tripId: 't1', routeId: 'J10', origin: 2, destination: 8),
      trip(tripId: 't2', routeId: 'J10', origin: 3, destination: 9),
      trip(tripId: 't3', routeId: 'J20', origin: 1, destination: 4),
    ]);

    expect(results, hasLength(2));
    expect(results.first.routeId, 'J10');
    expect(results.first.matchingTripCount, 2);
    expect(results.first.matchingTripIds, ['t1', 't2']);
  });
}
