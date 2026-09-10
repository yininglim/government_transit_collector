import 'dart:async';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/bus_frequency_recommendation_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/route_bus_stop_recommendation_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/cost_estimation_report_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/recommendation_management_page.dart';


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/ai_recommendation_analysis_session_store.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/ai_recommendation_dashboard_page.dart';

import 'package:government_transit_collector/core/theme/app_theme.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_scenario.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import '../admin_home/ai_recommendation_home_fakes.dart';
import 'bus_frequency_dashboard_test.dart' as bus;
import 'route_stop_dashboard_test.dart' as route;

const functionTitles = [
  'Bus Frequency Recommendation',
  'Route & Bus Stop Recommendation',
  'Cost Estimation Report',
  'Recommendation Management',
];

void main() {
  testWidgets('first use shows confirmed readiness and four function cards', (tester) async {
    final management = FakeManagementRepository();
    await pumpDashboard(tester, management: management);
    expect(find.text('AI Transit Recommendation'), findsOneWidget);
    expect(find.text('Ready to analyse your transit network.'), findsOneWidget);
    expect(metric(tester, 'Routes Available'), '1');
    expect(metric(tester, 'Analysis Tools'), '3');
    expect(metric(tester, 'Saved Recommendations'), '0');
    expect(find.text('Pending Review'), findsNothing);
    expect(find.text('High Priority'), findsNothing);
    expect(find.text('Current Analysis'), findsNothing);
    for (final title in functionTitles) { expect(find.text(title), findsOneWidget); }
    expect(find.byType(FilledButton), findsNWidgets(4));
    expect(management.loads, 1);
  });

  testWidgets('saved summary uses valid snapshot priority and feature counts', (tester) async {
    await pumpDashboard(tester, management: FakeManagementRepository(rows: [
      savedRow('high', priority: 'high'),
      savedRow('legacy'),
      savedRow('invalid', priority: 'high', version: 99),
      savedRow('route', feature: 'route_bus_stop', status: 'accepted', priority: 'medium'),
    ]));
    expect(metric(tester, 'Saved Recommendations'), '4');
    expect(metric(tester, 'Pending Review'), '3');
    expect(metric(tester, 'High Priority'), '1');
    expect(find.text('3 saved recommendations'), findsOneWidget);
    expect(find.text('1 saved recommendation'), findsOneWidget);
    expect(find.text('3 pending review / 1 high priority'), findsOneWidget);
    expect(find.text('Ready to analyse your transit network.'), findsNothing);
  });

  testWidgets('loading then failure leaves tools usable without false zeros', (tester) async {
    final gate = Completer<List<SavedRecommendation>>();
    await pumpDashboard(tester, management: FakeManagementRepository(pending: gate), settle: false);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Saved Recommendations'), findsNothing);
    gate.completeError(StateError('sensitive backend error'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved recommendations are unavailable'), findsOneWidget);
    expect(find.textContaining('sensitive backend error'), findsNothing);
    expect(find.text('Saved Recommendations'), findsNothing);
    expect(find.byType(FilledButton), findsNWidgets(4));
    await openFunction(tester, 3);
    expect(find.text('Destination 3'), findsOneWidget);
  });

  testWidgets('route metadata failure omits only route count', (tester) async {
    await pumpDashboard(tester, routes: UnavailableRoutes());
    expect(find.text('Routes Available'), findsNothing);
    expect(metric(tester, 'Analysis Tools'), '3');
    expect(find.byType(FilledButton), findsNWidgets(4));
  });

  for (var index = 0; index < 3; index++) {
    testWidgets('retained feature $index resumes identical authenticated session', (tester) async {
      final store = retainedStore();
      Object? opened;
      await pumpDashboard(tester, store: store, onOpen: (value) => opened = value);
      final label = ['Bus Frequency', 'Route & Bus Stop', 'Cost Estimation'][index];
      final resume = find.widgetWithText(OutlinedButton, label);
      expect(find.text('Current Analysis'), findsOneWidget);
      expect(resume, findsOneWidget);
      final stateLabel = index == 2 ? 'Calculation Available' : 'Result Available';
      expect(find.descendant(of: resume, matching: find.text(stateLabel)), findsOneWidget);
      final busResult = store.busFrequency.recommendationResult;
      final routeResult = store.routeStop.recommendationResult;
      final calculation = store.cost.calculatedPlanningContext;
      await tester.ensureVisible(resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(opened, same([store.busFrequency, store.routeStop, store.cost][index]));
      expect(store.busFrequency.recommendationResult, same(busResult));
      expect(store.routeStop.recommendationResult, same(routeResult));
      expect(store.cost.calculatedPlanningContext, same(calculation));
      expect(store.cost.additionalBusesInput, '2');
      expect(store.cost.additionalDriversInput, '3');
      expect(store.routeStop.selectedRouteId, 'R1');
    });
  }

  testWidgets('prepared screening is not labelled a generated result', (tester) async {
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
    store.busFrequency..screeningComplete = true
      ..routesAnalysed = 2;
    store.routeStop..screeningComplete = true
      ..candidates.add(route.candidate('R1'));
    await pumpDashboard(tester, store: store);
    expect(find.text('Current Analysis'), findsOneWidget);
    expect(find.text('Screening Available'), findsNWidgets(2));
    expect(find.text('Evidence Ready'), findsNWidgets(2));
    expect(find.text('Result Available'), findsNothing);
  });

  testWidgets('history and failed result alone do not imply retained analysis', (tester) async {
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
    store.busFrequency.periodStartUtc = DateTime(2026);
    store.busFrequency.recommendationResult = const BusFrequencyRecommendationResult(
      status: BusFrequencyRecommendationStatus.temporarilyUnavailable,
      synthesis: null, failure: BusFrequencyRecommendationFailure.timeout, payload: null,
    );
    store.routeStop.selectedRouteId = 'R1';
    store.cost.selectedScenarioRouteId = 'R1';
    await pumpDashboard(tester, store: store);
    expect(find.text('Current Analysis'), findsNothing);
    expect(find.text('Result Available'), findsNothing);
  });

  for (var index = 0; index < 4; index++) {
    testWidgets('function $index keeps navigation and refreshes after return', (tester) async {
      final store = retainedStore();
      final management = FakeManagementRepository();
      Object? opened;
      await pumpDashboard(tester, store: store, management: management, onOpen: (value) => opened = value);
      await openFunction(tester, index);
      expect(find.text('Destination $index'), findsOneWidget);
      expect(opened, same([store.busFrequency, store.routeStop, store.cost, management][index]));
      Navigator.of(tester.element(find.text('Destination $index'))).pop();
      await tester.pumpAndSettle();
      expect(management.loads, 2);
      expect(find.text('Current Analysis'), findsOneWidget);
    });
  }

  testWidgets('default destinations receive retained sessions and existing repositories', (tester) async {
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
    store.busFrequency.screeningComplete = true;
    store.routeStop.screeningComplete = true;
    store.cost.screeningComplete = true;
    final management = FakeManagementRepository();
    final busCoordinator = RecordingBusFrequencyCoordinator();
    final routeCoordinator = RecordingRouteStopCoordinator(events: []);
    final costCoordinator = RecordingCostDashboardCoordinator();
    await tester.pumpWidget(MaterialApp(home: AiRecommendationDashboardPage(
      sessionStore: store,
      managementRepository: management,
      routeRepository: FakeRoutesRepository(),
      busFrequencyCoordinator: busCoordinator,
      routeStopCoordinator: routeCoordinator,
      costCoordinator: costCoordinator,
    )));
    await tester.pumpAndSettle();
    for (var index = 0; index < 4; index++) {
      await openFunction(tester, index);
      if (index == 0) {
        final page = tester.widget<BusFrequencyRecommendationPage>(find.byType(BusFrequencyRecommendationPage));
        expect(page.session, same(store.busFrequency));
        expect(page.preserveRetainedSession, isTrue);
        expect(page.managementRepository, same(management));
      } else if (index == 1) {
        final page = tester.widget<RouteBusStopRecommendationPage>(find.byType(RouteBusStopRecommendationPage));
        expect(page.session, same(store.routeStop));
        expect(page.preserveRetainedSession, isTrue);
        expect(page.managementRepository, same(management));
      } else if (index == 2) {
        final page = tester.widget<CostEstimationReportPage>(find.byType(CostEstimationReportPage));
        expect(page.session, same(store.cost));
        expect(page.busFrequencySession, same(store.busFrequency));
        expect(page.preserveRetainedSession, isTrue);
      } else {
        final page = tester.widget<RecommendationManagementPage>(find.byType(RecommendationManagementPage));
        expect(page.repository, same(management));
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(busCoordinator.prepareCalls, 0);
    expect(routeCoordinator.prepareCalls, 0);
    expect(costCoordinator.prepareCalls, 0);
  });

  testWidgets('render and rebuild do not prepare analyse or mutate even with legacy preload flags', (tester) async {
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
    final busCoordinator = RecordingBusFrequencyCoordinator();
    final routeCoordinator = RecordingRouteStopCoordinator(events: []);
    final costCoordinator = RecordingCostDashboardCoordinator();
    final management = FakeManagementRepository();
    final routes = CountingRoutes();
    Widget dashboard() => MaterialApp(home: AiRecommendationDashboardPage(
      sessionStore: store,
      managementRepository: management,
      routeRepository: routes,
      busFrequencyCoordinator: busCoordinator,
      routeStopCoordinator: routeCoordinator,
      costCoordinator: costCoordinator,
      preloadBusFrequency: true,
      preloadRouteStops: true,
    ));
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();
    expect(busCoordinator.prepareCalls, 0);
    expect(busCoordinator.analysisCalls, 0);
    expect(routeCoordinator.prepareCalls, 0);
    expect(costCoordinator.prepareCalls, 0);
    expect(store.busFrequency.preparationVersion, 0);
    expect(store.routeStop.preparationVersion, 0);
    expect(store.cost.preparationVersion, 0);
    expect(store.busFrequency.preparation, isNull);
    expect(store.routeStop.preparation, isNull);
    expect(store.cost.preparationFuture, isNull);
    expect(management.loads, 1);
    expect(routes.calls, 1);
  });

  for (final size in [const Size(320, 640), const Size(400, 800), const Size(740, 360), const Size(1100, 800)]) {
    testWidgets('dashboard content and actions reflow without overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = retainedStore();
      await pumpDashboard(tester, store: store, management: FakeManagementRepository(rows: [savedRow('saved', priority: 'high')]));
      final metricCards = [
        for (final label in ['Saved Recommendations', 'Pending Review', 'High Priority'])
          find.byKey(ValueKey('planning-metric-$label')),
      ];
      final metricRects = metricCards.map(tester.getRect).toList();
      for (var index = 0; index < metricRects.length; index++) {
        expect(metricRects[index].top, closeTo(metricRects.first.top, 0.01));
        expect(metricRects[index].height, closeTo(metricRects.first.height, 0.01));
        expect(metricRects[index].width, closeTo(metricRects.first.width, 0.01));
        expect(find.descendant(of: metricCards[index], matching: find.byType(Icon)), findsOneWidget);
        if (index > 0) {
          expect(metricRects[index].left - metricRects[index - 1].right, closeTo(8, 0.01));
        }
      }
      for (var index = 0; index < 4; index++) {
        final button = actionFor(index);
        await tester.ensureVisible(button);
        await tester.pump();
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      final first = tester.getTopLeft(find.text(functionTitles[0]));
      final second = tester.getTopLeft(find.text(functionTitles[1]));
      if (size.width - 48 >= 600) {
        expect(first.dy, second.dy);
        expect(second.dx, greaterThan(first.dx));
        for (final pair in [0, 2]) {
          final left = tester.getRect(functionCard(pair));
          final right = tester.getRect(functionCard(pair + 1));
          expect(left.height, closeTo(right.height, 0.01));
          expect(left.top, closeTo(right.top, 0.01));
          expect(right.left - left.right, closeTo(16, 0.01));
          expect(tester.getRect(actionFor(pair)).bottom,
              closeTo(tester.getRect(actionFor(pair + 1)).bottom, 0.01));
        }
      } else {
        expect(second.dy, greaterThan(first.dy));
        for (var index = 0; index < 4; index++) {
          final rect = tester.getRect(functionCard(index));
          expect(rect.width, closeTo(size.width - 48, 0.01));
          expect(rect.left, closeTo(24, 0.01));
          if (index > 0) {
            expect(rect.top - tester.getRect(functionCard(index - 1)).bottom,
                closeTo(16, 0.01));
          }
          expect(rect.bottom - tester.getRect(actionFor(index)).bottom,
              closeTo(16, 0.01));
        }
      }
    });
  }
}

Future<void> pumpDashboard(WidgetTester tester, {
  AiRecommendationAnalysisSessionStore? store,
  FakeManagementRepository? management,
  FakeRoutesRepository? routes,
  void Function(Object)? onOpen,
  bool settle = true,
}) async {
  Widget destination(int index, Object session) {
    onOpen?.call(session);
    return Scaffold(body: Text('Destination $index'));
  }
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: AiRecommendationDashboardPage(
      sessionStore: store ?? AiRecommendationAnalysisSessionStore(adminUserId: 'admin'),
      managementRepository: management ?? FakeManagementRepository(),
      routeRepository: routes ?? FakeRoutesRepository(),
      busFrequencyPageBuilder: (session) => destination(0, session),
      routeStopPageBuilder: (session) => destination(1, session),
      costPageBuilder: (session) => destination(2, session),
      managementPageBuilder: (repository) => destination(3, repository),
    ),
  ));
  if (settle) await tester.pumpAndSettle();
}

Finder functionCard(int index) => find.ancestor(
  of: find.text(functionTitles[index]),
  matching: find.byType(Card),
).first;

Finder actionFor(int index) => find.descendant(
  of: functionCard(index),
  matching: find.byType(FilledButton),
);

Future<void> openFunction(WidgetTester tester, int index) async {
  final button = actionFor(index);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

String metric(WidgetTester tester, String label) {
  final column = find.ancestor(of: find.text(label), matching: find.byType(Column)).first;
  return tester.widgetList<Text>(find.descendant(of: column, matching: find.byType(Text))).first.data!;
}

Map<String, dynamic> savedRow(String id, {String? priority, int version = 1, String feature = 'bus_frequency', String status = 'pending_review'}) => {
  'recommendation_id': id, 'recommendation_type': feature == 'bus_frequency' ? feature : 'route_improvement',
  'title': 'Saved planning recommendation', 'description': 'Evidence-backed rationale',
  'route_id': 'R1', 'status': status, 'created_at': '2026-09-01', 'priority': 1,
  'supporting_metrics': {'feature_type': feature, 'priority_rule_version': version, if (priority != null) 'priority_level': priority},
};

AiRecommendationAnalysisSessionStore retainedStore() {
  final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
  store.busFrequency..screeningComplete = true
    ..recommendationResult = bus.success(['R1']);
  store.routeStop..screeningComplete = true
    ..recommendationResult = route.groupedResult(['R1'])
    ..selectedRouteId = 'R1';
  store.cost..screeningComplete = true
    ..candidates.add(CostDashboardCandidate(route: testRoute, evidence: FakeCostEvidence()))
    ..selectedScenarioRouteId = 'route'
    ..additionalBusesInput = '2'
    ..additionalDriversInput = '3'
    ..calculatedPlanningContext = const CostPlanningContext(
      routeId: 'route', busFrequencyAction: 'increasePeakHourFrequency',
      additionalBuses: 2, additionalDrivers: 3,
      estimatedBusAcquisitionCostRm: 1400000,
    );
  return store;
}

class CountingRoutes extends FakeRoutesRepository {
  int calls = 0;
  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() async {
    calls++;
    return super.loadRoutes();
  }
}

class UnavailableRoutes extends FakeRoutesRepository {
  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() async => throw StateError('metadata failure');
}

class RecordingBusFrequencyCoordinator
    implements BusFrequencyDashboardCoordinator {
  RecordingBusFrequencyCoordinator({this.events, this.gate});

  final List<String>? events;
  final Completer<void>? gate;
  int prepareCalls = 0;
  int analysisCalls = 0;
  BusFrequencyDashboardSession? preparedSession;

  @override
  Future<void> prepareSession({
    required BusFrequencyDashboardSession session,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    prepareCalls++;
    events?.add('6C started');
    preparedSession = session;
    if (gate != null) await gate!.future;
    events?.add('6C settled');
  }

  @override
  Future<BusFrequencyRecommendationResult> analyse({
    required List<BusFrequencyDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) {
    analysisCalls++;
    throw StateError('Gemini generation must not run during preload');
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected analysis operation: ${invocation.memberName}',
  );

}

class RecordingRouteStopCoordinator implements RouteStopDashboardCoordinator {
  RecordingRouteStopCoordinator({required this.events});

  final List<String> events;
  int prepareCalls = 0;

  @override
  Future<void> prepareSession({
    required RouteStopDashboardSession session,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    prepareCalls++;
    events.add('6D started');
    events.add('6D settled');
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected analysis operation: ${invocation.memberName}',
  );

}

class RecordingCostDashboardCoordinator implements CostDashboardCoordinator {
  int prepareCalls = 0;

  @override
  Future<void> prepareSession({
    required CostDashboardSession session,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  }) async {
    prepareCalls++;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected analysis operation: ${invocation.memberName}',
  );

}
