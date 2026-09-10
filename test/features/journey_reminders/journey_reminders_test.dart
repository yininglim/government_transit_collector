import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_reminders/journey_reminder.dart';
import 'package:government_transit_collector/features/journey_reminders/reminder_repository.dart';
import 'package:government_transit_collector/features/journey_reminders/reminder_notifications.dart';
import 'package:government_transit_collector/features/journey_reminders/reminder_controller.dart';
import 'package:government_transit_collector/features/journey_reminders/reminder_widgets.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/saved_journey_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_recommendation_page.dart';
import '../departure_recommendation/departure_recommendation_test.dart'
    as fixtures;

class MemoryReminders implements ReminderRepository {
  @override
  String? userId = 'a';
  final rows = <JourneyReminder>[];
  int nextId = 1;
  @override
  Future<List<JourneyReminder>> load() async =>
      rows.where((r) => r.owner == userId).toList();
  @override
  Future<JourneyReminder> create(
    ReminderJourney journey,
    int offset,
    DateTime now,
  ) async {
    for (final r in rows) {
      if (r.owner == userId && r.journey.key == journey.key) return r;
    }
    final r = JourneyReminder({
      ...journey.data,
      'reminder_id': nextId++,
      'user_id': userId,
      'reminder_offset_minutes': offset,
      'reminder_at': journey.reminderTime(offset, now).toIso8601String(),
    });
    rows.add(r);
    return r;
  }

  @override
  Future<void> delete(int id) async =>
      rows.removeWhere((r) => r.id == id && r.owner == userId);
}

class FakeNotifications implements ReminderNotifications {
  bool allowed = true;
  bool failSchedule = false;
  final scheduled = <int, JourneyReminder>{};
  final cancelled = <int>[];
  final permissionRequests = <bool>[];
  @override
  Future<bool> permission({required bool request}) async {
    permissionRequests.add(request);
    return allowed;
  }

  @override
  Future<void> schedule(JourneyReminder r) async {
    if (failSchedule) throw StateError('platform failed');
    scheduled[r.id] = r;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async => scheduled.clear();
}

final date = DateTime(2030, 9, 7);
final now = DateTime.utc(2030, 9, 7, 6);
ReminderJourney journey({bool transfer = false}) =>
    ReminderJourney.fromRecommendation(
      transfer
          ? fixtures.transferRecommendation
          : fixtures.directRecommendation,
      date,
      'Hab Sutera Mall',
      'UTM Skudai',
    );

void main() {
  late MemoryReminders repository;
  late FakeNotifications notifications;
  late ReminderController controller;
  setUp(() {
    repository = MemoryReminders();
    notifications = FakeNotifications();
    controller = ReminderController(repository, notifications, now: () => now);
  });
  tearDown(() => controller.dispose());

  test(
    'refresh preserves due notifications and hides only departed journeys',
    () async {
      var clock = now;
      final local = ReminderController(
        repository,
        notifications,
        now: () => clock,
      );
      addTearDown(local.dispose);
      await local.set(journey(), 10);
      final record = local.upcoming.single;
      expect(
        record.reminderAt,
        journey().departure.subtract(const Duration(minutes: 10)),
      );
      expect(reminderDisplayTime(record.reminderAt), '7/9/2030, 3:45 PM');
      clock = record.reminderAt.add(const Duration(seconds: 1));
      await local.refresh();
      expect(notifications.scheduled, contains(record.id));
      expect(local.upcoming.single.id, record.id);
      clock = record.journey.departure;
      await local.refresh();
      expect(local.upcoming, isEmpty);
      expect(repository.rows.single.id, record.id);
    },
  );

  test('GTFS after-midnight seconds preserve original service date', () {
    const overnight = DirectJourneyRecommendation(
      tripId: 'night',
      routeId: 'J34',
      routeShortName: 'J34',
      originStopId: 'a',
      destinationStopId: 'b',
      serviceId: 'night',
      originStopSequence: 1,
      destinationStopSequence: 2,
      departureSeconds: 25 * 3600,
      arrivalSeconds: 26 * 3600,
    );
    final j = ReminderJourney.fromRecommendation(overnight, date, 'A', 'B');
    expect(j.data['service_date'], '2030-09-07');
    expect(j.data['scheduled_departure_seconds'], 90000);
    expect(j.departure, DateTime.utc(2030, 9, 7, 17));
    expect(reminderDisplayTime(j.departure), '8/9/2030, 1:00 AM');
  });

  testWidgets(
    'long labels and multiple upcoming cards scroll at narrow phone width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final long = ReminderJourney({
        ...journey().data,
        'route_label':
            'J34 via a very long route label → J30 via another long route label',
        'origin_stop_name':
            'Hab Sutera Mall with an exceptionally long boarding stop name',
        'destination_stop_name':
            'UTM Skudai with an exceptionally long destination stop name',
      });
      await controller.set(long, 10);
      await controller.set(journey(transfer: true), 5);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [UpcomingJourneys(controller: controller)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(long.route));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      for (final r in controller.upcoming) {
        await controller.cancel(r);
      }
    },
  );

  test('direct uses exact scheduled boarding departure and service date', () {
    final j = journey();
    expect(j.departure, DateTime.utc(2030, 9, 7, 7, 55));
    expect(
      j.data['scheduled_departure_seconds'],
      fixtures.directRecommendation.departureSeconds,
    );
    expect(j.data['service_date'], '2030-09-07');
  });
  test(
    'transfer retains both routes, overall stops and first boarding departure',
    () {
      final j = journey(transfer: true);
      expect(j.route, 'J15 → J10');
      expect(j.data['route_ids'], ['J15', 'J10']);
      expect(j.data['origin_stop_id'], 'larkin');
      expect(j.data['destination_stop_id'], 'jb');
      expect(j.origin, 'Hab Sutera Mall');
      expect(j.destination, 'UTM Skudai');
      expect(j.departure, DateTime.utc(2030, 9, 7, 7, 45));
    },
  );
  for (final offset in reminderOffsets) {
    test('$offset minute timestamp and persisted selection', () async {
      await controller.set(journey(), offset);
      final r = controller.upcoming.single;
      expect(
        r.reminderAt,
        journey().departure.subtract(Duration(minutes: offset)),
      );
      expect(r.data['reminder_offset_minutes'], offset);
      expect(notifications.scheduled.length, 1);
    });
  }
  test('past offset rejected while later option remains usable', () {
    final j = journey();
    final near = j.departure.subtract(const Duration(minutes: 8));
    expect(() => j.reminderTime(10, near), throwsA(isA<ReminderException>()));
    expect(j.reminderTime(5, near).isAfter(near), isTrue);
  });
  test('past departure and too-soon departure rejected including boundary', () {
    final j = journey();
    for (final instant in [
      j.departure,
      j.departure.add(const Duration(seconds: 1)),
      j.departure.subtract(const Duration(minutes: 5)),
    ]) {
      expect(
        () => j.reminderTime(5, instant),
        throwsA(isA<ReminderException>()),
      );
    }
  });
  test(
    'stable identity ignores display names and distinguishes service dates',
    () {
      final j = journey();
      expect(
        ReminderJourney.fromRecommendation(
          fixtures.directRecommendation,
          date,
          'Renamed',
          'Stop',
        ).key,
        j.key,
      );
      expect(
        ReminderJourney.fromRecommendation(
          fixtures.directRecommendation,
          date.add(const Duration(days: 1)),
          'A',
          'B',
        ).key,
        isNot(j.key),
      );
    },
  );
  test(
    'duplicate repeated concurrent taps schedule one owned reminder',
    () async {
      await Future.wait([
        controller.set(journey(), 10),
        controller.set(journey(), 10),
      ]);
      expect(repository.rows.length, 1);
      expect(controller.upcoming.single.owner, 'a');
      expect(notifications.scheduled.length, 1);
    },
  );
  test(
    'cancel calls notification cancellation, removes record and permits recreation',
    () async {
      await controller.set(journey(), 10);
      final r = controller.upcoming.single;
      await controller.cancel(r);
      expect(notifications.cancelled, contains(r.id));
      expect(notifications.scheduled, isEmpty);
      expect(repository.rows, isEmpty);
      expect(controller.matching(journey()), isNull);
      await controller.set(journey(), 5);
      expect(controller.upcoming.length, 1);
    },
  );
  test(
    'logout and another account cannot mix records; login restores original',
    () async {
      await controller.set(journey(), 10);
      repository.userId = null;
      await controller.refresh();
      expect(controller.upcoming, isEmpty);
      expect(repository.rows.length, 1);
      expect(notifications.scheduled, isEmpty);
      repository.userId = 'b';
      await controller.refresh();
      expect(controller.upcoming, isEmpty);
      await controller.set(journey(), 5);
      expect(controller.upcoming.single.owner, 'b');
      repository.userId = 'a';
      await controller.refresh();
      expect(controller.upcoming.single.owner, 'a');
      expect(controller.upcoming.single.data['reminder_offset_minutes'], 10);
      expect(notifications.permissionRequests.last, false);
    },
  );
  test(
    'restart reloads persisted reminders in chronological order and hides past',
    () async {
      await controller.set(journey(), 10);
      await controller.set(journey(transfer: true), 10);
      repository.rows.add(
        JourneyReminder({
          ...journey().data,
          'reminder_id': 900,
          'user_id': 'a',
          'scheduled_departure_at': now
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          'reminder_at': now
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
        }),
      );
      final restored = ReminderController(
        repository,
        notifications,
        now: () => now,
      );
      await restored.refresh();
      expect(restored.upcoming.map((r) => r.journey.route), [
        'J15 → J10',
        'J15',
      ]);
      restored.dispose();
    },
  );
  test('permission denial creates no record and schedules nothing', () async {
    notifications.allowed = false;
    await expectLater(
      controller.set(journey(), 10),
      throwsA(isA<ReminderException>()),
    );
    expect(repository.rows, isEmpty);
    expect(notifications.scheduled, isEmpty);
    expect(controller.busy, false);
  });
  test('platform scheduling failure rolls back persisted reminder', () async {
    notifications.failSchedule = true;
    await expectLater(controller.set(journey(), 10), throwsStateError);
    expect(repository.rows, isEmpty);
    expect(controller.upcoming, isEmpty);
  });

  for (final offset in reminderOffsets) {
    testWidgets(
      'sheet defaults to 10 and supports selecting $offset at phone size',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReminderSheet(controller: controller, journey: journey()),
            ),
          ),
        );
        expect(
          tester
              .widget<RadioGroup<int>>(find.byType(RadioGroup<int>))
              .groupValue,
          10,
        );
        await tester.ensureVisible(find.text('$offset minutes before'));
        await tester.tap(find.text('$offset minutes before'));
        await tester.pump();
        await tester.ensureVisible(find.text('Set Reminder'));
        await tester.tap(find.text('Set Reminder'));
        await tester.pumpAndSettle();
        expect(repository.rows.single.data['reminder_offset_minutes'], offset);
        expect(tester.takeException(), isNull);
        await controller.cancel(controller.upcoming.single);
      },
    );
  }
  testWidgets('permission denied sheet shows friendly error without crashing', (
    tester,
  ) async {
    notifications.allowed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderSheet(controller: controller, journey: journey()),
        ),
      ),
    );
    await tester.tap(find.text('Set Reminder'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow notifications'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('upcoming shows route, stops, times, summary, and cancellation', (
    tester,
  ) async {
    await controller.set(journey(transfer: true), 10);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [UpcomingJourneys(controller: controller)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('J15 → J10'), findsOneWidget);
    expect(find.text('Hab Sutera Mall → UTM Skudai'), findsOneWidget);
    expect(find.text('Departure: 7/9/2030, 3:45 PM'), findsOneWidget);
    expect(find.text('Reminder: 7/9/2030, 3:35 PM'), findsOneWidget);
    await tester.tap(find.text('View Journey'));
    await tester.pumpAndSettle();
    expect(find.text('Journey Summary'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel Reminder'));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming Journey'), findsNothing);
  });

  for (final transfer in [false, true]) {
    testWidgets(
      '${transfer ? 'transfer' : 'direct'} recommendation reminder state and 2x2 phone actions',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final recommendation = transfer
            ? fixtures.transferRecommendation
            : const DirectJourneyRecommendation(
                tripId: 'direct-trip',
                routeId: 'J15',
                routeShortName:
                    'J15 with an exceptionally long route label for a narrow phone',
                originStopId: 'larkin',
                destinationStopId: 'jb',
                serviceId: 'weekday',
                originStopSequence: 1,
                destinationStopSequence: 5,
                departureSeconds: 57300,
                arrivalSeconds: 59100,
              );
        await tester.pumpWidget(
          MaterialApp(
            home: DepartureRecommendationPage(
              stopRepository: fixtures.FakeDepartureStopRepository(),
              tripRepository: fixtures.FakeDirectTripRepository(
                results: const [fixtures.directResult],
              ),
              transferRepository: fixtures.FakeTransferJourneyRepository(
                results: const [fixtures.transferResult],
              ),
              timetableRepository:
                  fixtures.FakeTimetableRecommendationRepository(
                    results: [recommendation],
                  ),
              recentSearchRepository: fixtures.FakeRecentSearchRepository(),
              realtimeRepository:
                  fixtures.FakeRecommendationRealtimeRepository(),
              initialDateTime: DateTime(2030, 9, 7, 14),
              now: () => now,
              initialJourney: const SavedJourney(
                id: 'saved',
                name: 'Journey',
                origin: DepartureStop(
                  id: 'larkin',
                  name:
                      'Larkin Sentral with an exceptionally long boarding stop name',
                ),
                destination: DepartureStop(
                  id: 'jb',
                  name:
                      'JB Sentral with an exceptionally long destination stop name',
                ),
              ),
              reminderController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('journey-search-button')),
        );
        await tester.tap(find.byKey(const Key('journey-search-button')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Remind Me'));
        expect(find.text('Remind Me'), findsOneWidget);
        final report = tester.getTopLeft(
          find.byKey(Key('report-bus-${recommendation.departureSeconds}')),
        );
        final route = tester.getTopLeft(
          find.byKey(Key('view-route-${recommendation.departureSeconds}')),
        );
        // Narrow cards may stack actions; both must remain reachable.
        expect(route.dy, greaterThanOrEqualTo(report.dy));
        await tester.ensureVisible(find.text('View Route'));
        await tester.pumpAndSettle();
        expect(find.text('View Route').hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.text('Remind Me'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remind Me'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Set Reminder'));
        await tester.tap(find.text('Set Reminder'));
        await tester.pumpAndSettle();
        expect(find.text('Reminder Set'), findsOneWidget);
        await tester.ensureVisible(find.text('Reminder Set'));
        await tester.tap(find.text('Reminder Set'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel Reminder'));
        await tester.pumpAndSettle();
        expect(find.text('Remind Me'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
