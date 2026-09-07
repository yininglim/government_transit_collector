import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback_repository.dart';
import 'package:government_transit_collector/features/bus_feedback/data/feedback_reference_repository.dart';
import 'package:government_transit_collector/features/bus_feedback/data/feedback_schedule_repository.dart';
import 'package:government_transit_collector/features/bus_feedback/presentation/bus_feedback_page.dart';

const stopA = FeedbackStop(id: 'a', name: 'Stop A');
const stopB = FeedbackStop(id: 'b', name: 'Stop B');
const stopC = FeedbackStop(id: 'c', name: 'Other Route Stop');
const contextOption = FeedbackJourneyOption(
  label: 'Direct Bus',
  routeId: 'r1',
  routeLabel: 'J30',
  tripId: 'trip',
  departureSeconds: 48480,
  boardingStop: stopA,
);

class ReportsFake implements BusFeedbackRepository {
  final rows = <BusFeedback>[];
  bool duplicate = false;
  @override
  Future<void> submitFeedback(BusFeedback feedback) async {
    if (duplicate) throw const BusFeedbackException(duplicateFeedbackMessage);
    rows.add(feedback);
  }

  @override
  Future<List<BusFeedback>> getMyFeedback() async => rows;
  @override
  Future<void> updateFeedback(BusFeedback feedback) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteFeedback(String feedbackId) async =>
      throw UnimplementedError();
}

class ReferenceFake implements FeedbackReferenceRepository {
  String? searched;
  @override
  Future<List<FeedbackRoute>> searchRoutes(String query) async {
    searched = query;
    return [
      FeedbackRoute(
        id: query == 'J44' ? 'r2' : 'r1',
        shortName: query == 'J44' ? 'J44' : 'J30',
        longName: 'Route',
      ),
    ];
  }

  @override
  Future<List<FeedbackStop>> searchStops({
    required String routeId,
    required String query,
    String? tripId,
  }) async => throw StateError('Old stop search must not be used');
  @override
  Future<bool> stopBelongsToSelection({
    required String routeId,
    required String stopId,
    String? tripId,
  }) async => true;
}

class ScheduleFake implements FeedbackScheduleRepository {
  final routes = <String>[];
  final calls = <({String route, String stop, DateTime date, String? trip})>[];
  bool failStops = false, failTimes = false, empty = false;
  Completer<List<FeedbackDeparture>>? pending;
  @override
  Future<List<FeedbackStop>> loadRouteStops(
    String routeId, {
    String? tripId,
  }) async {
    routes.add(routeId);
    if (failStops) throw const FeedbackReferenceException('offline');
    return routeId == 'r1' ? [stopA, stopB] : [stopC];
  }

  @override
  Future<List<FeedbackDeparture>> loadDepartures({
    required String routeId,
    required String stopId,
    required DateTime serviceDate,
    String? tripId,
  }) async {
    calls.add((route: routeId, stop: stopId, date: serviceDate, trip: tripId));
    if (pending != null) return pending!.future;
    if (failTimes) throw const FeedbackReferenceException('offline');
    if (empty) return [];
    return [
      const FeedbackDeparture(tripId: 'trip', seconds: 48480),
      const FeedbackDeparture(tripId: 'trip2', seconds: 50280),
    ];
  }
}

Finder stopField() => find.byWidgetPredicate(
  (w) =>
      w is DropdownButtonFormField<String> &&
      w.decoration.labelText == 'Related Bus Stop',
);
Finder timeField() => find.byType(DropdownButtonFormField<int>);
Finder issueField() => find.byKey(const Key('report-issues'));
DropdownButton<T> dropdown<T>(WidgetTester tester, Finder field) =>
    tester.widget<DropdownButton<T>>(
      find.descendant(of: field, matching: find.byType(DropdownButton<T>)),
    );
Future<void> choose(WidgetTester tester, Finder field, String label) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
  if (find.text('Done').evaluate().isNotEmpty) {
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }
}

Future<void> route(WidgetTester tester, String query) async {
  final label =
      find.text('Tap to search and select a route').evaluate().isNotEmpty
      ? find.text('Tap to search and select a route')
      : find.text('J30 - Route');
  await tester.ensureVisible(label);
  await tester.tap(label);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('feedback-route-search')), query);
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
  await tester.tap(find.text('$query - Route'));
  await tester.pumpAndSettle();
}

Future<void> mountReport(
  WidgetTester tester, {
  ScheduleFake? schedule,
  ReportsFake? reports,
  ReferenceFake? reference,
  bool contextual = false,
  Size size = const Size(400, 800),
  DateTime? now,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: BusFeedbackPage(
        repository: reports ?? ReportsFake(),
        referenceRepository: reference ?? ReferenceFake(),
        scheduleRepository: schedule ?? ScheduleFake(),
        currentUserId: () => 'owner',
        now: () => now ?? DateTime.utc(2026, 9, 7, 8),
        journeyOptions: contextual ? [contextOption] : [],
        travelDate: contextual ? DateTime(2026, 9, 7) : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no selected issues blocks submission', (tester) async {
    final reports = ReportsFake();
    await mountReport(tester, reports: reports, contextual: true);
    await tester.ensureVisible(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'Valid description');
    await tester.ensureVisible(find.text('Submit Report'));
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(find.text('Please select a problem type.'), findsOneWidget);
    expect(reports.rows, isEmpty);
  });

  testWidgets(
    'phone selector scrolls with keyboard inset and preserves applied selections',
    (tester) async {
      await mountReport(tester, contextual: true, size: const Size(360, 640));
      await tester.ensureVisible(find.byType(TextFormField));
      await tester.tap(find.byType(TextFormField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await choose(tester, issueField(), 'Other');
      expect(find.text('Other'), findsOneWidget);
      await tester.ensureVisible(issueField());
      await tester.tap(issueField());
      await tester.pumpAndSettle();
      final other = find.widgetWithText(CheckboxListTile, 'Other');
      expect(tester.widget<CheckboxListTile>(other).value, isTrue);
      await tester.ensureVisible(other);
      await tester.tap(other);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'route stays searchable; stop and schedule disabled until prerequisites; only selected route stops appear',
    (tester) async {
      final schedule = ScheduleFake();
      final reference = ReferenceFake();
      await mountReport(tester, schedule: schedule, reference: reference);
      expect(
        tester.widget<DropdownButtonFormField<String>>(stopField()).onChanged,
        isNull,
      );
      expect(
        tester.widget<DropdownButtonFormField<int>>(timeField()).onChanged,
        isNull,
      );
      expect(find.byKey(const Key('report-service-date')), findsOneWidget);
      await route(tester, 'J30');
      expect(reference.searched, 'J30');
      expect(schedule.routes, ['r1']);
      final stops = dropdown<String>(tester, stopField()).items!;
      expect(stops.map((s) => s.value), ['a', 'b']);
      expect(find.text('Other Route Stop (c)'), findsNothing);
      await choose(tester, stopField(), 'Stop A (a)');
      expect(schedule.calls.last.route, 'r1');
      expect(schedule.calls.last.stop, 'a');
      expect(schedule.calls.last.date, DateTime(2026, 9, 7));
      expect(dropdown<int>(tester, timeField()).items!.map((i) => i.value), [
        48480,
        50280,
      ]);
    },
  );

  testWidgets(
    'changing stop and route clears selected scheduled time and route clears stop',
    (tester) async {
      await mountReport(tester);
      await route(tester, 'J30');
      await choose(tester, stopField(), 'Stop A (a)');
      await choose(tester, timeField(), '1:28 PM');
      await choose(tester, stopField(), 'Stop B (b)');
      expect(
        tester.widget<DropdownButtonFormField<int>>(timeField()).initialValue,
        isNull,
      );
      await choose(tester, timeField(), '1:58 PM');
      await route(tester, 'J44');
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(stopField())
            .initialValue,
        isNull,
      );
      expect(
        tester.widget<DropdownButtonFormField<int>>(timeField()).initialValue,
        isNull,
      );
      expect(dropdown<String>(tester, stopField()).items!.single.value, 'c');
    },
  );

  testWidgets(
    'date picker change clears time and reloads selected route and stop',
    (tester) async {
      final schedule = ScheduleFake();
      await mountReport(tester, schedule: schedule);
      await route(tester, 'J30');
      await choose(tester, stopField(), 'Stop A (a)');
      await choose(tester, timeField(), '1:28 PM');
      await tester.ensureVisible(find.byKey(const Key('report-service-date')));
      await tester.tap(find.byKey(const Key('report-service-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(schedule.calls.last.date, DateTime(2026, 9, 8));
      expect(
        tester.widget<DropdownButtonFormField<int>>(timeField()).initialValue,
        isNull,
      );
    },
  );

  testWidgets('no services and recoverable schedule failure remain distinct', (
    tester,
  ) async {
    final schedule = ScheduleFake()..empty = true;
    await mountReport(tester, schedule: schedule);
    await route(tester, 'J30');
    await choose(tester, stopField(), 'Stop A (a)');
    expect(
      find.text(
        'No scheduled departures found for this stop on the selected date.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Submit Report'),
          )
          .onPressed,
      isNull,
    );
    schedule.empty = false;
    schedule.failTimes = true;
    await choose(tester, stopField(), 'Stop B (b)');
    expect(find.text('Retry scheduled departures'), findsOneWidget);
    expect(
      find.text(
        'No scheduled departures found for this stop on the selected date.',
      ),
      findsNothing,
    );
    schedule.failTimes = false;
    await tester.ensureVisible(find.text('Retry scheduled departures'));
    await tester.tap(find.text('Retry scheduled departures'));
    await tester.pumpAndSettle();
    expect(dropdown<int>(tester, timeField()).items, hasLength(2));
  });

  testWidgets(
    'stop loading failure is recoverable and route search remains usable',
    (tester) async {
      final schedule = ScheduleFake()..failStops = true;
      await mountReport(tester, schedule: schedule);
      await route(tester, 'J30');
      expect(find.text('Retry related stops'), findsOneWidget);
      schedule.failStops = false;
      await route(tester, 'J44');
      expect(dropdown<String>(tester, stopField()).items!.single.value, 'c');
    },
  );

  testWidgets('late timetable response cannot restore old route choices', (
    tester,
  ) async {
    final schedule = ScheduleFake();
    await mountReport(tester, schedule: schedule);
    await route(tester, 'J30');
    schedule.pending = Completer<List<FeedbackDeparture>>();
    final field = tester.widget<DropdownButtonFormField<String>>(stopField());
    field.onChanged!('a');
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // Change the route while its stop's request is still pending.
    final pending = schedule.pending!;
    schedule.pending = null;
    // Complete after navigating to the route picker, which does not wait for it.
    await tester.ensureVisible(find.text('J30 - Route'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('J30 - Route'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('feedback-route-search')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('feedback-route-search')),
      'J44',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.text('J44 - Route'));
    await tester.pumpAndSettle();
    pending.complete([const FeedbackDeparture(tripId: 'old', seconds: 1)]);
    await tester.pumpAndSettle();
    expect(dropdown<int>(tester, timeField()).items, isEmpty);
  });

  for (final contextual in [false, true]) {
    testWidgets(
      '${contextual ? 'contextual' : 'generic'} submission preserves schedule, selected issues and description',
      (tester) async {
        final reports = ReportsFake();
        final schedule = ScheduleFake();
        await mountReport(
          tester,
          reports: reports,
          schedule: schedule,
          contextual: contextual,
        );
        if (!contextual) {
          await route(tester, 'J30');
          await choose(tester, stopField(), 'Stop A (a)');
          await choose(tester, timeField(), '1:28 PM');
        } else {
          expect(find.byKey(const Key('report-service-date')), findsNothing);
          expect(timeField(), findsNothing);
          expect(find.text('J30'), findsOneWidget);
          expect(
            find.textContaining('Scheduled departure: 1:28 PM'),
            findsNWidgets(2),
          );
        }
        await choose(tester, issueField(), 'Bus overcrowded');
        await choose(tester, issueField(), 'Bus was late');
        expect(find.text('Bus overcrowded'), findsOneWidget);
        expect(find.text('Bus was late'), findsOneWidget);
        final description = find.byType(TextFormField);
        await tester.ensureVisible(description);
        await tester.enterText(description, 'The bus was overcrowded.');
        await tester.ensureVisible(find.text('Submit Report'));
        await tester.tap(find.text('Submit Report'));
        await tester.pumpAndSettle();
        expect(reports.rows, hasLength(1));
        final row = reports.rows.single;
        expect(row.userId, 'owner');
        expect(row.routeId, 'r1');
        expect(row.stopId, 'a');
        expect(row.tripId, 'trip');
        expect(row.serviceDate, DateTime(2026, 9, 7));
        expect(row.scheduledDepartureSeconds, 48480);
        expect(row.description, 'The bus was overcrowded.');
        expect(row.issueTypes, ['Bus overcrowded', 'Bus was late']);
        expect(schedule.calls.last.trip, 'trip');
      },
    );
  }

  testWidgets(
    'contextual duplicate shows friendly message without discarding description',
    (tester) async {
      final reports = ReportsFake()..duplicate = true;
      await mountReport(tester, reports: reports, contextual: true);
      await choose(tester, issueField(), 'Other');
      await tester.ensureVisible(find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), 'Report details');
      await tester.ensureVisible(find.text('Submit Report'));
      await tester.tap(find.text('Submit Report'));
      await tester.pumpAndSettle();
      expect(find.text(duplicateFeedbackMessage), findsOneWidget);
      expect(find.text('Report details'), findsOneWidget);
      expect(reports.rows, isEmpty);
    },
  );

  testWidgets(
    'description retains minimum validation and 500 character limit',
    (tester) async {
      final reports = ReportsFake();
      await mountReport(tester, reports: reports, contextual: true);
      await choose(tester, issueField(), 'Other');
      final field = find.byType(TextFormField);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'bad');
      await tester.ensureVisible(find.text('Submit Report'));
      await tester.tap(find.text('Submit Report'));
      await tester.pumpAndSettle();
      expect(find.text('Please provide more detail.'), findsOneWidget);
      expect(reports.rows, isEmpty);
      final input = tester.widget<TextField>(
        find.descendant(of: field, matching: find.byType(TextField)),
      );
      expect(input.maxLength, 500);
      expect(find.text('Describe the Problem'), findsOneWidget);
    },
  );

  testWidgets('contextual stale schedule is rejected without inserting', (
    tester,
  ) async {
    final reports = ReportsFake();
    final schedule = ScheduleFake()..empty = true;
    await mountReport(
      tester,
      reports: reports,
      schedule: schedule,
      contextual: true,
    );
    await choose(tester, issueField(), 'Other');
    await tester.ensureVisible(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'Valid description');
    await tester.ensureVisible(find.text('Submit Report'));
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This scheduled departure is no longer available. Please select it again.',
      ),
      findsOneWidget,
    );
    expect(reports.rows, isEmpty);
  });

  for (final minute in [27, 28, 38]) {
    testWidgets(
      'late/missing categories respect service timezone at 13:$minute',
      (tester) async {
        await mountReport(
          tester,
          contextual: true,
          now: DateTime.utc(2026, 9, 7, 5, minute),
        );
        await tester.ensureVisible(issueField());
        await tester.tap(issueField());
        await tester.pumpAndSettle();
        final issues = tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .map((item) => (item.title! as Text).data);
        expect(issues.contains('Bus was late'), minute >= 28);
        expect(issues.contains('Bus did not arrive'), minute >= 38);
        expect(
          issues,
          containsAll([
            'Bus overcrowded',
            'Missing bus stop',
            'Long walking distance',
            'Incorrect route information',
            'Other',
          ]),
        );
      },
    );
  }

  for (final size in [const Size(360, 640), const Size(800, 400)]) {
    testWidgets(
      'report swipe scroll works without keyboard and with keyboard at $size',
      (tester) async {
        await mountReport(tester, contextual: true, size: size);
        final scroll = find.byType(SingleChildScrollView);
        final before = tester
            .getTopLeft(find.text('Report a Transit Problem'))
            .dy;
        await tester.drag(scroll, const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Report a Transit Problem')).dy,
          lessThan(before),
        );
        await tester.ensureVisible(find.byType(TextFormField));
        await tester.tap(find.byType(TextFormField));
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 200);
        await tester.pump();
        await tester.drag(scroll, const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Submit Report'));
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
      },
    );
  }
}
