import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/admin_home/presentation/admin_home_page.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_repository.dart';
import 'package:government_transit_collector/features/peak_operation/presentation/peak_operation_analysis_page.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('admin home exposes Peak Operation Analysis', (tester) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomePage(
          profile: const AppProfile(
            userId: 'a',
            fullName: 'Admin',
            role: 'admin',
            email: null,
          ),
          repository: AuthRepository(client: client),
          peakOperationRepository: FakeRepository(rows: activityRows()),
        ),
      ),
    );
    await tester.tap(find.text('Peak Operation Analysis'));
    await tester.pumpAndSettle();
    expect(find.text('Observed bus operational activity'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
  });

  testWidgets('shows scope, metrics, chart, insight, coverage, and warning', (
    tester,
  ) async {
    await pump(tester, FakeRepository(rows: activityRows()));
    expect(find.text('All Routes'), findsOneWidget);
    expect(find.text('Peak Period'), findsOneWidget);
    expect(find.text('Average Active Trips'), findsOneWidget);
    expect(find.text('Observed Service Window'), findsOneWidget);
    expect(find.text('Busiest Observed Route'), findsOneWidget);
    expect(find.text('Operational Activity by Time'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Daily Activity'), findsOneWidget);
    expect(find.text('Operational Insight'), findsOneWidget);
    expect(find.text('Historical Coverage'), findsOneWidget);
    expect(find.text('Limited historical coverage'), findsOneWidget);
    expect(find.textContaining('passenger demand'), findsNothing);
  });

  testWidgets('valid result exposes Save Report before detailed activity', (
    tester,
  ) async {
    await pump(
      tester,
      FakeRepository(rows: activityRows()),
      savedRepository: FakeSavedReportRepository(),
    );
    expect(find.byKey(const Key('save-peak-operation-report')), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(const Key('peak-operation-save-section')))
          .dy,
      lessThan(tester.getTopLeft(find.text('Operational Activity by Time')).dy),
    );
  });

  testWidgets('invalid and no-data results do not expose Save Report', (
    tester,
  ) async {
    await pump(tester, FakeRepository(rows: const []));
    expect(find.byKey(const Key('save-peak-operation-report')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester, FakeRepository(rows: [activityRows().first]));
    expect(find.byKey(const Key('save-peak-operation-report')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester, FakeRepository(rows: activityRows(), fail: true));
    expect(
      find.textContaining('Unable to load peak analysis for test.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('save-peak-operation-report')), findsNothing);
  });

  testWidgets('All Routes dialog validates and saves displayed snapshot', (
    tester,
  ) async {
    final saved = FakeSavedReportRepository();
    await pump(
      tester,
      FakeRepository(rows: activityRows()),
      savedRepository: saved,
    );
    await openSaveDialog(tester);
    final title = tester.widget<TextField>(
      find.byKey(const Key('save-peak-report-title')),
    );
    expect(title.controller!.text, 'All Routes Peak Operation - Today');

    await tester.enterText(
      find.byKey(const Key('save-peak-report-title')),
      ' ',
    );
    await tester.tap(
      find.byKey(const Key('confirm-save-peak-operation-report')),
    );
    await tester.pump();
    expect(find.text('Report title is required.'), findsOneWidget);
    expect(saved.createCount, 0);

    await tester.enterText(
      find.byKey(const Key('save-peak-report-title')),
      '  Network peak review  ',
    );
    await tester.tap(
      find.byKey(const Key('confirm-save-peak-operation-report')),
    );
    await tester.pumpAndSettle();
    expect(saved.createCount, 1);
    expect(saved.routeId, isNull);
    expect(saved.routeName, 'All Routes');
    expect(saved.periodStart, DateTime.utc(2026, 8, 25, 16));
    expect(saved.periodEnd, DateTime.utc(2026, 8, 26, 16));
    expect(saved.title, 'Network peak review');
    expect(saved.notes, isNull);
    expect(saved.snapshot, containsPair('peak_period', '8:00 AM – 8:30 AM'));
    expect(saved.snapshot, containsPair('peak_average_active_trips', 1.5));
    expect(saved.snapshot, containsPair('total_observations', 6));
    expect(saved.snapshot, containsPair('distinct_trip_occurrences', 5));
    expect(saved.snapshot, containsPair('populated_bucket_count', 3));
    expect(saved.snapshot, containsPair('busiest_route_id', 'A'));
    expect(find.text('Peak Operation report saved.'), findsOneWidget);
    expect(find.text('Peak Period'), findsOneWidget);
  });

  testWidgets('specific route save stores route scope and current period', (
    tester,
  ) async {
    final saved = FakeSavedReportRepository();
    await pump(
      tester,
      FakeRepository(rows: activityRows()),
      savedRepository: saved,
    );
    await selectScope(tester, 'J15 — Friendly route');
    await tester.tap(find.text('7 Days'));
    await tester.pumpAndSettle();
    await openSaveDialog(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('save-peak-report-title')))
          .controller!
          .text,
      'J15 Peak Operation - 7 Days',
    );
    await tester.tap(
      find.byKey(const Key('confirm-save-peak-operation-report')),
    );
    await tester.pumpAndSettle();
    expect(saved.createCount, 1);
    expect(saved.routeId, 'A');
    expect(saved.routeName, 'J15 — Friendly route');
    expect(saved.periodStart, DateTime.utc(2026, 8, 19, 16));
    expect(saved.periodEnd, DateTime.utc(2026, 8, 26, 16));
  });

  testWidgets('duplicate save is blocked and failure preserves analysis', (
    tester,
  ) async {
    final pending = FakeSavedReportRepository()..pending = Completer<void>();
    await pump(
      tester,
      FakeRepository(rows: activityRows()),
      savedRepository: pending,
    );
    await openSaveDialog(tester);
    final confirm = find.byKey(const Key('confirm-save-peak-operation-report'));
    await tester.tap(confirm);
    await tester.pump();
    expect(pending.createCount, 1);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    pending.pending!.complete();
    await tester.pumpAndSettle();

    final failing = FakeSavedReportRepository(fail: true);
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(
      tester,
      FakeRepository(rows: activityRows()),
      savedRepository: failing,
    );
    await openSaveDialog(tester);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Unable to save peak report for test.'), findsOneWidget);
    expect(find.text('Save Peak Operation Report'), findsOneWidget);
    expect(find.text('Peak Period'), findsOneWidget);
  });

  testWidgets('specific route selection applies route filter', (tester) async {
    final repository = FakeRepository(rows: activityRows());
    await pump(tester, repository);
    await tester.tap(find.byKey(const Key('peak-scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('J15 — Friendly route').last);
    await tester.pumpAndSettle();
    expect(repository.lastRoute, 'A');
    expect(find.text('Peak Activity'), findsOneWidget);
  });

  testWidgets('Today, 7 Days, and Custom controls work', (tester) async {
    final repository = FakeRepository(rows: activityRows());
    await pump(tester, repository);
    expect(find.text('Today'), findsOneWidget);
    await tester.tap(find.text('7 Days'));
    await tester.pumpAndSettle();
    expect(repository.loadCount, 2);
    expect(repository.availabilityCount, 2);
    expect(
      repository.availabilityRanges.last.$1,
      DateTime.utc(2026, 8, 19, 16),
    );
    expect(
      repository.availabilityRanges.last.$2,
      DateTime.utc(2026, 8, 26, 16),
    );
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
  });

  testWidgets('refresh preserves filters and shows progress then timestamp', (
    tester,
  ) async {
    final repository = FakeRepository(rows: activityRows());
    await pump(tester, repository);
    repository.pending = Completer<List<PeakOperationObservation>>();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(find.byKey(const Key('peak-refresh-progress')), findsOneWidget);
    expect(find.text('Peak Period'), findsOneWidget);
    repository.pending!.complete(activityRows());
    await tester.pumpAndSettle();
    expect(find.text('Updated 12:00 PM'), findsOneWidget);
  });

  testWidgets('handles no-data and limited-data states', (tester) async {
    await pump(tester, FakeRepository(rows: const []));
    expect(find.text('No operational history'), findsOneWidget);
    expect(find.text('All Routes'), findsNothing);
    expect(find.text('No routes with data'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester, FakeRepository(rows: [activityRows().first]));
    expect(find.text('Limited operational history'), findsOneWidget);
    expect(find.text('Peak Period'), findsNothing);
  });

  testWidgets('scope contains All Routes and only observed routes', (
    tester,
  ) async {
    await pump(
      tester,
      FakeRepository(
        rows: activityRows(),
        routesForRange: (_, _) => [peakRoutes.first],
      ),
    );
    await tester.tap(find.byKey(const Key('peak-scope-selector')));
    await tester.pumpAndSettle();
    expect(find.text('All Routes'), findsWidgets);
    expect(find.text('J15 — Friendly route'), findsWidgets);
    expect(find.text('J30 — Second route'), findsNothing);
  });

  testWidgets('period change preserves an available specific route', (
    tester,
  ) async {
    final repository = FakeRepository(
      rows: activityRows(),
      routesForRange: (_, _) => peakRoutes,
    );
    await pump(tester, repository);
    await selectScope(tester, 'J15 — Friendly route');
    await tester.tap(find.text('7 Days'));
    await tester.pumpAndSettle();
    expect(repository.lastRoute, 'A');
  });

  testWidgets('period change falls back to All Routes when route disappears', (
    tester,
  ) async {
    var request = 0;
    final repository = FakeRepository(
      rows: activityRows(),
      routesForRange: (_, _) => request++ == 0 ? peakRoutes : [peakRoutes.last],
    );
    await pump(tester, repository);
    await selectScope(tester, 'J15 — Friendly route');
    await tester.tap(find.text('7 Days'));
    await tester.pumpAndSettle();
    expect(repository.lastRoute, isNull);
    expect(find.text('All Routes'), findsOneWidget);
    expect(find.text('J15 — Friendly route'), findsNothing);
  });

  testWidgets('refresh re-evaluates scope availability', (tester) async {
    var request = 0;
    final repository = FakeRepository(
      rows: activityRows(),
      routesForRange: (_, _) => request++ == 0 ? peakRoutes : [peakRoutes.last],
    );
    await pump(tester, repository);
    await selectScope(tester, 'J15 — Friendly route');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(repository.lastRoute, isNull);
    expect(repository.availabilityCount, 2);
  });

  testWidgets('Custom availability uses the inclusive selected end date', (
    tester,
  ) async {
    final repository = FakeRepository(rows: activityRows());
    await pump(tester, repository);
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20').last);
    await tester.tap(find.text('22').last);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      repository.availabilityRanges.last.$1,
      DateTime.utc(2026, 8, 19, 16),
    );
    expect(
      repository.availabilityRanges.last.$2,
      DateTime.utc(2026, 8, 22, 16),
    );
  });

  for (final size in [const Size(400, 800), const Size(800, 400)]) {
    testWidgets('renders without overflow at ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, FakeRepository(rows: activityRows()));
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> pump(
  WidgetTester tester,
  PeakOperationRepository repository, {
  SavedOperationalReportRepository? savedRepository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PeakOperationAnalysisPage(
        repository: repository,
        savedReportRepository: savedRepository,
        now: () => DateTime.utc(2026, 8, 26, 4),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openSaveDialog(WidgetTester tester) async {
  final button = find.byKey(const Key('save-peak-operation-report'));
  await tester.tap(button.hitTestable());
  await tester.pumpAndSettle();
  expect(find.text('Save Peak Operation Report'), findsOneWidget);
}

class FakeSavedReportRepository implements SavedOperationalReportRepository {
  FakeSavedReportRepository({this.fail = false});
  final bool fail;
  Completer<void>? pending;
  int createCount = 0;
  String? routeId;
  String? routeName;
  DateTime? periodStart;
  DateTime? periodEnd;
  String? title;
  String? notes;
  Map<String, dynamic>? snapshot;

  @override
  Future<SavedOperationalReport> createPeakOperationReport({
    required String? routeId,
    required String routeNameSnapshot,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String title,
    required String? adminNotes,
    required Map<String, dynamic> resultSnapshot,
  }) async {
    createCount++;
    this.routeId = routeId;
    routeName = routeNameSnapshot;
    this.periodStart = periodStart;
    this.periodEnd = periodEnd;
    this.title = title;
    notes = adminNotes;
    snapshot = resultSnapshot;
    if (fail) {
      throw const SavedOperationalReportException(
        'Unable to save peak report for test.',
      );
    }
    await pending?.future;
    return SavedOperationalReport(
      reportId: 'peak',
      adminId: 'admin',
      reportType: SavedOperationalReportType.peakOperation,
      routeId: routeId,
      routeNameSnapshot: routeNameSnapshot,
      periodStart: periodStart,
      periodEnd: periodEnd,
      title: title,
      resultSnapshot: resultSnapshot,
      adminNotes: adminNotes,
      status: SavedOperationalReportStatus.draft,
      createdAt: DateTime.utc(2026, 8, 26),
      updatedAt: DateTime.utc(2026, 8, 26),
    );
  }

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
  Future<List<SavedOperationalReport>> loadReports() =>
      throw UnimplementedError();
  @override
  Future<SavedOperationalReport> updateManagementMetadata({
    required String reportId,
    required String title,
    required String? adminNotes,
    required SavedOperationalReportStatus status,
  }) => throw UnimplementedError();
}

Future<void> selectScope(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('peak-scope-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class FakeRepository
    implements PeakOperationRepository, PeriodPeakOperationRepository {
  FakeRepository({required this.rows, this.routesForRange, this.fail = false});
  final List<PeakOperationObservation> rows;
  final List<PeakOperationRoute> Function(DateTime, DateTime)? routesForRange;
  final bool fail;
  int loadCount = 0;
  int availabilityCount = 0;
  String? lastRoute;
  Completer<List<PeakOperationObservation>>? pending;
  final availabilityRanges = <(DateTime, DateTime)>[];

  @override
  Future<List<PeakOperationRoute>> loadRoutes() async => peakRoutes;

  @override
  Future<List<PeakOperationRoute>> loadRoutesWithObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    if (fail) throw Exception('Unable to load peak analysis for test.');
    availabilityCount++;
    availabilityRanges.add((startUtc, endExclusiveUtc));
    if (routesForRange case final resolver?) {
      return resolver(startUtc, endExclusiveUtc);
    }
    final observedIds = rows.map((row) => row.routeId).toSet();
    return peakRoutes
        .where((route) => observedIds.contains(route.routeId))
        .toList();
  }

  @override
  Future<List<PeakOperationObservation>> loadObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    String? routeId,
  }) async {
    loadCount++;
    lastRoute = routeId;
    if (pending != null) return pending!.future;
    return rows
        .where((row) => routeId == null || row.routeId == routeId)
        .toList();
  }
}

const peakRoutes = [
  PeakOperationRoute(
    routeId: 'A',
    shortName: 'J15',
    longName: 'Friendly route',
  ),
  PeakOperationRoute(routeId: 'B', shortName: 'J30', longName: 'Second route'),
];

List<PeakOperationObservation> activityRows() => [
  item(DateTime.utc(2026, 8, 26, 0, 1), 'A', 'one'),
  item(DateTime.utc(2026, 8, 26, 0, 5), 'A', 'two'),
  item(DateTime.utc(2026, 8, 26, 0, 31), 'A', 'one'),
  item(DateTime.utc(2026, 8, 26, 1, 1), 'B', 'three'),
  item(DateTime.utc(2026, 8, 27, 0, 2), 'A', 'four'),
  item(DateTime.utc(2026, 8, 27, 0, 35), 'B', 'five'),
];

PeakOperationObservation item(DateTime time, String route, String trip) =>
    PeakOperationObservation(
      routeId: route,
      tripId: trip,
      vehicleId: 'bus-$trip',
      recordedAt: time,
    );
