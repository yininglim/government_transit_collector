import '../admin_home/ai_recommendation_home_fakes.dart' as overview;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/admin_home/presentation/admin_home_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/ai_recommendation_analysis_session_store.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_scenario.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/ai_recommendation_dashboard_page.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('same Admin reopens AI Analysis with the same session store', (
    tester,
  ) async {
    final client = _client();
    addTearDown(client.dispose);
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin-a');
    store.busFrequency
      ..screeningComplete = true
      ..routesAnalysed = 7
      ..recommendationResult = const BusFrequencyRecommendationResult(
        status: BusFrequencyRecommendationStatus.available,
        synthesis: BusFrequencyRecommendationSynthesis(
          overallSummary: 'Retained result',
          routeRecommendations: [],
          recommendationGroups: [],
          needsMoreEvidence: null,
        ),
        failure: null,
        payload: null,
      );
    store.busFrequency.savedRecommendationIds.add('J10');
    final retainedResult = store.busFrequency.recommendationResult;
    store.routeStop
      ..screeningComplete = true
      ..routesAnalysed = 5;
    store.cost
      ..screeningComplete = true
      ..batchTotal = 3
      ..selectedScenarioRouteId = 'J10'
      ..additionalBusesInput = '2'
      ..additionalDriversInput = '3'
      ..resourceCostReady = true
      ..calculatedPlanningContext = const CostPlanningContext(
        routeId: 'J10',
        busFrequencyAction: 'increasePeakHourFrequency',
        additionalBuses: 2,
        additionalDrivers: 3,
        estimatedBusAcquisitionCostRm: 1400000,
        lowMonthlyDriverCostRm: 7500,
        highMonthlyDriverCostRm: 10500,
      );
    final opened = <AiRecommendationAnalysisSessionStore>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomePage(
          profile: _profile('admin-a'),
          repository: _RecordingAuthRepository(client),
          aiRecommendationSessionStore: store,
          aiRecommendationDashboardBuilder: (value) {
            opened.add(value);
            return const Scaffold(body: Text('Retained AI Analysis'));
          },
        ),
      ),
    );

    await tester.tap(find.text('AI Transit Recommendation'));
    await tester.pumpAndSettle();
    expect(opened.single, same(store));
    Navigator.of(tester.element(find.text('Retained AI Analysis'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI Transit Recommendation'));
    await tester.pumpAndSettle();

    expect(opened.length, 2);
    expect(opened.every((value) => identical(value, store)), isTrue);
    expect(store.busFrequency.routesAnalysed, 7);
    expect(store.busFrequency.recommendationResult, same(retainedResult));
    expect(store.busFrequency.savedRecommendationIds, contains('J10'));
    expect(store.routeStop.routesAnalysed, 5);
    expect(store.cost.batchTotal, 3);
    expect(store.cost.selectedScenarioRouteId, 'J10');
    expect(store.cost.additionalBusesInput, '2');
    expect(store.cost.additionalDriversInput, '3');
    expect(store.cost.resourceCostReady, isTrue);
    expect(
      store.cost.calculatedPlanningContext?.estimatedBusAcquisitionCostRm,
      1400000,
    );
  });

  testWidgets('dashboard uses retained C D and E session instances', (
    tester,
  ) async {
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin-a');
    store.busFrequency.screeningComplete = true;
    store.routeStop.screeningComplete = true;
    store.busFrequency.savedRecommendationIds.add('J10');
    store.routeStop.savedRecommendationIds.add('J20');
    store.cost
      ..screeningComplete = true
      ..additionalBusesInput = '2'
      ..additionalDriversInput = '3'
      ..resourceCostReady = true;
    BusFrequencyDashboardSession? busSession;
    RouteStopDashboardSession? routeSession;
    CostDashboardSession? costSession;
    await tester.pumpWidget(
      MaterialApp(
        home: AiRecommendationDashboardPage(
          routeRepository: overview.FakeRoutesRepository(),
          managementRepository: overview.FakeManagementRepository(),
          sessionStore: store,
          preloadBusFrequency: false,
          preloadRouteStops: false,
          busFrequencyPageBuilder: (session) {
            busSession = session;
            return const Scaffold(body: Text('C session'));
          },
          routeStopPageBuilder: (session) {
            routeSession = session;
            return const Scaffold(body: Text('D session'));
          },
          costPageBuilder: (session) {
            costSession = session;
            return const Scaffold(body: Text('E session'));
          },
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Bus Frequency Recommendation'));
    await tester.tap(find.text('Bus Frequency Recommendation'));
    await tester.pumpAndSettle();
    expect(busSession, same(store.busFrequency));
    Navigator.of(tester.element(find.text('C session'))).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Route & Bus Stop Recommendation'));
    await tester.tap(find.text('Route & Bus Stop Recommendation'));
    await tester.pumpAndSettle();
    expect(routeSession, same(store.routeStop));
    Navigator.of(tester.element(find.text('D session'))).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cost Estimation Report'));
    await tester.tap(find.text('Cost Estimation Report'));
    await tester.pumpAndSettle();
    expect(costSession, same(store.cost));
  });

  testWidgets('logout clears all temporary analysis sessions', (tester) async {
    final client = _client();
    addTearDown(client.dispose);
    final auth = _RecordingAuthRepository(client);
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin-a');
    store.busFrequency.screeningComplete = true;
    store.routeStop.screeningComplete = true;
    store.cost
      ..screeningComplete = true
      ..additionalBusesInput = '2'
      ..additionalDriversInput = '3'
      ..resourceCostReady = true;
    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomePage(
          profile: _profile('admin-a'),
          repository: auth,
          aiRecommendationSessionStore: store,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pump();

    expect(auth.logoutCalls, 1);
    expect(store.busFrequency.screeningComplete, isFalse);
    expect(store.routeStop.screeningComplete, isFalse);
    expect(store.cost.screeningComplete, isFalse);
    expect(store.cost.additionalBusesInput, isEmpty);
    expect(store.cost.additionalDriversInput, isEmpty);
    expect(store.cost.resourceCostReady, isFalse);
  });

  testWidgets('different Admin cannot inherit prior temporary sessions', (
    tester,
  ) async {
    final client = _client();
    addTearDown(client.dispose);
    final oldStore = AiRecommendationAnalysisSessionStore(
      adminUserId: 'admin-a',
    );
    oldStore.busFrequency.screeningComplete = true;
    oldStore.cost
      ..screeningComplete = true
      ..selectedScenarioRouteId = 'J10'
      ..additionalBusesInput = '2'
      ..resourceCostReady = true;
    AiRecommendationAnalysisSessionStore? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomePage(
          profile: _profile('admin-b'),
          repository: _RecordingAuthRepository(client),
          aiRecommendationSessionStore: oldStore,
          aiRecommendationDashboardBuilder: (store) {
            opened = store;
            return const Scaffold(body: Text('Fresh AI Analysis'));
          },
        ),
      ),
    );
    await tester.tap(find.text('AI Transit Recommendation'));
    await tester.pumpAndSettle();

    expect(opened, isNot(same(oldStore)));
    expect(opened!.adminUserId, 'admin-b');
    expect(opened!.busFrequency.screeningComplete, isFalse);
    expect(opened!.cost.selectedScenarioRouteId, isNull);
    expect(opened!.cost.additionalBusesInput, isEmpty);
    expect(oldStore.busFrequency.screeningComplete, isFalse);
    expect(oldStore.cost.selectedScenarioRouteId, isNull);
  });

  test('feature-specific clear leaves the other sessions intact', () {
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin-a');
    store.busFrequency.screeningComplete = true;
    store.routeStop.screeningComplete = true;
    store.cost.screeningComplete = true;
    store.cost.additionalBusesInput = '2';
    store.busFrequency.savedRecommendationIds.add('J10');
    store.routeStop.savedRecommendationIds.add('J20');

    store.busFrequency.clear();

    expect(store.busFrequency.screeningComplete, isFalse);
    expect(store.routeStop.screeningComplete, isTrue);
    expect(store.cost.screeningComplete, isTrue);
    expect(store.cost.additionalBusesInput, '2');
    expect(store.busFrequency.savedRecommendationIds, isEmpty);
    expect(store.routeStop.savedRecommendationIds, contains('J20'));
  });

  test('Cost Start New Analysis state clear leaves C and D intact', () {
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin-a');
    store.busFrequency
      ..screeningComplete = true
      ..routesAnalysed = 7;
    store.routeStop
      ..screeningComplete = true
      ..routesAnalysed = 5;
    store.cost
      ..screeningComplete = true
      ..selectedScenarioRouteId = 'J10'
      ..additionalBusesInput = '2'
      ..additionalDriversInput = '3'
      ..resourceCostReady = true;

    store.cost.clear();

    expect(store.cost.screeningComplete, isFalse);
    expect(store.cost.selectedScenarioRouteId, isNull);
    expect(store.cost.additionalBusesInput, isEmpty);
    expect(store.cost.additionalDriversInput, isEmpty);
    expect(store.cost.resourceCostReady, isFalse);
    expect(store.busFrequency.screeningComplete, isTrue);
    expect(store.busFrequency.routesAnalysed, 7);
    expect(store.routeStop.screeningComplete, isTrue);
    expect(store.routeStop.routesAnalysed, 5);
  });
}

class _RecordingAuthRepository extends AuthRepository {
  _RecordingAuthRepository(SupabaseClient client) : super(client: client);

  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

SupabaseClient _client() => SupabaseClient(
  'https://example.test',
  'test-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

AppProfile _profile(String userId) => AppProfile(
  userId: userId,
  fullName: 'Admin',
  role: 'admin',
  email: 'admin@example.test',
);
