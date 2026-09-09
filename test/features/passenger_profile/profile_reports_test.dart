import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback.dart';
import 'package:government_transit_collector/features/passenger_profile/presentation/passenger_profile_page.dart';
import 'package:government_transit_collector/features/passenger_profile/presentation/my_reports_section.dart';
import 'package:government_transit_collector/features/passenger_home/presentation/passenger_home_page.dart';
import '../bus_feedback/report_form_test.dart' show ReportsFake;
import '../bus_feedback/feedback_repository_test.dart' show report;
import 'travel_profile_test.dart' as existing;

class HomeAuth extends existing.ProfileAuth {
  HomeAuth(super.client);
  int logouts = 0;
  @override
  Future<void> logout() async {
    logouts++;
  }
}

void main() {
  late SupabaseClient client;
  setUp(() {
    client = SupabaseClient(
      'https://example.test',
      'key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDown(() => client.dispose());

  testWidgets(
    'profile icon replaces card beside logout, opens profile, refreshes name; logout still calls auth',
    (tester) async {
      final auth = HomeAuth(client);
      await tester.pumpWidget(
        MaterialApp(
          home: PassengerHomePage(
            profile: existing.profile,
            repository: auth,
            recentSearchRepository: existing.RecentFake(),
            preferencesRepository: existing.PreferencesFake(),
            savedJourneyRepository: existing.SavedFake(),
            feedbackRepository: ReportsFake(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('My Travel Profile'), findsNothing);
      expect(find.text('Plan a Journey'), findsOneWidget);
      expect(find.text("Today's Transit"), findsNothing);
      final actions = tester.widget<AppBar>(find.byType(AppBar)).actions!;
      expect((actions[0] as IconButton).tooltip, 'My Travel Profile');
      expect((actions[1] as IconButton).tooltip, 'Sign out');
      await tester.tap(find.byTooltip('My Travel Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(PassengerProfilePage), findsOneWidget);
      expect(find.byType(MyReportsSection), findsNothing);
      expect(find.text('My Reports'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Updated Rider');
      await tester.ensureVisible(find.text('Update Name'));
      await tester.tap(find.text('Update Name'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining(', Updated Rider'), findsOneWidget);
      await tester.tap(find.byTooltip('Sign out'));
      await tester.pump();
      expect(auth.logouts, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'My Reports displays owned scheduled and historical reports with read-only description details',
    (tester) async {
      final reports = ReportsFake()
        ..rows.addAll([
          report(issue: '["Bus was late","Bus overcrowded"]'),
          report(user: 'other', issue: 'Private report'),
          BusFeedback(
            userId: 'owner',
            routeId: 'old-route',
            stopId: 'old-stop',
            issueType: 'Historical report',
            comment: 'Historical description',
            createdAt: DateTime.utc(2026, 8, 1),
          ),
        ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MyReportsSection(userId: 'owner', repository: reports),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private report'), findsNothing);
      expect(find.textContaining('Service: Mon, Sep 7, 2026'), findsOneWidget);
      expect(find.textContaining('1:28 PM'), findsOneWidget);
      expect(
        find.textContaining('Submitted: Tue, Sep 8, 2026'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Service date/time not recorded'),
        findsOneWidget,
      );
      expect(find.text('Bus was late\nBus overcrowded'), findsOneWidget);
      await tester.tap(find.text('Bus was late\nBus overcrowded'));
      await tester.pumpAndSettle();
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Late bus'), findsOneWidget);
      expect(find.text('Service Date'), findsOneWidget);
      expect(find.text('Scheduled Departure'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.textContaining('Comment'), findsNothing);
      expect(find.text('Reply'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historical report'));
      await tester.pumpAndSettle();
      expect(find.text('Not recorded'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing profile owner immediately removes previous reports', (
    tester,
  ) async {
    final reports = ReportsFake()
      ..rows.addAll([report(), report(user: 'other', issue: 'Other user')]);
    Widget page(String user) => MaterialApp(
      home: Scaffold(
        body: MyReportsSection(userId: user, repository: reports),
      ),
    );
    await tester.pumpWidget(page('owner'));
    await tester.pumpAndSettle();
    expect(find.text('Bus was late'), findsOneWidget);
    await tester.pumpWidget(page('other'));
    await tester.pumpAndSettle();
    expect(find.text('Bus was late'), findsNothing);
    expect(find.text('Other user'), findsOneWidget);
  });

  for (final size in [const Size(360, 640), const Size(800, 400)]) {
    testWidgets(
      'profile swipes to lower sections without keyboard and has no overflow at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: PassengerProfilePage(
              profile: existing.profile,
              authRepository: existing.ProfileAuth(client),
              savedRepository: existing.SavedFake(),
              recentRepository: existing.RecentFake(),
              preferencesRepository: existing.PreferencesFake(),
              feedbackRepository: ReportsFake(),
              onProfileUpdated: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels,
          greaterThan(0),
        );
        await tester.scrollUntilVisible(
          find.text('Recent Searches'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Recent Searches'), findsOneWidget);
        expect(find.text('My Reports'), findsNothing);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Comment'), findsNothing);
      },
    );
  }
}
