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
              dataCheckPageBuilder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Data check page')),
              ),
              departurePageBuilder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Departure Recommendation')),
              ),
              livePageBuilder: (_) =>
                  Scaffold(appBar: AppBar(title: const Text('Module 3'))),
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
          for (final label in [
            'Home',
            'Plan',
            'Live',
            'Data Check',
            'Reports',
          ]) {
            expect(find.text(label).hitTestable(), findsOneWidget);
          }
          expect(find.text('Profile / Reports'), findsNothing);
          expect(
            tester
                .widgetList<Scrollable>(find.byType(Scrollable))
                .every((s) => s.axisDirection == AxisDirection.down),
            isTrue,
          );
          await press(tester, find.text('Data Check'));
          expect(find.text('Data check page'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await press(tester, find.text('Reports'));
          expect(find.text('Report a Transit Issue'), findsOneWidget);
          expect(find.text('My Reports'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
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
          expect(find.text('Departure Recommendation'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await press(tester, find.text('Live'));
          expect(find.text('Module 3'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
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
            expect(find.text('Upcoming Journey'), findsNothing);
            expect(find.textContaining('No upcoming journey.'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
}
