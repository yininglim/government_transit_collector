import 'package:government_transit_collector/core/widgets/responsive_app_shell.dart';
import 'dart:async';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_scenario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/admin_home/presentation/ai_recommendation_home_card.dart';
import 'package:government_transit_collector/features/admin_home/presentation/admin_home_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/ai_recommendation_analysis_session_store.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/bus_frequency_recommendation_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/route_bus_stop_recommendation_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/cost_estimation_report_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/recommendation_management_page.dart';
import 'admin_home_page_test.dart' show TestAuthRepository, adminProfile;
import 'ai_recommendation_home_fakes.dart';

const labels = ['Bus Frequency', 'Route & Bus Stop', 'Cost Estimation', 'Recommendation Management'];

void main() {
  testWidgets('first use shows readiness and confirmed empty management', (tester) async {
    final repository = FakeManagementRepository();
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
    await pumpCard(tester, repository: repository, store: store);
    expect(find.text('Ready to analyse your transit network.'), findsOneWidget);
    expect(metric(tester, 'Routes Available'), '1');
    expect(metric(tester, 'Analysis Functions'), '3');
    expect(metric(tester, 'Saved Recommendations'), '0');
    expect(find.text('Pending Review'), findsNothing);
    expect(find.text('Resume Analysis'), findsNothing);
    expect(find.text('Latest Recommendation'), findsNothing);
    for (final label in labels) { expect(find.widgetWithText(OutlinedButton, label), findsOneWidget); }
    expect(repository.loads, 1);
    expect(store.busFrequency.preparation, isNull);
    expect(store.routeStop.preparation, isNull);
    expect(store.cost.preparationFuture, isNull);
    expect(store.busFrequency.preparationVersion, 0);
    expect(store.routeStop.preparationVersion, 0);
    expect(store.cost.preparationVersion, 0);
  });

  testWidgets('real metrics ignore numeric legacy priority and invalid snapshots', (tester) async {
    await pumpCard(tester, repository: FakeManagementRepository(rows: [
      row('old', '2026-01-01', priority: 'high'),
      row('latest', '2026-03-01', priority: 'medium', status: 'accepted'),
      row('legacy', '2026-02-01'),
      row('invalid', '2026-02-02', priority: 'high', version: 9),
    ]));
    expect(metric(tester, 'Saved Recommendations'), '4');
    expect(metric(tester, 'Pending Review'), '3');
    expect(metric(tester, 'High Priority'), '1');
    expect(find.text('Route latest'), findsOneWidget);
    expect(find.text('Increase Peak-Hour Frequency'), findsOneWidget);
    expect(find.text('Medium Priority'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('Route old'), findsNothing);
  });

  testWidgets('legacy latest is Not Ranked with safe route fallback', (tester) async {
    final legacy = row('legacy', '2026-01-01');
    legacy['route_id'] = null;
    (legacy['supporting_metrics'] as Map)['route_display_label'] = '';
    await pumpCard(tester, repository: FakeManagementRepository(rows: [legacy]));
    expect(find.text('Not Ranked'), findsOneWidget);
    expect(find.text('Service recommendation'), findsOneWidget);
    expect(metric(tester, 'High Priority'), '0');
  });

  testWidgets('loading and failure never claim zero saved records', (tester) async {
    final pending = Completer<List<SavedRecommendation>>();
    await pumpCard(tester, repository: FakeManagementRepository(pending: pending), settle: false);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Saved Recommendations'), findsNothing);
    pending.completeError(StateError('private backend details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved recommendations are unavailable'), findsOneWidget);
    expect(find.textContaining('private backend'), findsNothing);
    expect(find.text('Saved Recommendations'), findsNothing);
    expect(find.byType(OutlinedButton), findsNWidgets(4));
    expect(find.text('Open AI Analysis'), findsOneWidget);
  });

  for (var index = 0; index < 3; index++) {
    testWidgets('retained feature $index provides resume without mutation', (tester) async {
      final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
      if (index == 0) { store.busFrequency..screeningComplete = true
          ..routesAnalysed = 2; }
      if (index == 1) { store.routeStop..screeningComplete = true
          ..routesAnalysed = 2; }
      if (index == 2) {
        store.cost.screeningComplete = true;
        store.cost.candidates.add(CostDashboardCandidate(route: testRoute, evidence: FakeCostEvidence()));
        store.cost
          ..additionalBusesInput = '2'
          ..additionalDriversInput = '3'
          ..selectedScenarioRouteId = 'route'
          ..calculatedPlanningContext = const CostPlanningContext(
            routeId: 'route',
            busFrequencyAction: 'increasePeakHourFrequency',
            additionalBuses: 2,
            additionalDrivers: 3,
            estimatedBusAcquisitionCostRm: 1400000,
            lowMonthlyDriverCostRm: 7500,
            highMonthlyDriverCostRm: 10500,
          );
      }
      Widget? opened;
      await pumpCard(tester, store: store, pageBuilder: (page) { opened = page; return const Scaffold(body: Text('Destination')); });
      final resume = find.text('${labels[index]}: Analysis Available');
      expect(resume, findsOneWidget);
      await tester.ensureVisible(resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expectSession(opened!, index, store);
      expect(store.cost.additionalBusesInput, index == 2 ? '2' : '');
    });
  }

  testWidgets('history or incomplete screening does not imply resume', (tester) async {
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
    store.busFrequency.periodStartUtc = DateTime(2026);
    store.routeStop.selectedRouteId = 'route';
    store.cost.selectedScenarioRouteId = 'route';
    await pumpCard(tester, store: store);
    expect(find.text('Resume Analysis'), findsNothing);
  });

  for (var index = 0; index < 4; index++) {
    testWidgets('shortcut $index opens existing page with shared dependencies', (tester) async {
      final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
      final repository = FakeManagementRepository();
      Widget? opened;
      await pumpCard(tester, store: store, repository: repository, pageBuilder: (page) { opened = page; return const Scaffold(body: Text('Destination')); });
      final shortcut = find.widgetWithText(OutlinedButton, labels[index]);
      await tester.ensureVisible(shortcut);
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      if (index < 3) { expectSession(opened!, index, store); }
      else { expect((opened as RecommendationManagementPage).repository, same(repository)); }
      Navigator.of(tester.element(find.text('Destination'))).pop();
      await tester.pumpAndSettle();
      expect(repository.loads, 2);
    });
  }

  testWidgets('Open AI Analysis selects existing dashboard and authenticated store', (tester) async {
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
    AiRecommendationAnalysisSessionStore? opened;
    await tester.pumpWidget(MaterialApp(home: AdminHomePage(
      profile: adminProfile, repository: TestAuthRepository(),
      recommendationManagementRepository: FakeManagementRepository(),
      routePerformanceRepository: FakeRoutesRepository(),
      aiRecommendationSessionStore: store,
      aiRecommendationDashboardBuilder: (value) { opened = value; return const Text('Existing dashboard'); },
    )));
    await tester.pumpAndSettle();
    final action = find.text('Open AI Analysis');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(opened, same(store));
    expect(find.text('Existing dashboard'), findsOneWidget);
    expect(tester.widget<ResponsiveAppShell>(find.byType(ResponsiveAppShell)).selectedIndex, 1);
  });

  for (final size in [const Size(320, 640), const Size(400, 800), const Size(800, 360), const Size(1100, 800)]) {
    testWidgets('long content reflows at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpCard(tester, repository: FakeManagementRepository(rows: [row('very long route name ' * 20, '2026-01-01', priority: 'high')]));
      for (final label in labels) {
        await tester.ensureVisible(find.widgetWithText(OutlinedButton, label));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  }
}

void expectSession(Widget page, int index, AiRecommendationAnalysisSessionStore store) {
  if (index == 0) { final p = page as BusFrequencyRecommendationPage; expect(p.session, same(store.busFrequency)); expect(p.preserveRetainedSession, isTrue); }
  if (index == 1) { final p = page as RouteBusStopRecommendationPage; expect(p.session, same(store.routeStop)); expect(p.preserveRetainedSession, isTrue); }
  if (index == 2) { final p = page as CostEstimationReportPage; expect(p.session, same(store.cost)); expect(p.busFrequencySession, same(store.busFrequency)); expect(p.preserveRetainedSession, isTrue); }
}

String metric(WidgetTester tester, String label) {
  final column = find.ancestor(of: find.text(label), matching: find.byType(Column)).first;
  return tester.widgetList<Text>(find.descendant(of: column, matching: find.byType(Text))).first.data!;
}

Future<void> pumpCard(WidgetTester tester, {FakeManagementRepository? repository, AiRecommendationAnalysisSessionStore? store, Widget Function(Widget)? pageBuilder, bool settle = true}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: AiRecommendationHomeCard(
    repository: repository ?? FakeManagementRepository(), routeRepository: FakeRoutesRepository(),
    sessionStore: store ?? AiRecommendationAnalysisSessionStore(adminUserId: 'admin'),
    onOpenAnalysis: () {}, pageBuilder: pageBuilder,
  )))));
  if (settle) await tester.pumpAndSettle();
}

Map<String, dynamic> row(String id, String date, {String? priority, int version = 1, String status = 'pending_review'}) => {
  'recommendation_id': id, 'recommendation_type': 'bus_frequency', 'route_id': id,
  'title': 'Service recommendation', 'description': 'Evidence rationale',
  'created_at': date, 'status': status, 'priority': 1,
  'supporting_metrics': {'feature_type': 'bus_frequency', 'route_display_label': 'Route $id', 'action': 'increasePeakHourFrequency', if (priority != null) 'priority_level': priority, if (priority != null) 'priority_rule_version': version},
};

