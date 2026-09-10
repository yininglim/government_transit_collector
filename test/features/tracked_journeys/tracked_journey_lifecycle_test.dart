import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/tracked_journeys/tracked_journey.dart';
import 'package:government_transit_collector/features/tracked_journeys/tracked_journey_repository.dart';
import 'package:government_transit_collector/features/tracked_journeys/tracked_journey_widgets.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/saved_journey_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_recommendation_page.dart';
import 'package:government_transit_collector/features/passenger_home/presentation/passenger_home_page.dart';
import 'package:government_transit_collector/features/passenger_profile/presentation/passenger_profile_page.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import '../departure_recommendation/departure_recommendation_test.dart' as f;
import '../departure_recommendation/planning_actions_test.dart'
    show press, fieldText;
import '../departure_recommendation/personalized_departure_test.dart'
    show RecordingDirect;
import '../passenger_profile/travel_profile_test.dart' as p;
import '../authentication/auth_pages_test.dart' show PageAuth;

TrackedJourneySnapshot snapshot({bool transfer = false}) =>
    TrackedJourneySnapshot(
      recommendation: transfer
          ? f.transferRecommendation
          : f.directRecommendation,
      originName: f.larkin.name,
      destinationName: f.jbSentral.name,
      serviceDate: DateTime(2026, 9, 10),
    );
TrackedJourney row({
  String id = 'trip',
  String user = 'owner',
  String status = 'active',
  bool transfer = false,
}) => TrackedJourney(
  id: id,
  userId: user,
  status: status,
  snapshot: snapshot(transfer: transfer),
  startedAt: DateTime.utc(2026, 9, 10, 7),
  completedAt: status == 'completed' ? DateTime.utc(2026, 9, 10, 9) : null,
);

class MemoryJourneys extends TrackedJourneyRepository {
  @override
  String get userId => 'owner';
  final rows = <TrackedJourney>[];
  int starts = 0, finishes = 0;
  bool failStart = false;
  @override
  Future<TrackedJourney?> active() async =>
      rows.where((r) => r.userId == userId && r.status == 'active').firstOrNull;
  // Deliberately return mixed rows to verify the UI's ownership/status boundary too.
  @override
  Future<List<TrackedJourney>> completed() async => List.of(rows);
  @override
  Future<void> start(
    TrackedJourneySnapshot journey, {
    String? replaceId,
  }) async {
    if (failStart) throw StateError('offline');
    starts++;
    if (replaceId != null) await finish(replaceId, completed: false);
    rows.add(
      TrackedJourney(
        id: 'started-$starts',
        userId: userId,
        snapshot: journey,
        status: 'active',
        startedAt: DateTime.utc(2026, 9, 10, 7),
      ),
    );
    notifyListeners();
  }

  @override
  Future<void> finish(String id, {required bool completed}) async {
    finishes++;
    final index = rows.indexWhere(
      (r) => r.id == id && r.userId == userId && r.status == 'active',
    );
    final current = rows[index];
    rows[index] = TrackedJourney(
      id: id,
      userId: userId,
      snapshot: current.snapshot,
      status: completed ? 'completed' : 'cancelled',
      startedAt: current.startedAt,
      completedAt: completed ? DateTime.utc(2026, 9, 10, 9) : null,
    );
    notifyListeners();
  }
}

Widget sections(MemoryJourneys repository, DateTime Function() now) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              ActiveJourneySection(repository: repository, now: now),
              MyTripsSection(repository: repository, onPlanAgain: (_) {}),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'starting a different journey asks before cancelling the current journey',
    (tester) async {
      final repository = MemoryJourneys()..rows.add(row(transfer: true));
      bool? started;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  started = await startPassengerJourney(
                    context,
                    repository,
                    snapshot(),
                  );
                },
                child: const Text('Start'),
              ),
            ),
          ),
        ),
      );
      await press(tester, find.text('Start'));
      expect(repository.starts, 0);
      await press(tester, find.text('Keep Current Journey'));
      expect(started, false);
      expect(repository.rows.single.status, 'active');
      await press(tester, find.text('Start'));
      await press(tester, find.text('Start New Journey'));
      expect(started, true);
      expect(repository.rows.first.status, 'cancelled');
      expect(repository.rows.where((r) => r.status == 'active'), hasLength(1));
    },
  );

  test(
    'direct and transfer snapshots reconstruct every real recommendation field',
    () {
      for (final transfer in [false, true]) {
        final original = snapshot(transfer: transfer);
        final restored = TrackedJourneySnapshot.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
        );
        expect(restored.toJson(), original.toJson());
        expect(restored.tracking.legs.length, transfer ? 2 : 1);
        expect(restored.routeLabel, transfer ? 'J15 → J10' : 'J15');
        expect(restored.tracking.legs.last.toStopId, 'jb');
        expect(restored.at(25 * 3600), DateTime.utc(2026, 9, 10, 17));
      }
    },
  );

  testWidgets(
    'only Track Journey starts history and opens the existing tracker context',
    (tester) async {
      final repository = MemoryJourneys();
      SelectedJourneyTracking? selected;
      final saved = p.SavedFake();
      await tester.pumpWidget(
        MaterialApp(
          home: DepartureRecommendationPage(
            stopRepository: f.FakeDepartureStopRepository(),
            tripRepository: f.FakeDirectTripRepository(
              results: [f.directResult],
            ),
            transferRepository: f.FakeTransferJourneyRepository(),
            timetableRepository: f.FakeTimetableRecommendationRepository(
              results: [f.directRecommendation],
            ),
            recentSearchRepository: f.FakeRecentSearchRepository(),
            savedJourneyRepository: saved,
            realtimeRepository: f.FakeRecommendationRealtimeRepository(),
            trackedJourneyRepository: repository,
            initialJourney: const SavedJourney(
              id: 'pair',
              name: 'Pair',
              origin: f.larkin,
              destination: f.jbSentral,
            ),
            initialDateTime: DateTime(2026, 9, 10, 15),
            now: () => DateTime.utc(2026, 9, 10, 6),
            selectedJourneyTrackerBuilder: (journey, _) {
              selected = journey;
              return const Scaffold(body: Text('Existing tracker'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.starts, 0);
      await press(tester, find.byKey(const Key('journey-search-button')));
      expect(repository.starts, 0);
      await press(
        tester,
        find.byKey(
          Key('track-journey-${f.directRecommendation.departureSeconds}'),
        ),
      );
      expect(repository.starts, 1);
      expect(find.text('Existing tracker'), findsOneWidget);
      expect(selected!.recommendation, same(f.directRecommendation));
      expect(repository.rows.single.snapshot.toJson(), snapshot().toJson());
    },
  );

  testWidgets(
    'Home shows active above Upcoming and Continue Tracking restores both legs through rotation',
    (tester) async {
      final repository = MemoryJourneys()..rows.add(row(transfer: true));
      SelectedJourneyTracking? selected;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: PassengerHomePage(
            profile: p.profile,
            repository: PageAuth(),
            savedJourneyRepository: p.SavedFake(),
            recentSearchRepository: p.RecentFake(),
            preferencesRepository: p.PreferencesFake(),
            trackedJourneyRepository: repository,
            now: () => DateTime.utc(2026, 9, 10, 7),
            activeJourneyTrackerBuilder: (journey) {
              selected = journey;
              return const Scaffold(body: Text('Continued tracker'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final size in [const Size(390, 844), const Size(844, 390)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('active-journey')));
        expect(find.text('YOUR ACTIVE JOURNEY'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Upcoming Journey'),
          150,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          tester.getTopLeft(find.text('YOUR ACTIVE JOURNEY')).dy,
          lessThan(tester.getTopLeft(find.text('Upcoming Journey')).dy),
        );
        expect(tester.takeException(), isNull);
      }
      await press(tester, find.text('Continue Tracking'));
      expect(find.text('Continued tracker'), findsOneWidget);
      expect(selected!.legs.map((l) => l.tripId), [
        'first-trip',
        'second-trip',
      ]);
      expect(repository.starts, 0);
    },
  );

  testWidgets(
    'arrival boundary prompts, Not Yet stays active, Completed moves to My Trips',
    (tester) async {
      final repository = MemoryJourneys()..rows.add(row());
      var now = DateTime.utc(2026, 9, 10, 8, 24, 59);
      await tester.pumpWidget(sections(repository, () => now));
      await tester.pumpAndSettle();
      expect(find.text('Have you completed this journey?'), findsNothing);
      now = DateTime.utc(2026, 9, 10, 8, 25);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Have you completed this journey?'), findsOneWidget);
      expect(repository.rows.single.status, 'active');
      await press(tester, find.text('Not Yet'));
      expect(repository.finishes, 0);
      expect(find.text('Continue Tracking'), findsOneWidget);
      await press(tester, find.widgetWithText(FilledButton, 'Completed'));
      expect(repository.rows.single.status, 'completed');
      expect(repository.rows.single.completedAt, isNotNull);
      expect(find.byKey(const Key('active-journey')), findsNothing);
      expect(find.byKey(const ValueKey('completed-trip-trip')), findsOneWidget);
    },
  );

  testWidgets(
    'Cancel Tracking requires confirmation and never appears in My Trips',
    (tester) async {
      final repository = MemoryJourneys()..rows.add(row());
      await tester.pumpWidget(
        sections(repository, () => DateTime.utc(2026, 9, 10, 7)),
      );
      await tester.pumpAndSettle();
      await press(tester, find.text('Cancel Tracking'));
      expect(repository.finishes, 0);
      await press(tester, find.text('Keep Tracking'));
      expect(repository.rows.single.status, 'active');
      await press(tester, find.text('Cancel Tracking'));
      await press(tester, find.widgetWithText(FilledButton, 'Cancel Tracking'));
      expect(repository.rows.single.status, 'cancelled');
      expect(repository.rows.single.completedAt, isNull);
      expect(find.byKey(const Key('active-journey')), findsNothing);
      expect(find.byKey(const ValueKey('completed-trip-trip')), findsNothing);
    },
  );

  testWidgets(
    'Profile My Trips shows only current user completed trips and Plan Again prefills without searching',
    (tester) async {
      final repository = MemoryJourneys()
        ..rows.addAll([
          row(id: 'mine', status: 'completed'),
          row(id: 'active'),
          row(id: 'cancelled', status: 'cancelled'),
          row(id: 'other', user: 'other', status: 'completed'),
        ]);
      RecentJourneySearch? plan;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  plan = await Navigator.of(context).push<RecentJourneySearch>(
                    MaterialPageRoute(
                      builder: (_) => PassengerProfilePage(
                        profile: p.profile,
                        authRepository: PageAuth(),
                        savedRepository: p.SavedFake(),
                        recentRepository: p.RecentFake(),
                        preferencesRepository: p.PreferencesFake(),
                        trackedJourneyRepository: repository,
                        onProfileUpdated: (_) {},
                      ),
                    ),
                  );
                },
                child: const Text('Profile'),
              ),
            ),
          ),
        ),
      );
      await press(tester, find.text('Profile'));
      await tester.scrollUntilVisible(
        find.text('My Trips'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('completed-trip-mine')), findsOneWidget);
      for (final id in ['active', 'cancelled', 'other']) {
        expect(find.byKey(ValueKey('completed-trip-$id')), findsNothing);
      }
      await press(tester, find.text('Plan Again'));
      expect(plan!.originStopId, 'larkin');
      final direct = RecordingDirect();
      await tester.pumpWidget(
        MaterialApp(
          home: DepartureRecommendationPage(
            stopRepository: f.FakeDepartureStopRepository(),
            tripRepository: direct,
            transferRepository: f.FakeTransferJourneyRepository(),
            timetableRepository: f.FakeTimetableRecommendationRepository(),
            recentSearchRepository: f.FakeRecentSearchRepository(),
            initialRecentSearch: plan,
            now: () => DateTime.utc(2026, 9, 11, 2),
            trackedJourneyRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fieldText('origin-field', f.larkin.name), findsOneWidget);
      expect(fieldText('destination-field', f.jbSentral.name), findsOneWidget);
      expect(direct.origin, isNull);
      expect(repository.starts, 0);
    },
  );
}
