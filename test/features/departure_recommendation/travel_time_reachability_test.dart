import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/direct_trip_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/transfer_journey_repository.dart';
import 'timetable_recommendation_test.dart' as f;

TransferTripEndpoint endpoint(String trip, String route, int sequence) =>
    TransferTripEndpoint(
      tripId: trip,
      routeId: route,
      routeShortName: route,
      routeLongName: null,
      tripHeadsign: null,
      endpointSequence: sequence,
    );
TripStopPosition stop(String trip, String id, int sequence) => TripStopPosition(
  tripId: trip,
  stopId: id,
  stopName: id,
  stopSequence: sequence,
);

void main() {
  List<JourneyRecommendation> search(TravelTimeMode mode, int target) =>
      buildTimetableRecommendations(
        originStopId: 'origin',
        destinationStopId: 'destination',
        travelDate: f.monday,
        now: () => DateTime.utc(2026, 8, 16, 16),
        travelTimeSeconds: target,
        mode: mode,
        directRoutes: const [
          DirectRouteResult(
            routeId: 'J15',
            routeShortName: 'J15',
            routeLongName: null,
            tripHeadsign: null,
            matchingTripIds: ['early', 'target', 'late'],
          ),
        ],
        transferJourneys: const [f.transfer],
        tripServices: [
          for (final id in ['early', 'target', 'late', 'first', 'second'])
            GtfsTripService(tripId: id, serviceId: 'service'),
        ],
        calendars: [f.calendar()],
        stopTimes: [
          f.time('early', 'origin', 1, 8 * 3600),
          f.time('early', 'destination', 2, 8 * 3600 + 30 * 60),
          f.time('target', 'origin', 1, 8 * 3600 + 20 * 60),
          f.time('target', 'destination', 2, 9 * 3600),
          f.time('late', 'origin', 1, 8 * 3600 + 25 * 60),
          f.time('late', 'destination', 2, 9 * 3600 + 1),
          f.time('first', 'origin', 1, 8 * 3600),
          f.time('first', 'transfer', 5, 8 * 3600 + 20 * 60),
          f.time('second', 'transfer', 2, 8 * 3600 + 25 * 60),
          f.time('second', 'destination', 8, 8 * 3600 + 55 * 60),
        ],
      );

  test(
    'Arrive By includes exact target, excludes late journeys, retains transfers',
    () {
      final rows = search(TravelTimeMode.arriveBy, 9 * 3600);
      expect(rows.length, 3);
      expect((rows.first as DirectJourneyRecommendation).tripId, 'target');
      expect(rows.every((j) => j.arrivalSeconds <= 9 * 3600), isTrue);
      expect(rows.whereType<TransferJourneyRecommendation>(), hasLength(1));
      final earlier = search(TravelTimeMode.arriveBy, 8 * 3600 + 54 * 60);
      expect(earlier.whereType<TransferJourneyRecommendation>(), isEmpty);
    },
  );
  test(
    'Depart At keeps departures at or after target and earliest arrival first',
    () {
      final rows = search(TravelTimeMode.departAt, 8 * 3600 + 20 * 60);
      expect(rows.length, 2);
      expect(
        rows.every((j) => j.departureSeconds >= 8 * 3600 + 20 * 60),
        isTrue,
      );
      expect((rows.first as DirectJourneyRecommendation).tripId, 'target');
    },
  );
  test('Best Choice ties are deterministic and reasons use actual data', () {
    final a = f.directRecommendation(tripId: 'a', arrivalSeconds: 11 * 3600);
    final b = f.directRecommendation(tripId: 'b', arrivalSeconds: 11 * 3600);
    for (final mode in TravelTimeMode.values) {
      final rows = [b, a]
        ..sort((a, b) => compareJourneyRecommendations(a, b, mode));
      expect(rows.first.tripId, 'a');
    }
    expect(
      journeyRecommendationReasons(a, TravelTimeMode.arriveBy, 11 * 3600),
      ['Arrives at or before your 11:00 AM target', 'Direct journey'],
    );
    expect(journeyRecommendationReasons(a, TravelTimeMode.arriveBy, 9 * 3600), [
      'Direct journey',
    ]);
  });
  test(
    'reachable stops exclude origin/upstream, deduplicate, preserve one transfer',
    () {
      final rows = buildReachableDestinations(
        originStopId: 'C',
        originTrips: [endpoint('first', 'R1', 3)],
        firstTripStops: [
          stop('first', 'A', 1),
          stop('first', 'B', 2),
          stop('first', 'C', 3),
          stop('first', 'D', 4),
          stop('first', 'E', 5),
          stop('first', 'D', 6),
        ],
        transferTripsByStop: {
          'D': [endpoint('second', 'R2', 2), endpoint('same-route', 'R1', 1)],
        },
        secondTripStops: [
          stop('second', 'X', 1),
          stop('second', 'D', 2),
          stop('second', 'F', 3),
          stop('second', 'C', 4),
          stop('same-route', 'G', 2),
        ],
      );
      expect(rows.map((s) => s.id), ['D', 'E', 'F']);
    },
  );
}
