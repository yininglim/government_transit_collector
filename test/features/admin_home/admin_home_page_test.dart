import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/admin_home/presentation/admin_home_page.dart';
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

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navigationBar.selectedIndex, 0);
    expect(navigationBar.destinations, hasLength(5));
    expect(
      navigationBar.destinations.cast<NavigationDestination>().map(
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
    expect(reports.loadCalls, 0);

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(reports.loadCalls, 1);
    final reportsState = tester.state(find.byType(SavedOperationalReportsPage));

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(reports.loadCalls, 1);
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
      profile: const AppProfile(
        userId: 'admin',
        fullName: 'Admin',
        role: 'admin',
        email: 'admin@example.com',
      ),
      repository: auth,
      savedOperationalReportRepository: reports,
    ),
  ),
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
