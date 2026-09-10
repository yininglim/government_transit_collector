import '../tracked_journeys/tracked_journey_lifecycle_test.dart'
    show MemoryJourneys;
import '../departure_recommendation/departure_recommendation_test.dart' as plan;
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_recommendation_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/saved_journey_repository.dart';
import '../bus_feedback/report_form_test.dart' show ReportsFake;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/passenger_home/presentation/passenger_home_page.dart';
import 'package:government_transit_collector/features/journey_reminders/reminder_controller.dart';
import '../authentication/auth_pages_test.dart' show PageAuth;
import '../journey_reminders/journey_reminders_test.dart' as reminders;
import '../departure_recommendation/planning_actions_test.dart' show press;
import 'travel_profile_test.dart' as profile;

void main() {
  test('Malaysia greeting boundaries use UTC+8', () {
    for (final entry in {
      4: 'Good Evening',
      5: 'Good Morning',
      11: 'Good Morning',
      12: 'Good Afternoon',
      17: 'Good Afternoon',
      18: 'Good Evening',
      23: 'Good Evening',
      0: 'Good Evening',
    }.entries) {
      final instant = DateTime.utc(2026, 9, 10, entry.key - 8, 59);
      expect(malaysiaGreeting(instant), entry.value);
      expect(malaysiaGreeting(instant.toLocal()), entry.value);
    }
  });

  Future<void> revealHeader(WidgetTester tester) async {
    final home = find.byKey(const Key('passenger-nav-Home'));
    if (home.hitTestable().evaluate().isEmpty &&
        find.byType(Scrollable).evaluate().isNotEmpty) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 250));
      await tester.pumpAndSettle();
    }
    expect(find.byIcon(Icons.menu), findsNothing);
  }

  Future<void> pressNav(WidgetTester tester, String label) async {
    await revealHeader(tester);
    await press(tester, find.byKey(Key('passenger-nav-$label')));
  }

  Future<void> expectSelected(WidgetTester tester, String label) async {
    await revealHeader(tester);
    final target = find.byKey(Key('passenger-nav-$label'));
    expect(
      tester
          .widgetList<Semantics>(
            find.ancestor(of: target, matching: find.byType(Semantics)),
          )
          .any((s) => s.properties.selected == true),
      isTrue,
    );
    expect(
      tester.widget<TextButton>(target).style!.backgroundColor!.resolve({}),
      isNotNull,
    );
  }

  Widget scrollPage(String title) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      children: [
        for (var i = 0; i < 30; i++)
          SizedBox(height: 60, child: Text('Row $i')),
      ],
    ),
  );

  Future<void> checkCollapse(WidgetTester tester) async {
    await revealHeader(tester);
    final header = find.byKey(const Key('passenger-scrolling-header'));
    final before = tester.getSize(find.byType(Scrollable).first).height;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getSize(header).height, 0);
    expect(
      find.byKey(const Key('passenger-nav-Home')).hitTestable(),
      findsNothing,
    );
    expect(
      tester.getSize(find.byType(Scrollable).first).height,
      greaterThan(before),
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('passenger-nav-Home')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }

  testWidgets('Plan survives shared tabs and clears only after confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final saved = profile.SavedFake();
    final tracked = MemoryJourneys();
    await tester.pumpWidget(
      MaterialApp(
        home: PassengerHomePage(
          profile: profile.profile,
          repository: PageAuth(),
          recentSearchRepository: profile.RecentFake(),
          preferencesRepository: profile.PreferencesFake(),
          savedJourneyRepository: saved,
          trackedJourneyRepository: tracked,
          feedbackRepository: ReportsFake(),
          departurePageBuilder: (_) => DepartureRecommendationPage(
            showPageHeader: false,
            stopRepository: plan.FakeDepartureStopRepository(),
            tripRepository: plan.FakeDirectTripRepository(
              results: [plan.directResult],
            ),
            transferRepository: plan.FakeTransferJourneyRepository(),
            timetableRepository: plan.FakeTimetableRecommendationRepository(
              results: [plan.directRecommendation],
            ),
            recentSearchRepository: plan.FakeRecentSearchRepository(),
            savedJourneyRepository: saved,
            realtimeRepository: plan.FakeRecommendationRealtimeRepository(),
            initialJourney: const SavedJourney(
              id: 'pair',
              name: 'Pair',
              origin: plan.larkin,
              destination: plan.jbSentral,
            ),
            initialDateTime: DateTime(2026, 9, 10, 15),
            now: () => DateTime.utc(2026, 9, 10, 7),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pressNav(tester, 'Plan');
    expect(find.byKey(const Key('clear-journey-plan')), findsNothing);
    await press(tester, find.byKey(const Key('journey-search-button')));
    final state = tester.state(find.byType(DepartureRecommendationPage));
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.byKey(const Key('departure-page-scroll')),
        )
        .controller!;
    final offset = scroll.offset;
    for (final tab in ['Reports', 'My Trips', 'Home', 'Plan']) {
      await pressNav(tester, tab);
      await expectSelected(tester, tab);
    }
    expect(tester.state(find.byType(DepartureRecommendationPage)), same(state));
    expect(scroll.offset, offset);
    expect(find.byKey(const Key('journey-results')), findsOneWidget);
    for (final size in [const Size(320, 640), const Size(844, 390)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await expectSelected(tester, 'Plan');
      expect(tester.takeException(), isNull);
    }
    final childContext = tester.element(
      find.byType(DepartureRecommendationPage),
    );
    Navigator.of(childContext).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Plan child')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await expectSelected(tester, 'Plan');
    expect(tester.state(find.byType(DepartureRecommendationPage)), same(state));
    await press(tester, find.byKey(const Key('clear-journey-plan')));
    await press(tester, find.text('Cancel'));
    expect(find.byKey(const Key('journey-results')), findsOneWidget);
    await press(tester, find.byKey(const Key('clear-journey-plan')));
    await press(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Clear'),
      ),
    );
    expect(find.byKey(const Key('journey-results')), findsNothing);
    expect(find.byKey(const Key('clear-journey-plan')), findsNothing);
    expect(scroll.offset, 0);
    expect(tracked.starts, 0);
    expect(tracked.finishes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final upcoming in [false, true]) {
    testWidgets(
      'Home rotation preserves navigation and ${upcoming ? 'upcoming journey' : 'empty state'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = reminders.MemoryReminders();
        final controller = ReminderController(
          repository,
          reminders.FakeNotifications(),
          now: () => reminders.now,
        );
        if (upcoming) {
          await repository.create(reminders.journey(), 10, reminders.now);
        }
        await tester.pumpWidget(
          MaterialApp(
            home: PassengerHomePage(
              profile: profile.profile,
              repository: PageAuth(),
              recentSearchRepository: profile.RecentFake(),
              preferencesRepository: profile.PreferencesFake(),
              savedJourneyRepository: profile.SavedFake(),
              reminderController: controller,
              feedbackRepository: ReportsFake(),
              departurePageBuilder: (_) =>
                  scrollPage('Departure Recommendation'),
              livePageBuilder: (_) => scrollPage('Module 3'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final size in [
          const Size(320, 640),
          const Size(844, 390),
          const Size(390, 844),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(find.byType(AppBar), findsOneWidget);
          await revealHeader(tester);
          for (final label in ['Home', 'Plan', 'Live', 'Reports', 'My Trips']) {
            expect(
              find.byKey(Key('passenger-nav-$label')).hitTestable(),
              findsOneWidget,
            );
          }
          expect(
            find.byKey(const Key('passenger-nav-Data Check')),
            findsNothing,
          );
          expect(find.text('Profile / Reports'), findsNothing);
          expect(
            tester
                .widgetList<Scrollable>(find.byType(Scrollable))
                .every((s) => s.axisDirection == AxisDirection.down),
            isTrue,
          );
          await checkCollapse(tester);
          await pressNav(tester, 'Reports');
          await expectSelected(tester, 'Reports');
          expect(find.text('Report a Transit Issue'), findsOneWidget);
          await checkCollapse(tester);
          await tester.scrollUntilVisible(
            find.text('My Reports'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text('My Reports'), findsOneWidget);
          final reportsContext = tester.element(find.text('My Reports'));
          Navigator.of(reportsContext).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  Scaffold(appBar: AppBar(title: const Text('Report child'))),
            ),
          );
          await tester.pumpAndSettle();
          await expectSelected(tester, 'Reports');
          Navigator.of(reportsContext).pop();
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('My Reports'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text('My Reports'), findsOneWidget);
          await expectSelected(tester, 'Reports');
          expect(find.byKey(Key('passenger-nav-Home')), findsOneWidget);
          expect(
            tester
                .widgetList<Scaffold>(find.byType(Scaffold))
                .every((s) => s.bottomNavigationBar == null),
            isTrue,
          );

          await pressNav(tester, 'Home');
          await tester.scrollUntilVisible(
            find.text('Plan a Journey'),
            -150,
            scrollable: find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await press(tester, find.text('Plan a Journey'));
          await expectSelected(tester, 'Plan');
          expect(find.text('Departure Recommendation'), findsOneWidget);
          await checkCollapse(tester);
          await pressNav(tester, 'Home');
          await pressNav(tester, 'Live');
          await expectSelected(tester, 'Live');
          expect(find.text('Module 3'), findsOneWidget);
          await checkCollapse(tester);
          await pressNav(tester, 'Home');
          await expectSelected(tester, 'Home');
          if (upcoming) {
            await tester.scrollUntilVisible(
              find.text('View Journey'),
              150,
              scrollable: find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await press(tester, find.text('View Journey'));
            expect(find.text('Journey Summary'), findsOneWidget);
            expect(find.textContaining('Hab Sutera Mall'), findsOneWidget);
            await tester.pageBack();
            await tester.pumpAndSettle();
          } else {
            await tester.scrollUntilVisible(
              find.text('Nothing scheduled yet'),
              150,
              scrollable: find.byType(Scrollable).first,
            );
            expect(find.text('Upcoming Journey'), findsOneWidget);
            expect(find.text('Nothing scheduled yet'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
}
