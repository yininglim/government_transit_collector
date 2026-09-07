import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/bus_feedback/data/feedback_schedule_repository.dart';
import 'package:government_transit_collector/features/bus_feedback/data/feedback_reference_repository.dart';
import 'feedback_test_support.dart';

Map<String, dynamic> trip(String id, {bool monday = true}) => {
  'trip_id': id,
  'source_import_id': 'import-a',
  'calendar': {
    'source_import_id': 'import-a',
    'service_id': 'service-$id',
    'start_date': '2026-09-01',
    'end_date': '2026-09-30',
    'monday': monday,
    'tuesday': false,
    'wednesday': false,
    'thursday': false,
    'friday': false,
    'saturday': false,
    'sunday': false,
  },
};
Map<String, dynamic> time(
  String tripId,
  String stop,
  int sequence,
  int seconds,
) => {
  'trip_id': tripId,
  'source_import_id': 'import-a',
  'stop_id': stop,
  'stop_sequence': sequence,
  'departure_seconds': seconds,
  'stop': {'stop_id': stop, 'stop_name': 'Stop $stop'},
};

void main() {
  test('rejects stale calendar and stop times from another import', () async {
    final stale = trip('stale');
    (stale['calendar'] as Map)['source_import_id'] = 'import-b';
    final client = await feedbackClient((request) async {
      if (request.url.path.endsWith('gtfs_trips')) {
        return jsonResponse([trip('active'), stale]);
      }
      if (request.url.queryParameters.containsKey('stop_id')) {
        expect(request.url.queryParameters['trip_id'], 'in.("active")');
      }
      return jsonResponse([
        time('active', 'a', 1, 90000),
        {
          ...time('active', 'obsolete', 2, 91000),
          'source_import_id': 'import-b',
        },
      ]);
    });
    addTearDown(client.dispose);
    final repo = SupabaseFeedbackScheduleRepository(client: client);
    expect((await repo.loadRouteStops('r')).map((s) => s.id), ['a']);
    final departures = await repo.loadDepartures(
      routeId: 'r',
      stopId: 'a',
      serviceDate: DateTime(2026, 9, 7),
    );
    expect(departures.map((d) => d.seconds), [90000]);
  });

  test(
    'route stops use route trips, deduplicate and retain pattern sequence',
    () async {
      final client = await feedbackClient((request) async {
        final q = request.url.queryParameters;
        if (request.url.path.endsWith('gtfs_trips')) {
          expect(q['route_id'], 'eq.J30');
          return jsonResponse([trip('t1'), trip('t2')]);
        }
        expect(request.url.path.endsWith('gtfs_stop_times'), isTrue);
        expect(q['trip_id'], 'in.("t1","t2")');
        return jsonResponse([
          time('t2', 'c', 1, 500),
          time('t1', 'b', 2, 200),
          time('t1', 'a', 1, 100),
          time('t2', 'a', 2, 600),
        ]);
      });
      addTearDown(client.dispose);
      final rows = await SupabaseFeedbackScheduleRepository(
        client: client,
      ).loadRouteStops('J30');
      expect(rows.map((s) => s.id), ['a', 'b', 'c']);
    },
  );

  test(
    'active calendar route/stop/date produces sorted unique real departures including overnight',
    () async {
      var timeReads = 0;
      final client = await feedbackClient((request) async {
        final q = request.url.queryParameters;
        if (request.url.path.endsWith('gtfs_trips')) {
          expect(q['route_id'], 'eq.J30');
          return jsonResponse([
            trip('active'),
            trip('inactive', monday: false),
          ]);
        }
        timeReads++;
        expect(q['trip_id'], 'in.("active")');
        expect(q['stop_id'], 'eq.a');
        return jsonResponse([
          time('active', 'a', 3, 90000),
          time('active', 'a', 1, 3600),
          time('active', 'a', 2, 3600),
          time('active', 'a', 4, 7200),
        ]);
      });
      addTearDown(client.dispose);
      final repo = SupabaseFeedbackScheduleRepository(client: client);
      final rows = await repo.loadDepartures(
        routeId: 'J30',
        stopId: 'a',
        serviceDate: DateTime(2026, 9, 7),
      );
      expect(rows.map((r) => r.seconds), [3600, 7200, 90000]);
      expect(
        await repo.loadDepartures(
          routeId: 'J30',
          stopId: 'a',
          serviceDate: DateTime(2026, 9, 8),
        ),
        isEmpty,
      );
      expect(
        await repo.loadDepartures(
          routeId: 'J30',
          stopId: 'a',
          serviceDate: DateTime(2026, 10, 5),
        ),
        isEmpty,
      );
      expect(timeReads, 1);
      expect(feedbackDepartureLabel(90000), '1:00 AM (+1 day)');
      expect(feedbackDepartureLabel(3601), '1:00:01 AM');
    },
  );

  test(
    'trip-specific contextual query is restricted to route and trip',
    () async {
      final client = await feedbackClient((request) async {
        if (request.url.path.endsWith('gtfs_trips')) {
          expect(request.url.queryParameters['trip_id'], 'eq.context');
          expect(request.url.queryParameters['route_id'], 'eq.J30');
          return jsonResponse([trip('context')]);
        }
        return jsonResponse([time('context', 'a', 1, 12345)]);
      });
      addTearDown(client.dispose);
      final rows = await SupabaseFeedbackScheduleRepository(client: client)
          .loadDepartures(
            routeId: 'J30',
            stopId: 'a',
            serviceDate: DateTime(2026, 9, 7),
            tripId: 'context',
          );
      expect(rows.single.seconds, 12345);
    },
  );

  test(
    'trips and stop times paginate beyond server page before deduplication',
    () async {
      var tripPages = 0, timePages = 0;
      final client = await feedbackClient((request) async {
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        if (request.url.path.endsWith('gtfs_trips')) {
          tripPages++;
          return jsonResponse(
            offset == 0
                ? [for (var i = 0; i < 500; i++) trip('t$i')]
                : [trip('last')],
          );
        }
        timePages++;
        if (request.url.queryParameters['trip_id'] == 'in.("last")') {
          return jsonResponse([time('last', 'last-stop', 1, 100)]);
        }
        return jsonResponse(
          offset == 0
              ? [for (var i = 0; i < 500; i++) time('t0', 'a', i + 1, 100)]
              : [time('t0', 'after-page', 501, 200)],
        );
      });
      addTearDown(client.dispose);
      final rows = await SupabaseFeedbackScheduleRepository(
        client: client,
      ).loadRouteStops('route');
      expect(tripPages, 2);
      expect(timePages, 11);
      expect(
        rows.map((r) => r.id),
        containsAll(['a', 'after-page', 'last-stop']),
      );
    },
  );

  test('database error is not an empty timetable or stop list', () async {
    final client = await feedbackClient(
      (request) async => jsonResponse({'message': 'offline'}, status: 503),
    );
    addTearDown(client.dispose);
    final repo = SupabaseFeedbackScheduleRepository(client: client);
    await expectLater(
      repo.loadRouteStops('r'),
      throwsA(isA<FeedbackReferenceException>()),
    );
    await expectLater(
      repo.loadDepartures(
        routeId: 'r',
        stopId: 'a',
        serviceDate: DateTime(2026, 9, 7),
      ),
      throwsA(isA<FeedbackReferenceException>()),
    );
  });
}
