import 'package:flutter/rendering.dart';
import 'dart:async';
import 'package:government_transit_collector/core/theme/app_theme.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_models.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_repository.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/core/widgets/responsive_app_shell.dart';
import 'ai_recommendation_home_fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/admin_home/presentation/admin_home_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/ai_recommendation_analysis_session_store.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report_repository.dart';
import 'package:government_transit_collector/features/saved_operational_reports/presentation/saved_operational_reports_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('shows the five-destination admin shell with Home selected', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    await pumpAdmin(tester, auth: auth);

    final navigationBar = tester.widget<ResponsiveAppShell>(
      find.byType(ResponsiveAppShell),
    );
    expect(navigationBar.selectedIndex, 0);
    expect(navigationBar.items, hasLength(5));
    expect(
      navigationBar.items.map(
        (destination) => destination.label,
      ),
      ['Home', 'AI', 'Performance', 'Peak', 'Reports'],
    );
    expect(
      find.text('Monitor and improve Johor bus operations.'),
      findsOneWidget,
    );
    expect(find.text('Admin / Transport Authority'), findsNothing);
    expect(find.text('AI Transit Recommendation'), findsNothing);
    expect(find.text('AI Planning'), findsOneWidget);
    expect(find.text('Route Performance Dashboard'), findsNothing);
    expect(find.text('Peak Operation Analysis'), findsNothing);
    expect(find.text('Saved Operational Reports'), findsNothing);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pump();
    expect(auth.logoutCalls, 1);
  });

  testWidgets('lazily creates and preserves a visited Reports destination', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    final reports = EmptyReportsRepository();
    await pumpAdmin(tester, auth: auth, reports: reports);
    expect(reports.loadCalls, 1);

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(reports.loadCalls, 2);
    final reportsState = tester.state(find.byType(SavedOperationalReportsPage));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in [const Size(320, 640), const Size(844, 390), const Size(400, 800)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.widget<ResponsiveAppShell>(find.byType(ResponsiveAppShell)).selectedIndex, 4);
      expect(tester.state(find.byType(SavedOperationalReportsPage)), same(reportsState));
      expect(find.text('Government Transit Collector'), findsOneWidget);
      expect(find.byTooltip('Admin profile'), findsOneWidget);
      expect(find.byTooltip('Sign out'), findsOneWidget);
      expect(find.byTooltip('Refresh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    Navigator.of(tester.element(find.byType(SavedOperationalReportsPage))).push(
      MaterialPageRoute<void>(builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Report detail')),
        body: const Text('Detail content'),
      )),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-header')), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(SavedOperationalReportsPage)), same(reportsState));
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(reports.loadCalls, 3);
    expect(
      tester.state(find.byType(SavedOperationalReportsPage)),
      same(reportsState),
    );
  });

  testWidgets('AI destination opens the existing recommendation page', (
    tester,
  ) async {
    final auth = TestAuthRepository();
    await pumpAdmin(tester, auth: auth);

    await tester.tap(find.text('AI'));
    await tester.pump();
    expect(find.text('AI Recommendation Dashboard'), findsOneWidget);
    expect(find.text('AI Transit Recommendation'), findsOneWidget);
  });

  testWidgets(
    'AI destination receives and retains the injected session store',
    (tester) async {
      final auth = TestAuthRepository();
      final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
      final opened = <AiRecommendationAnalysisSessionStore>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AdminHomePage(
            profile: adminProfile,
            repository: auth,
            recommendationManagementRepository: FakeManagementRepository(),
            routePerformanceRepository: FakeRoutesRepository(),
            savedOperationalReportRepository: EmptyReportsRepository(),
            aiRecommendationSessionStore: store,
            aiRecommendationDashboardBuilder: (sessionStore) {
              opened.add(sessionStore);
              return const Scaffold(body: Text('Injected AI dashboard'));
            },
          ),
        ),
      );

      await tester.tap(find.text('AI'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Home'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('AI'));
      await tester.pump(const Duration(seconds: 1));

      expect(opened, hasLength(1));
      expect(opened.single, same(store));
      expect(find.text('Injected AI dashboard'), findsOneWidget);
    },
  );

  testWidgets('every Admin destination keeps the shared header and actions', (tester) async {
    final auth = TestAuthRepository();
    await tester.pumpWidget(MaterialApp(home: AdminHomePage(
      profile: adminProfile,
      repository: auth,
      recommendationManagementRepository: FakeManagementRepository(),
      routePerformanceRepository: EmptyNavigationRoutes(),
      peakOperationRepository: EmptyNavigationPeak(),
      savedOperationalReportRepository: EmptyReportsRepository(),
      aiRecommendationDashboardBuilder: (_) => const Text('AI content'),
    )));
    await tester.pumpAndSettle();
    for (final label in ['AI', 'Performance', 'Peak', 'Reports', 'Home']) {
      final destination = find.byKey(Key('admin-nav-$label'));
      await tester.ensureVisible(destination);
      await tester.tap(destination);
      await tester.pumpAndSettle();
      expect(find.text('Government Transit Collector'), findsOneWidget);
      expect(find.byTooltip('Admin profile'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byTooltip('Admin profile')).onPressed, isNull);
      expect(find.byTooltip('Sign out').hitTestable(), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pump();
    expect(auth.logoutCalls, 1);
  });

  testWidgets('populated Home uses network metadata saved report statuses and valid priorities', (tester) async {
    final reports = HomeReports(rows: reportRows());
    final recommendations = HomeRecommendations(rows: recommendationRows());
    final network = HomeNetwork();
    final peak = GuardedPeak();
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
    store.busFrequency..screeningComplete = true
      ..routesAnalysed = 7;
    store.routeStop..screeningComplete = true
      ..selectedRouteId = 'retained-route';
    store.cost..additionalBusesInput = '2'
      ..additionalDriversInput = '3';
    var dashboardBuilds = 0;
    await pumpOverview(tester, reports: reports, recommendations: recommendations,
      network: network, peak: peak, store: store,
      onDashboard: (_) => dashboardBuilds++);
    expect(homeMetric(tester, 'Routes'), '1');
    expect(homeMetric(tester, 'Saved Reports'), '4');
    expect(find.text('Needs Attention'), findsOneWidget);
    expect(find.text('Route C'), findsOneWidget);
    expect(find.text('Route B'), findsOneWidget);
    expect(find.text('Route A'), findsNothing);
    expect(find.text('Route Z'), findsNothing);
    expect(find.text('Based on saved report review statuses.'), findsOneWidget);
    expect(find.text('Pending Recommendations: 3'), findsOneWidget);
    expect(find.text('High Priority: 1'), findsOneWidget);
    expect(find.text('Recent Activity'), findsOneWidget);
    for (final title in ['Needs Attention', 'AI Planning', 'Recent Activity']) {
      final section = find.ancestor(of: find.text(title), matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_HomeSection',
      ));
      expect(find.descendant(of: section, matching: find.byType(Card)), findsOneWidget);
    }
    expect(find.text('Report Z'), findsOneWidget);
    expect(find.text('Report C'), findsOneWidget);
    expect(find.text('Report B'), findsNothing);
    expect(find.text('Operations overview'), findsNothing);
    expect(find.text('Quick Access'), findsNothing);
    expect(find.text('Analysis & Management'), findsNothing);
    expect(find.text('Bus Frequency Recommendation'), findsNothing);
    expect(find.text('Cost Estimation Report'), findsNothing);
    expect(find.text('Recommendation Management'), findsNothing);
    expect(dashboardBuilds, 0);
    expect(network.loads, 1);
    expect(reports.loadCalls, 1);
    expect(recommendations.loads, 1);
    expect(network.unexpectedCalls, 0);
    expect(reports.unexpectedCalls, 0);
    expect(recommendations.unexpectedCalls, 0);
    expect(peak.calls, 0);
    expect(store.busFrequency.routesAnalysed, 7);
    expect(store.routeStop.selectedRouteId, 'retained-route');
    expect(store.cost.additionalBusesInput, '2');
    expect(store.cost.additionalDriversInput, '3');
    expect(store.busFrequency.preparationVersion, 0);
    expect(store.routeStop.preparationVersion, 0);
    expect(store.cost.preparationVersion, 0);
    await tester.pump();
    expect(reports.loadCalls, 1);
  });

  testWidgets('empty Home is ready and omits empty activity', (tester) async {
    await pumpOverview(tester, network: HomeNetwork(empty: true));
    expect(homeMetric(tester, 'Routes'), '0');
    expect(homeMetric(tester, 'Saved Reports'), '0');
    expect(find.text('Ready for analysis'), findsOneWidget);
    expect(find.text('No immediate operational issues to review.'), findsOneWidget);
    expect(find.text('Recent Activity'), findsNothing);
    expect(find.text('Pending Recommendations: 0'), findsNothing);
  });

  for (final failed in ['routes', 'reports', 'recommendations']) {
    testWidgets('Home isolates $failed failure and keeps AI preview usable', (tester) async {
      final reports = HomeReports(rows: reportRows(), fail: failed == 'reports');
      final recommendations = HomeRecommendations(rows: recommendationRows(), fail: failed == 'recommendations');
      await pumpOverview(tester, reports: reports, recommendations: recommendations,
        network: HomeNetwork(fail: failed == 'routes'));
      expect(find.textContaining('private backend error'), findsNothing);
      if (failed == 'routes') {
        expect(homeMetric(tester, 'Routes'), 'Unavailable');
        expect(homeMetric(tester, 'Saved Reports'), '4');
        expect(find.text('Pending Recommendations: 3'), findsOneWidget);
      } else if (failed == 'reports') {
        expect(homeMetric(tester, 'Routes'), '1');
        expect(homeMetric(tester, 'Saved Reports'), 'Unavailable');
        expect(find.text('Operational report status is unavailable.'), findsOneWidget);
        expect(find.text('No immediate operational issues to review.'), findsNothing);
        expect(find.text('Recent Activity'), findsNothing);
      } else {
        expect(homeMetric(tester, 'Saved Reports'), '4');
        expect(find.text('Planning summary is unavailable.'), findsOneWidget);
        expect(find.text('Ready for analysis'), findsNothing);
      }
      await tester.ensureVisible(find.text('Open AI Analysis'));
      await tester.tap(find.text('Open AI Analysis'));
      await tester.pumpAndSettle();
      expect(find.text('Existing AI dashboard'), findsOneWidget);
      expect(tester.widget<ResponsiveAppShell>(find.byType(ResponsiveAppShell)).selectedIndex, 1);
    });
  }

  testWidgets('AI preview uses the existing authenticated dashboard store', (tester) async {
    final store = AiRecommendationAnalysisSessionStore(adminUserId: 'admin');
    AiRecommendationAnalysisSessionStore? opened;
    await pumpOverview(tester, store: store, onDashboard: (value) => opened = value);
    await tester.ensureVisible(find.text('Open AI Analysis'));
    await tester.tap(find.text('Open AI Analysis'));
    await tester.pumpAndSettle();
    expect(opened, same(store));
    expect(tester.widget<ResponsiveAppShell>(find.byType(ResponsiveAppShell)).selectedIndex, 1);
  });

  testWidgets('Home does not turn loading sources into zero or all-clear claims', (tester) async {
    final gate = Completer<List<SavedOperationalReport>>();
    await pumpOverview(tester, reports: HomeReports(pending: gate.future));
    expect(homeMetric(tester, 'Saved Reports'), 'Loading...');
    expect(find.text('Checking saved report statuses...'), findsOneWidget);
    expect(find.text('No immediate operational issues to review.'), findsNothing);
    gate.complete([]);
    await tester.pumpAndSettle();
    expect(homeMetric(tester, 'Saved Reports'), '0');
    expect(find.text('No immediate operational issues to review.'), findsOneWidget);
  });

  for (final size in [const Size(320, 640), const Size(390, 844), const Size(844, 390), const Size(1200, 800)]) {
    testWidgets('populated Home reflows without overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpOverview(tester, reports: HomeReports(rows: reportRows(longLabels: true)),
        recommendations: HomeRecommendations(rows: recommendationRows()));
      final first = tester.getRect(find.byKey(const ValueKey('home-metric-Routes')));
      final second = tester.getRect(find.byKey(const ValueKey('home-metric-Saved Reports')));
      expect(first.top, second.top);
      expect(first.height, closeTo(second.height, 0.01));
      expect(first.width, closeTo(second.width, 0.01));
      final attention = tester.getRect(find.byKey(const Key('home-needs-attention')));
      final planning = tester.getRect(find.byKey(const Key('home-ai-planning')));
      if (size.width > size.height) {
        expect(attention.top, planning.top);
        expect(planning.left, greaterThan(attention.right));
        expect(find.byKey(const Key('app-side-navigation')), findsOneWidget);
      } else {
        expect(planning.top, greaterThan(attention.bottom));
        expect(find.byKey(const Key('app-bottom-navigation')), findsOneWidget);
      }
      await tester.ensureVisible(find.text('Open AI Analysis'));
      await tester.pump();
      expect(find.text('Open AI Analysis').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Recent Activity'));
      await tester.pump();
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.textContaining('Long saved report title'),
      )) {
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.maxLines, isNull);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(400, 800), const Size(800, 400)]) {
    testWidgets('admin Home has no overflow at ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = TestAuthRepository();
      await pumpAdmin(tester, auth: auth);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> pumpAdmin(
  WidgetTester tester, {
  required TestAuthRepository auth,
  EmptyReportsRepository? reports,
}) => tester.pumpWidget(
  MaterialApp(
    home: AdminHomePage(
      profile: adminProfile,
      repository: auth,
      recommendationManagementRepository: FakeManagementRepository(),
      routePerformanceRepository: FakeRoutesRepository(),
      aiRecommendationDashboardBuilder: (_) => const Scaffold(
        body: Column(children: [
          Text('AI Recommendation Dashboard'),
          Text('AI Transit Recommendation'),
        ]),
      ),
      savedOperationalReportRepository: reports ?? EmptyReportsRepository(),
    ),
  ),
);

const adminProfile = AppProfile(
  userId: 'admin',
  fullName: 'Admin',
  role: 'admin',
  email: 'admin@example.com',
);

class TestAuthRepository extends AuthRepository {
  TestAuthRepository()
    : super(
        client: SupabaseClient(
          'https://example.test',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

class EmptyReportsRepository implements SavedOperationalReportRepository {
  int loadCalls = 0;

  @override
  Future<List<SavedOperationalReport>> loadReports() async {
    loadCalls++;
    return const [];
  }

  @override
  Future<SavedOperationalReport> createPeakOperationReport({
    required String? routeId,
    required String routeNameSnapshot,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  }) => throw UnimplementedError();

  @override
  Future<SavedOperationalReport> createRoutePerformanceReport({
    required String routeId,
    required String routeNameSnapshot,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteReport(String reportId) => throw UnimplementedError();

  @override
  Future<SavedOperationalReport> loadReport(String reportId) =>
      throw UnimplementedError();

  @override
  Future<SavedOperationalReport> updateManagementMetadata({
    required String reportId,
    required String title,
    required String? adminNotes,
    required SavedOperationalReportStatus status,
  }) => throw UnimplementedError();
}

class EmptyNavigationRoutes extends FakeRoutesRepository {
  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() async => [];
}

class EmptyNavigationPeak implements PeakOperationRepository {
  @override
  Future<List<PeakOperationRoute>> loadRoutes() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected analysis');
}

Future<void> pumpOverview(WidgetTester tester, {
  HomeNetwork? network,
  HomeReports? reports,
  HomeRecommendations? recommendations,
  GuardedPeak? peak,
  AiRecommendationAnalysisSessionStore? store,
  void Function(AiRecommendationAnalysisSessionStore)? onDashboard,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: AdminHomePage(
      profile: adminProfile,
      repository: TestAuthRepository(),
      routePerformanceRepository: network ?? HomeNetwork(),
      savedOperationalReportRepository: reports ?? HomeReports(),
      recommendationManagementRepository: recommendations ?? HomeRecommendations(),
      peakOperationRepository: peak ?? GuardedPeak(),
      aiRecommendationSessionStore: store,
      aiRecommendationDashboardBuilder: (session) {
        onDashboard?.call(session);
        return const Text('Existing AI dashboard');
      },
    ),
  ));
  await tester.pumpAndSettle();
}

String homeMetric(WidgetTester tester, String label) => tester.widgetList<Text>(
  find.descendant(of: find.byKey(ValueKey('home-metric-$label')), matching: find.byType(Text)),
).first.data!;

List<SavedOperationalReport> reportRows({bool longLabels = false}) => [
  for (final entry in ['A', 'B', 'C', 'Z'].asMap().entries)
    SavedOperationalReport(
      reportId: entry.value, adminId: 'admin',
      reportType: entry.value == 'B' ? SavedOperationalReportType.peakOperation : SavedOperationalReportType.routePerformance,
      routeId: entry.value,
      routeNameSnapshot: longLabels ? 'Long route label ' * 20 : 'Route ${entry.value}',
      periodStart: DateTime(2026, 9, 1), periodEnd: DateTime(2026, 9, 2),
      title: longLabels ? 'Long saved report title ' * 20 : 'Report ${entry.value}',
      resultSnapshot: const {'delayedTripCount': 99999}, adminNotes: null,
      status: entry.value == 'Z' ? SavedOperationalReportStatus.resolved : SavedOperationalReportStatus.needsAttention,
      createdAt: DateTime(2026, 9, entry.key + 1), updatedAt: DateTime(2026, 9, entry.key + 1),
    ),
];

List<Map<String, dynamic>> recommendationRows() => [
  for (final id in ['high', 'legacy', 'invalid', 'accepted']) {
    'recommendation_id': id, 'recommendation_type': 'bus_frequency',
    'title': 'Saved recommendation', 'description': 'Existing rationale',
    'status': id == 'accepted' ? 'accepted' : 'pending_review',
    'priority': 1,
    'supporting_metrics': {
      'feature_type': 'bus_frequency',
      if (id != 'legacy') 'priority_rule_version': id == 'invalid' ? 9 : 1,
      if (id != 'legacy') 'priority_level': id == 'accepted' ? 'low' : 'high',
    },
  },
];

class HomeNetwork extends FakeRoutesRepository {
  HomeNetwork({this.fail = false, this.empty = false});
  final bool fail;
  final bool empty;
  int loads = 0;
  int unexpectedCalls = 0;
  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() async {
    loads++;
    if (fail) throw StateError('private backend error');
    return empty ? [] : [testRoute];
  }
  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('Unexpected operational analysis');
  }
}

class HomeReports implements SavedOperationalReportRepository {
  HomeReports({this.rows = const [], this.fail = false, this.pending});
  final List<SavedOperationalReport> rows;
  final bool fail;
  final Future<List<SavedOperationalReport>>? pending;
  int loadCalls = 0;
  int unexpectedCalls = 0;
  @override
  Future<List<SavedOperationalReport>> loadReports() async {
    loadCalls++;
    if (fail) throw StateError('private backend error');
    return pending == null ? rows : await pending!;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('Unexpected report mutation or generation');
  }
}

class HomeRecommendations extends FakeManagementRepository {
  HomeRecommendations({super.rows, this.fail = false});
  final bool fail;
  int unexpectedCalls = 0;
  @override
  Future<List<SavedRecommendation>> loadSavedRecommendations() {
    if (fail) return Future.error(StateError('private backend error'));
    return super.loadSavedRecommendations();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('Unexpected recommendation mutation');
  }
}

class GuardedPeak implements PeakOperationRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Home must not run Peak analysis');
  }
}
