import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/transfer_journey_repository.dart';

TransferTripEndpoint endpoint({
  required String tripId,
  required String routeId,
  required int sequence,
}) {
  return TransferTripEndpoint(
    tripId: tripId,
    routeId: routeId,
    routeShortName: routeId,
    routeLongName: 'Route $routeId',
    tripHeadsign: 'Terminal',
    endpointSequence: sequence,
  );
}

TripStopPosition stop({
  required String tripId,
  required String stopId,
  required int sequence,
}) {
  return TripStopPosition(
    tripId: tripId,
    stopId: stopId,
    stopName: 'Stop $stopId',
    stopSequence: sequence,
  );
}

List<OneTransferJourneyResult> build({
  String originId = 'origin',
  String destinationId = 'destination',
  List<TransferTripEndpoint>? originTrips,
  List<TransferTripEndpoint>? destinationTrips,
  List<TripStopPosition>? firstStops,
  List<TripStopPosition>? secondStops,
  int limit = 5,
}) {
  return buildOneTransferJourneys(
    originStopId: originId,
    destinationStopId: destinationId,
    originTrips:
        originTrips ?? [endpoint(tripId: 'a', routeId: 'J10', sequence: 1)],
    destinationTrips:
        destinationTrips ??
        [endpoint(tripId: 'b', routeId: 'J20', sequence: 8)],
    firstTripStops:
        firstStops ?? [stop(tripId: 'a', stopId: 'transfer', sequence: 4)],
    secondTripStops:
        secondStops ?? [stop(tripId: 'b', stopId: 'transfer', sequence: 3)],
    limit: limit,
  );
}

void main() {
  test('accepts valid transfer sequences on both legs', () {
    final results = build();
    expect(results, hasLength(1));
    expect(results.single.firstLeg.fromStopSequence, 1);
    expect(results.single.firstLeg.toStopSequence, 4);
    expect(results.single.secondLeg.fromStopSequence, 3);
    expect(results.single.secondLeg.toStopSequence, 8);
  });

  test('rejects transfer before origin', () {
    expect(
      build(
        firstStops: [stop(tripId: 'a', stopId: 'transfer', sequence: 1)],
      ),
      isEmpty,
    );
  });

  test('rejects destination before transfer', () {
    expect(
      build(
        secondStops: [stop(tripId: 'b', stopId: 'transfer', sequence: 9)],
      ),
      isEmpty,
    );
  });

  test('rejects same-route transfer', () {
    expect(
      build(
        destinationTrips: [endpoint(tripId: 'b', routeId: 'J10', sequence: 8)],
      ),
      isEmpty,
    );
  });

  test('rejects origin and destination as transfer stops', () {
    expect(
      build(
        firstStops: [stop(tripId: 'a', stopId: 'origin', sequence: 4)],
        secondStops: [stop(tripId: 'b', stopId: 'origin', sequence: 3)],
      ),
      isEmpty,
    );
    expect(
      build(
        firstStops: [stop(tripId: 'a', stopId: 'destination', sequence: 4)],
        secondStops: [stop(tripId: 'b', stopId: 'destination', sequence: 3)],
      ),
      isEmpty,
    );
  });

  test('deduplicates route-transfer-route patterns and retains trip pairs', () {
    final results = build(
      originTrips: [
        endpoint(tripId: 'a1', routeId: 'J10', sequence: 1),
        endpoint(tripId: 'a2', routeId: 'J10', sequence: 2),
      ],
      destinationTrips: [
        endpoint(tripId: 'b1', routeId: 'J20', sequence: 8),
        endpoint(tripId: 'b2', routeId: 'J20', sequence: 9),
      ],
      firstStops: [
        stop(tripId: 'a1', stopId: 'transfer', sequence: 4),
        stop(tripId: 'a2', stopId: 'transfer', sequence: 5),
      ],
      secondStops: [
        stop(tripId: 'b1', stopId: 'transfer', sequence: 3),
        stop(tripId: 'b2', stopId: 'transfer', sequence: 4),
      ],
    );

    expect(results, hasLength(1));
    expect(results.single.matchingTripPairs, hasLength(4));
  });

  test('enforces the configured maximum result limit', () {
    final firstStops = <TripStopPosition>[];
    final secondStops = <TripStopPosition>[];
    for (var index = 0; index < 8; index++) {
      firstStops.add(
        stop(tripId: 'a', stopId: 'transfer$index', sequence: index + 2),
      );
      secondStops.add(
        stop(tripId: 'b', stopId: 'transfer$index', sequence: index + 1),
      );
    }
    final results = build(
      destinationTrips: [endpoint(tripId: 'b', routeId: 'J20', sequence: 20)],
      firstStops: firstStops,
      secondStops: secondStops,
      limit: 5,
    );
    expect(results, hasLength(5));
  });
}
