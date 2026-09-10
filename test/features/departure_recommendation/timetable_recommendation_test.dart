import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/direct_trip_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/transfer_journey_repository.dart';

final monday = DateTime(2026, 8, 17);

GtfsServiceCalendar calendar({
  List<bool> weekdays = const [true, false, false, false, false, false, false],
  DateTime? start,
  DateTime? end,
}) {
  return GtfsServiceCalendar(
    serviceId: 'service',
    startDate: start ?? DateTime(2026, 8, 1),
    endDate: end ?? DateTime(2026, 8, 31),
    weekdays: weekdays,
  );
}

const direct = DirectRouteResult(
  routeId: 'J15',
  routeShortName: 'J15',
  routeLongName: null,
  tripHeadsign: null,
  matchingTripIds: ['direct'],
);

const transfer = OneTransferJourneyResult(
  firstLeg: TransferJourneyLeg(
    routeId: 'J10',
    routeShortName: 'J10',
    routeLongName: null,
    tripId: 'first',
    tripHeadsign: null,
    fromStopId: 'origin',
    toStopId: 'transfer',
    fromStopSequence: 1,
    toStopSequence: 5,
  ),
  transferStopId: 'transfer',
  transferStopName: 'Transfer Stop',
  secondLeg: TransferJourneyLeg(
    routeId: 'J20',
    routeShortName: 'J20',
    routeLongName: null,
    tripId: 'second',
    tripHeadsign: null,
    fromStopId: 'transfer',
    toStopId: 'destination',
    fromStopSequence: 2,
    toStopSequence: 8,
  ),
  matchingTripPairs: [
    TransferTripPair(firstTripId: 'first', secondTripId: 'second'),
  ],
);

GtfsStopTimeValue time(
  String tripId,
  String stopId,
  int sequence,
  int seconds,
) {
  return GtfsStopTimeValue(
    tripId: tripId,
    stopId: stopId,
    stopSequence: sequence,
    arrivalSeconds: seconds,
    departureSeconds: seconds,
  );
}

List<JourneyRecommendation> build({
  int selectedSeconds = 9 * 3600,
  DateTime Function()? now,
  TravelTimeMode mode = TravelTimeMode.departAt,
  List<DirectRouteResult> directRoutes = const [],
  List<OneTransferJourneyResult> transfers = const [],
  List<GtfsTripService> services = const [],
  List<GtfsStopTimeValue> times = const [],
  int buffer = defaultMinimumTransferSeconds,
  int limit = defaultRecommendationLimit,
}) {
  return buildTimetableRecommendations(
    originStopId: 'origin',
    destinationStopId: 'destination',
    travelDate: monday,
    travelTimeSeconds: selectedSeconds,
    now: now ?? () => DateTime.utc(2026, 8, 16, 16),
    mode: mode,
    directRoutes: directRoutes,
    transferJourneys: transfers,
    tripServices: services,
    calendars: [calendar()],
    stopTimes: times,
    minimumTransferSeconds: buffer,
    limit: limit,
  );
}

TransferJourneyRecommendation transferRecommendation({
  String firstTripId = 'first',
  String secondTripId = 'second',
  String firstRouteId = 'J10',
  String transferStopId = 'transfer',
  String secondRouteId = 'J20',
  int departureSeconds = 10 * 3600,
  int transferArrivalSeconds = 10 * 3600 + 20 * 60,
  int secondDepartureSeconds = 10 * 3600 + 25 * 60,
  int arrivalSeconds = 11 * 3600,
}) {
  return TransferJourneyRecommendation(
    firstTripId: firstTripId,
    secondTripId: secondTripId,
    firstRouteId: firstRouteId,
    firstRouteShortName: firstRouteId,
    secondRouteId: secondRouteId,
    secondRouteShortName: secondRouteId,
    originStopId: 'origin',
    transferStopId: transferStopId,
    transferStopName: 'Stop $transferStopId',
    destinationStopId: 'destination',
    firstServiceId: 'service',
    secondServiceId: 'service',
    originStopSequence: 1,
    firstTransferStopSequence: 5,
    secondTransferStopSequence: 2,
    destinationStopSequence: 8,
    departureSeconds: departureSeconds,
    transferArrivalSeconds: transferArrivalSeconds,
    secondDepartureSeconds: secondDepartureSeconds,
    arrivalSeconds: arrivalSeconds,
  );
}

DirectJourneyRecommendation directRecommendation({
  required String tripId,
  String routeId = 'J15',
  int departureSeconds = 10 * 3600,
  required int arrivalSeconds,
}) {
  return DirectJourneyRecommendation(
    tripId: tripId,
    routeId: routeId,
    routeShortName: routeId,
    originStopId: 'origin',
    destinationStopId: 'destination',
    serviceId: 'service',
    originStopSequence: 1,
    destinationStopSequence: 5,
    departureSeconds: departureSeconds,
    arrivalSeconds: arrivalSeconds,
  );
}

void main() {
  test(
    'review: past service dates expire and overnight departures survive midnight',
    () {
      final midnight = DateTime.utc(2026, 8, 17, 16);
      expect(
        minimumCurrentDepartureSeconds(monday, now: () => midnight),
        86400,
      );
      expect(
        minimumCurrentDepartureSeconds(
          monday,
          now: () => midnight.add(const Duration(microseconds: 1)),
        ),
        86401,
      );
      expect(
        minimumCurrentDepartureSeconds(
          DateTime(2026, 8, 19),
          now: () => midnight,
        ),
        0,
      );
      for (final mode in TravelTimeMode.values) {
        List<JourneyRecommendation> at(int departure, DateTime now) => build(
          now: () => now,
          mode: mode,
          selectedSeconds: mode == TravelTimeMode.arriveBy ? 30 * 3600 : 0,
          directRoutes: const [direct],
          transfers: const [transfer],
          services: const [
            GtfsTripService(tripId: 'direct', serviceId: 'service'),
            GtfsTripService(tripId: 'first', serviceId: 'service'),
            GtfsTripService(tripId: 'second', serviceId: 'service'),
          ],
          times: [
            time('direct', 'origin', 1, departure),
            time('direct', 'destination', 5, departure + 3600),
            time('first', 'origin', 1, departure),
            time('first', 'transfer', 5, departure + 600),
            time('second', 'transfer', 2, departure + 900),
            time('second', 'destination', 8, departure + 3600),
          ],
        );
        expect(at(9 * 3600, midnight), isEmpty);
        expect(at(25 * 3600, midnight), hasLength(2));
        expect(
          at(
            25 * 3600,
            midnight.add(const Duration(hours: 1, microseconds: 1)),
          ),
          isEmpty,
        );
      }
    },
  );

  test('today filters past direct and transfer departures in both modes', () {
    for (final mode in TravelTimeMode.values) {
      List<JourneyRecommendation> search(DateTime instant, {int? selected}) =>
          build(
            now: () => instant,
            mode: mode,
            selectedSeconds:
                selected ??
                (mode == TravelTimeMode.departAt ? 9 * 3600 : 11 * 3600),
            directRoutes: [direct],
            transfers: [transfer],
            services: const [
              GtfsTripService(tripId: 'direct', serviceId: 'service'),
              GtfsTripService(tripId: 'first', serviceId: 'service'),
              GtfsTripService(tripId: 'second', serviceId: 'service'),
            ],
            times: [
              time('direct', 'origin', 1, 10 * 3600),
              time('direct', 'destination', 5, 11 * 3600),
              time('first', 'origin', 1, 10 * 3600),
              time('first', 'transfer', 5, 10 * 3600 + 1200),
              time('second', 'transfer', 2, 10 * 3600 + 1500),
              time('second', 'destination', 8, 11 * 3600),
            ],
          );
      // 02:00 UTC is 10:00 Malaysia, regardless of the device timezone.
      expect(search(DateTime.utc(2026, 8, 17, 2)), hasLength(2));
      expect(search(DateTime.utc(2026, 8, 17, 2, 0, 0, 1)), isEmpty);
      expect(
        search(
          DateTime.utc(2026, 8, 17, 1),
          selected: mode == TravelTimeMode.departAt
              ? 10 * 3600 + 1
              : 11 * 3600 - 1,
        ),
        isEmpty,
      );
      expect(search(DateTime.utc(2026, 8, 16, 2)), hasLength(2));
    }
  });

  test('alternatives prefer GTFS diversity before repeated departures', () {
    final best = directRecommendation(tripId: 'best', arrivalSeconds: 40000);
    final repeated = directRecommendation(
      tripId: 'later',
      departureSeconds: 37000,
      arrivalSeconds: 41000,
    );
    final other = directRecommendation(
      tripId: 'other',
      routeId: 'J99',
      arrivalSeconds: 42000,
    );
    final transfer = transferRecommendation();
    expect(
      selectJourneyAlternatives([best, repeated, other, transfer], limit: 3),
      [best, other, transfer],
    );
    expect(selectJourneyAlternatives([best, repeated], limit: 3), [
      best,
      repeated,
    ]);
  });

  group('service calendar', () {
    test('accepts enabled weekday within date range', () {
      expect(calendar().operatesOn(monday), isTrue);
    });

    test('rejects disabled weekday', () {
      expect(
        calendar().operatesOn(monday.add(const Duration(days: 1))),
        isFalse,
      );
    });

    test('rejects date before service start', () {
      expect(calendar().operatesOn(DateTime(2026, 7, 27)), isFalse);
    });

    test('rejects date after service end', () {
      expect(calendar().operatesOn(DateTime(2026, 9, 7)), isFalse);
    });
  });

  group('GTFS service-day time', () {
    test('converts selected time to service seconds', () {
      expect(
        timeOfDayToServiceSeconds(const TimeOfDay(hour: 15, minute: 45)),
        56700,
      );
    });

    test('formats normal and after-24-hour times', () {
      expect(formatServiceDaySeconds(15 * 3600 + 30 * 60), '3:30 PM');
      expect(formatServiceDaySeconds(24 * 3600 + 10 * 60), '12:10 AM');
      expect(formatServiceDaySeconds(25 * 3600 + 20 * 60), '1:20 AM');
    });

    test('calculates duration across service-day midnight', () {
      expect(
        formatDurationMinutes(25 * 3600 - (23 * 3600 + 30 * 60)),
        '1h 30m',
      );
    });
  });

  group('direct timetable matching', () {
    final services = const [
      GtfsTripService(tripId: 'direct', serviceId: 'service'),
    ];
    final times = [
      time('direct', 'origin', 1, 10 * 3600),
      time('direct', 'destination', 5, 10 * 3600 + 30 * 60),
    ];

    test(
      'accepts departure after selected time with correct arrival and duration',
      () {
        final result = build(
          directRoutes: const [direct],
          services: services,
          times: times,
        );
        final recommendation = result.single as DirectJourneyRecommendation;
        expect(recommendation.arrivalSeconds, 10 * 3600 + 30 * 60);
        expect(recommendation.durationSeconds, 30 * 60);
      },
    );

    test('rejects departure before selected time', () {
      expect(
        build(
          selectedSeconds: 10 * 3600 + 1,
          directRoutes: const [direct],
          services: services,
          times: times,
        ),
        isEmpty,
      );
    });
  });

  group('transfer timetable matching', () {
    final services = const [
      GtfsTripService(tripId: 'first', serviceId: 'service'),
      GtfsTripService(tripId: 'second', serviceId: 'service'),
    ];

    List<GtfsStopTimeValue> times(int secondDeparture) => [
      time('first', 'origin', 1, 10 * 3600),
      time('first', 'transfer', 5, 10 * 3600 + 20 * 60),
      time('second', 'transfer', 2, secondDeparture),
      time('second', 'destination', 8, 11 * 3600),
    ];

    test('accepts valid transfer and calculates wait and total duration', () {
      final result = build(
        transfers: const [transfer],
        services: services,
        times: times(10 * 3600 + 28 * 60),
      );
      final recommendation = result.single as TransferJourneyRecommendation;
      expect(recommendation.transferWaitSeconds, 8 * 60);
      expect(recommendation.durationSeconds, 60 * 60);
    });

    test('accepts transfer buffer exactly satisfied', () {
      expect(
        build(
          transfers: const [transfer],
          services: services,
          times: times(10 * 3600 + 25 * 60),
        ),
        hasLength(1),
      );
    });

    test('rejects second bus that leaves too early or misses buffer', () {
      expect(
        build(
          transfers: const [transfer],
          services: services,
          times: times(10 * 3600 + 24 * 60),
        ),
        isEmpty,
      );
      expect(
        build(
          transfers: const [transfer],
          services: services,
          times: times(10 * 3600 + 19 * 60),
        ),
        isEmpty,
      );
    });
  });

  test('ranks direct and transfer together by arrival and limits to five', () {
    final routes = <DirectRouteResult>[
      for (var index = 0; index < 6; index++)
        DirectRouteResult(
          routeId: 'route$index',
          routeShortName: null,
          routeLongName: null,
          tripHeadsign: null,
          matchingTripIds: ['trip$index'],
        ),
    ];
    final services = <GtfsTripService>[
      for (var index = 0; index < 6; index++)
        GtfsTripService(tripId: 'trip$index', serviceId: 'service'),
      const GtfsTripService(tripId: 'first', serviceId: 'service'),
      const GtfsTripService(tripId: 'second', serviceId: 'service'),
    ];
    final times = <GtfsStopTimeValue>[
      for (var index = 0; index < 6; index++) ...[
        time('trip$index', 'origin', 1, 10 * 3600),
        time('trip$index', 'destination', 2, 11 * 3600 + index),
      ],
      time('first', 'origin', 1, 9 * 3600 + 10 * 60),
      time('first', 'transfer', 5, 9 * 3600 + 20 * 60),
      time('second', 'transfer', 2, 9 * 3600 + 25 * 60),
      time('second', 'destination', 8, 9 * 3600 + 50 * 60),
    ];
    final results = build(
      directRoutes: routes,
      transfers: const [transfer],
      services: services,
      times: times,
    );

    expect(results.first, isA<TransferJourneyRecommendation>());
    expect(results, hasLength(5));
  });

  group('equivalent recommendation pruning', () {
    test('keeps earliest arrival for same transfer pattern and departure', () {
      final earlier = transferRecommendation(
        secondTripId: 'second-a',
        secondDepartureSeconds: 10 * 3600 + 25 * 60,
        arrivalSeconds: 11 * 3600,
      );
      final later = transferRecommendation(
        secondTripId: 'second-b',
        secondDepartureSeconds: 10 * 3600 + 45 * 60,
        arrivalSeconds: 11 * 3600 + 20 * 60,
      );

      final results = pruneEquivalentRecommendations([later, earlier]);

      expect(results, [earlier]);
    });

    test('uses shorter transfer wait when equivalent arrivals tie', () {
      final shorterWait = transferRecommendation(
        secondTripId: 'second-a',
        secondDepartureSeconds: 10 * 3600 + 25 * 60,
        arrivalSeconds: 11 * 3600,
      );
      final longerWait = transferRecommendation(
        secondTripId: 'second-b',
        secondDepartureSeconds: 10 * 3600 + 35 * 60,
        arrivalSeconds: 11 * 3600,
      );

      final results = pruneEquivalentRecommendations([longerWait, shorterWait]);

      expect(results, [shorterWait]);
    });

    test('retains same pattern with different initial departure times', () {
      final results = pruneEquivalentRecommendations([
        transferRecommendation(departureSeconds: 10 * 3600),
        transferRecommendation(
          firstTripId: 'first-later',
          secondTripId: 'second-later',
          departureSeconds: 10 * 3600 + 30 * 60,
          transferArrivalSeconds: 10 * 3600 + 50 * 60,
          secondDepartureSeconds: 10 * 3600 + 55 * 60,
          arrivalSeconds: 11 * 3600 + 30 * 60,
        ),
      ]);
      expect(results, hasLength(2));
    });

    test('retains different transfer stops', () {
      final results = pruneEquivalentRecommendations([
        transferRecommendation(transferStopId: 'transfer-a'),
        transferRecommendation(
          transferStopId: 'transfer-b',
          firstTripId: 'first-b',
          secondTripId: 'second-b',
        ),
      ]);
      expect(results, hasLength(2));
    });

    test('retains different route combinations', () {
      final results = pruneEquivalentRecommendations([
        transferRecommendation(firstRouteId: 'J10', secondRouteId: 'J20'),
        transferRecommendation(
          firstTripId: 'first-b',
          secondTripId: 'second-b',
          firstRouteId: 'J11',
          secondRouteId: 'J21',
        ),
      ]);
      expect(results, hasLength(2));
    });

    test('prunes direct duplicates by route and departure', () {
      final earlier = directRecommendation(
        tripId: 'direct-a',
        arrivalSeconds: 10 * 3600 + 30 * 60,
      );
      final later = directRecommendation(
        tripId: 'direct-b',
        arrivalSeconds: 10 * 3600 + 45 * 60,
      );

      final results = pruneEquivalentRecommendations([later, earlier]);

      expect(results, [earlier]);
    });
  });
}
