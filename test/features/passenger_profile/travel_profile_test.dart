import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/saved_journey_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_search_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/passenger_profile/data/travel_preferences_repository.dart';
import 'package:government_transit_collector/features/passenger_profile/presentation/passenger_profile_page.dart';

const profile = AppProfile(
  userId: 'owner',
  fullName: 'Rider',
  role: 'passenger',
  email: 'rider@example.test',
);
const journey = SavedJourney(
  id: 'saved',
  name: 'College',
  origin: DepartureStop(id: 'a', name: 'Stop A'),
  destination: DepartureStop(id: 'b', name: 'Stop B'),
);

class ProfileAuth extends AuthRepository {
  ProfileAuth(SupabaseClient superClient) : super(client: superClient);
  @override
  Future<AppProfile> updateFullName(String name) async => AppProfile(
    userId: 'owner',
    fullName: name.trim(),
    role: 'passenger',
    email: profile.email,
  );
}

class SavedFake implements SavedJourneyRepository {
  final rows = <SavedJourney>[journey];
  @override
  Future<List<SavedJourney>> load() async => List.of(rows);
  @override
  Future<void> delete(String id) async => rows.removeWhere((r) => r.id == id);
  @override
  Future<void> save(
    String name,
    DepartureStop origin,
    DepartureStop destination,
  ) async {}
}

class PreferencesFake implements TravelPreferencesRepository {
  int radius = 1000;
  @override
  Future<int> loadRadius() async => radius;
  @override
  Future<void> saveRadius(int value) async {
    radius = value;
  }
}

class RecentFake implements RecentSearchRepository {
  final rows = <RecentJourneySearch>[
    RecentJourneySearch(
      originStopId: 'a',
      originStopName: 'Recent A',
      destinationStopId: 'b',
      destinationStopName: 'Recent B',
      searchedAt: DateTime.utc(2026),
    ),
  ];
  @override
  Future<List<RecentJourneySearch>> getRecentSearches() async => List.of(rows);
  @override
  Future<void> clearRecentSearches() async => rows.clear();
  @override
  Future<void> saveRecentSearch(RecentJourneySearch search) async =>
      rows.add(search);
}

void main() {
  setUpAll(sqfliteFfiInit);
  late SupabaseClient client;
  setUp(() {
    client = SupabaseClient(
      'https://example.test',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDown(() => client.dispose());
  test(
    'radius persists locally per account and validates supported options',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'travel_preferences_test',
      );
      final dbPath = '${dir.path}/preferences.db';
      final first = SqliteTravelPreferencesRepository(
        userId: 'a',
        factory: databaseFactoryFfi,
        databasePath: dbPath,
      );
      final second = SqliteTravelPreferencesRepository(
        userId: 'b',
        factory: databaseFactoryFfi,
        databasePath: dbPath,
      );
      expect(await first.loadRadius(), 1000);
      await first.saveRadius(500);
      expect(
        await SqliteTravelPreferencesRepository(
          userId: 'a',
          factory: databaseFactoryFfi,
          databasePath: dbPath,
        ).loadRadius(),
        500,
      );
      expect(await second.loadRadius(), 1000);
      await expectLater(first.saveRadius(42), throwsArgumentError);
      await databaseFactoryFfi.deleteDatabase(dbPath);
      await dir.delete();
    },
  );
  testWidgets(
    'profile name, read-only email, radius, saved journeys, recent clear',
    (tester) async {
      final prefs = PreferencesFake();
      final saved = SavedFake();
      final recent = RecentFake();
      AppProfile? updated;
      await tester.pumpWidget(
        MaterialApp(
          home: PassengerProfilePage(
            profile: profile,
            authRepository: ProfileAuth(client),
            savedRepository: saved,
            recentRepository: recent,
            preferencesRepository: prefs,
            onProfileUpdated: (p) => updated = p,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rider'), findsNWidgets(2));
      expect(find.text('rider@example.test'), findsNWidgets(2));
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'New Rider');
      await tester.tap(find.text('Update Name'));
      await tester.pumpAndSettle();
      expect(updated?.fullName, 'New Rider');
      await tester.ensureVisible(find.text('500 m'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('500 m'));
      await tester.pumpAndSettle();
      expect(prefs.radius, 500);
      await tester.scrollUntilVisible(
        find.text('College'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Stop A → Stop B'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete College'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(saved.rows, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Clear History'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear History'));
      await tester.pumpAndSettle();
      expect(recent.rows, isEmpty);
    },
  );
  testWidgets('selecting saved journey returns only the stop pair', (
    tester,
  ) async {
    SavedJourney? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.of(context).push<SavedJourney>(
                  MaterialPageRoute(
                    builder: (_) => PassengerProfilePage(
                      profile: profile,
                      authRepository: ProfileAuth(client),
                      savedRepository: SavedFake(),
                      recentRepository: RecentFake(),
                      preferencesRepository: PreferencesFake(),
                      onProfileUpdated: (_) {},
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('College'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('College'));
    await tester.pumpAndSettle();
    expect(selected?.origin?.id, 'a');
    expect(selected?.destination?.id, 'b');
  });
}
