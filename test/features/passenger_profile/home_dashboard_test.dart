import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback.dart';
import 'package:government_transit_collector/features/passenger_home/presentation/home_transit_insights.dart';
import 'package:government_transit_collector/features/passenger_home/presentation/passenger_home_page.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import '../authentication/auth_pages_test.dart' show PageAuth;
import '../bus_feedback/report_form_test.dart' show ReportsFake;
import 'travel_profile_test.dart' as f;

class HomeFeedFake implements RealtimeVehicleRepository {
  bool fail = false;
  @override
  Future<RealtimeFeedSnapshot> fetchVehiclePositions() async {
    if (fail) throw StateError('offline');
    return RealtimeFeedSnapshot(
      vehicles: [
        RealtimeVehiclePosition.fromJson({'route_id': 'actual-route'}),
      ],
      feedTimestampSeconds:
          DateTime.utc(2026, 9, 9, 16).millisecondsSinceEpoch ~/ 1000,
    );
  }
}

BusFeedback report(
  DateTime at, {
  String user = 'owner',
  String issue = 'Bus was late',
}) => BusFeedback(
  userId: user,
  routeId: 'r',
  stopId: 's',
  issueType: issue,
  comment: '',
  createdAt: at,
);

void main() {
  final now = DateTime.utc(2026, 9, 9, 17);
  test(
    'Malaysia today excludes previous date, future timestamps and other users',
    () {
      final rows = [
        report(DateTime.utc(2026, 9, 9, 15, 59, 59)),
        report(DateTime.utc(2026, 9, 9, 16)),
        report(now),
        report(now, user: 'other'),
        report(now.add(const Duration(seconds: 1))),
      ];
      expect(homeReportsToday(rows, 'owner', now), [rows[1], rows[2]]);
      expect(homeReportsToday(rows, 'owner', now.toLocal()), [
        rows[1],
        rows[2],
      ]);
      expect(
        homeReportsToday(rows, 'owner', DateTime.utc(2026, 9, 10, 16)),
        isEmpty,
      );
    },
  );

  testWidgets(
    'Home renders repository data, categories and empty reminder through rotation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reports = ReportsFake()
        ..rows.addAll([
          report(now, issue: '["Bus was late","Bus stop issue"]'),
          report(now),
          report(now.subtract(const Duration(days: 1))),
        ]);
      final feed = HomeFeedFake();
      await tester.pumpWidget(
        MaterialApp(
          home: PassengerHomePage(
            profile: f.profile,
            repository: PageAuth(),
            recentSearchRepository: f.RecentFake(),
            preferencesRepository: f.PreferencesFake(),
            savedJourneyRepository: f.SavedFake(),
            feedbackRepository: reports,
            homeRealtimeRepository: feed,
            now: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final size in [const Size(320, 640), const Size(844, 390)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        for (final label in [
          'Plan a Journey',
          "Today's Transit",
          'Community Today',
          'Nothing scheduled yet',
        ]) {
          await tester.scrollUntilVisible(
            find.text(label),
            label == 'Plan a Journey' ? -200 : 150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        expect(find.text('Your reports today: 2'), findsOneWidget);
        expect(find.text('Bus was late: 2'), findsOneWidget);
        expect(find.text('Bus stop issue: 1'), findsOneWidget);
        expect(find.textContaining('2026-09-10 00:00 MYT'), findsOneWidget);
        expect(find.textContaining('Reliability'), findsNothing);
        expect(find.text('Service Insight'), findsNothing);
        expect(find.text('Service Status: Unavailable'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      feed.fail = true;
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.text('Data Status: Data unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'missing data stays unavailable; empty reports are distinct from failure',
    (tester) async {
      for (final reports in <List<BusFeedback>?>[null, []]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: HomeTransitInsights(
                  now: now,
                  userId: 'owner',
                  reports: reports,
                  snapshot: null,
                ),
              ),
            ),
          ),
        );
        expect(find.text('Data Status: Data unavailable'), findsOneWidget);
        expect(find.textContaining('Reliability'), findsNothing);
        expect(find.text('Service Insight'), findsNothing);
        expect(
          find.text(
            reports == null
                ? 'Report data unavailable'
                : 'No reports from you today',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('%'), findsNothing);
      }
    },
  );
}
