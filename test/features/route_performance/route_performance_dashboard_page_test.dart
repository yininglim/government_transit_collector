import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/admin_home/presentation/admin_home_page.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:government_transit_collector/features/route_performance/presentation/route_performance_dashboard_page.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report.dart';
import 'package:government_transit_collector/features/saved_operational_reports/data/saved_operational_report_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('admin home exposes the route performance navigation entry', (
    tester,
  ) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomePage(
          profile: const AppProfile(
            userId: 'admin',
            fullName: 'Admin',
            role: 'admin',
            email: 'admin@example.com',
          ),
          repository: AuthRepository(client: client),
          routePerformanceRepository: FakeRepository(data: dataWithTrips()),
        ),
      ),
    );
    await tester.tap(find.text('Route Performance Dashboard'));
    await tester.pumpAndSettle();
    expect(
      find.text('Based on collected realtime observations'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    client.dispose();
  });

  testWidgets('shows filters, metrics, coverage, trips, and partial reasons', (
    tester,
  ) async {
    await pump(tester, FakeRepository(data: dataWithTrips()));
    expect(find.text('J30'), findsWidgets);
    expect(find.text('Johor route'), findsWidgets);
    expect(find.text('Average Travel Time'), findsOneWidget);
    expect(find.text('Delay Frequency'), findsOneWidget);
    expect(find.text('Schedule Adherence'), findsOneWidget);
    expect(find.text('Route Efficiency'), findsNothing);
    expect(find.byKey(const Key('adherence-progress')), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.task_alt), findsOneWidget);
    expect(find.text('Historical Coverage'), findsOneWidget);
    expect(find.text('Limited historical coverage'), findsOneWidget);
    expect(find.text('On time'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reason: End not observed'), findsNothing);
    await tester.tap(find.text('Partial / insufficient trips (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('End not observed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows no-data state', (tester) async {
    await pump(
      tester,
      FakeRepository(
        data: const RoutePerformanceData(
          observations: [],
          schedulesByTripId: {},
        ),
      ),
    );
    expect(find.text('No historical data'), findsOneWidget);
  });

  testWidgets('shows partial-data state without fake metrics', (tester) async {
    final data = dataWithTrips(complete: false);
    await pump(tester, FakeRepository(data: data));
    expect(find.text('Insufficient trip coverage'), findsOneWidget);
    expect(find.text('Average Travel Time'), findsNothing);
    expect(find.text('Delay Frequency'), findsNothing);
    expect(find.text('Schedule Adherence'), findsNothing);
    expect(
      find.byKey(const Key('save-route-performance-report')),
      findsNothing,
    );
  });

  testWidgets('valid result exposes Save Report before observed trips', (
    tester,
  ) async {
    await pump(
      tester,
      FakeRepository(data: dataWithTrips()),
      savedRepository: FakeSavedReportRepository(),
    );
    expect(
      find.byKey(const Key('save-route-performance-report')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(find.byKey(const Key('route-performance-save-section')))
          .dy,
      lessThan(tester.getTopLeft(find.text('Observed trip performance')).dy),
    );
  });

  testWidgets('no observations does not expose Save Report', (tester) async {
    await pump(
      tester,
      FakeRepository(
        data: const RoutePerformanceData(
          observations: [],
          schedulesByTripId: {},
        ),
      ),
      savedRepository: FakeSavedReportRepository(),
    );
    expect(
      find.byKey(const Key('save-route-performance-report')),
      findsNothing,
    );
  });

  testWidgets('save dialog validates and stores the displayed result', (
    tester,
  ) async {
    final saved = FakeSavedReportRepository();
    await pump(
      tester,
      FakeRepository(data: dataWithTrips()),
      savedRepository: saved,
    );
    await openSaveDialog(tester);

    final title = tester.widget<TextField>(
      find.byKey(const Key('save-report-title')),
    );
    expect(title.controller!.text, 'J30 Route Performance - Today');

    await tester.enterText(find.byKey(const Key('save-report-title')), '  ');
    await tester.tap(
      find.byKey(const Key('confirm-save-route-performance-report')),
    );
    await tester.pump();
    expect(find.text('Report title is required.'), findsOneWidget);
    expect(saved.createCount, 0);

    await tester.enterText(
      find.byKey(const Key('save-report-title')),
      '  Morning Route Review  ',
    );
    await tester.tap(
      find.byKey(const Key('confirm-save-route-performance-report')),
    );
    await tester.pumpAndSettle();

    expect(saved.createCount, 1);
    expect(saved.routeId, 'route');
    expect(saved.routeName, 'J30 — Johor route');
    expect(saved.periodStart, DateTime.utc(2026, 8, 25, 16));
    expect(saved.periodEnd, DateTime.utc(2026, 8, 26, 16));
    expect(saved.title, 'Morning Route Review');
    expect(saved.notes, isNull);
    expect(saved.snapshot, {
      'average_travel_time_minutes': 30.0,
      'delay_frequency_percent': 0.0,
      'schedule_adherence_percent': 100.0,
      'total_observed_trip_occurrences': 2,
      'trips_used_in_metrics': 1,
      'partial_trip_occurrences': 1,
      'total_observations': 6,
      'delayed_trip_count': 0,
      'on_time_trip_count': 1,
    });
    expect(find.text('Route Performance report saved.'), findsOneWidget);
    expect(find.text('Average Travel Time'), findsOneWidget);
  });

  testWidgets('optional notes are stored and duplicate save taps are blocked', (
    tester,
  ) async {
    final saved = FakeSavedReportRepository()..pending = Completer<void>();
    await pump(
      tester,
      FakeRepository(data: dataWithTrips()),
      savedRepository: saved,
    );
    await openSaveDialog(tester);
    await tester.enterText(
      find.byKey(const Key('save-report-notes')),
      '  Review with operations  ',
    );
    final confirm = find.byKey(
      const Key('confirm-save-route-performance-report'),
    );
    await tester.tap(confirm);
    await tester.pump();
    expect(saved.createCount, 1);
    expect(saved.notes, 'Review with operations');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    saved.pending!.complete();
    await tester.pumpAndSettle();
    expect(saved.createCount, 1);
  });

  testWidgets(
    'save failure preserves analysis and shows retryable dialog error',
    (tester) async {
      final saved = FakeSavedReportRepository(fail: true);
      await pump(
        tester,
        FakeRepository(data: dataWithTrips()),
        savedRepository: saved,
      );
      await openSaveDialog(tester);
      await tester.tap(
        find.byKey(const Key('confirm-save-route-performance-report')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unable to save report for test.'), findsOneWidget);
      expect(find.text('Save Route Performance Report'), findsOneWidget);
      expect(find.text('Average Travel Time'), findsOneWidget);
      expect(saved.createCount, 1);
    },
  );

  testWidgets('refresh re-queries current collector data', (tester) async {
    final repository = FakeRepository(data: dataWithTrips());
    await pump(tester, repository);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(repository.loadCount, 2);
    expect(find.text('Updated 12:00 PM'), findsOneWidget);
  });

  testWidgets('refresh preserves data and shows subtle progress', (
    tester,
  ) async {
    final repository = FakeRepository(data: dataWithTrips());
    await pump(tester, repository);
    repository.pending = Completer<RoutePerformanceData>();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(find.byKey(const Key('refresh-progress')), findsOneWidget);
    expect(find.text('Average Travel Time'), findsOneWidget);
    repository.pending!.complete(dataWithTrips());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('refresh-progress')), findsNothing);
  });

  testWidgets('error offers retry', (tester) async {
    await pump(tester, FakeRepository(data: dataWithTrips(), fail: true));
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('landscape layout has no overflow', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, FakeRepository(data: dataWithTrips()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait 400x800 has no overflow', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, FakeRepository(data: dataWithTrips()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('delayed trip uses a labelled status chip', (tester) async {
    await pump(tester, FakeRepository(data: dataWithTrips(delayed: true)));
    await tester.scrollUntilVisible(find.text('Delayed').last, 300);
    expect(find.text('Delayed'), findsWidgets);
    expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
  });

  testWidgets('Today and 7 Days period controls reload the query', (
    tester,
  ) async {
    final repository = FakeRepository(data: dataWithTrips());
    await pump(tester, repository);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('7 Days'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
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
  });

  testWidgets('period availability keeps the selected route when possible', (
    tester,
  ) async {
    final repository = FakeRepository(
      data: dataWithTrips(),
      routesForRange: (_, end) =>
          end.difference(DateTime.utc(2026)).inDays > 230
          ? twoRoutes
          : twoRoutes,
    );
    await pump(tester, repository);
    await tester.tap(
      find.byType(DropdownButtonFormField<RoutePerformanceRoute>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('J50').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 Days'));
    await tester.pumpAndSettle();
    expect(repository.loadedRouteIds.last, 'other');
  });

  testWidgets(
    'period availability replaces a route that is no longer present',
    (tester) async {
      var request = 0;
      final repository = FakeRepository(
        data: dataWithTrips(),
        routesForRange: (_, _) =>
            request++ == 0 ? twoRoutes : [twoRoutes.first],
      );
      await pump(tester, repository);
      await tester.tap(
        find.byType(DropdownButtonFormField<RoutePerformanceRoute>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('J50').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('7 Days'));
      await tester.pumpAndSettle();
      expect(repository.loadedRouteIds.last, 'route');
      expect(find.text('J50'), findsNothing);
    },
  );

  testWidgets('no observed routes shows the period-wide empty state', (
    tester,
  ) async {
    await pump(
      tester,
      FakeRepository(data: dataWithTrips(), routesForRange: (_, _) => const []),
    );
    expect(find.text('No historical route data'), findsOneWidget);
    expect(find.byKey(const Key('no-historical-route-data')), findsOneWidget);
    expect(find.text('J30'), findsNothing);
  });

  testWidgets('refresh re-evaluates route availability', (tester) async {
    var request = 0;
    final repository = FakeRepository(
      data: dataWithTrips(),
      routesForRange: (_, _) =>
          request++ == 0 ? [twoRoutes.first] : [twoRoutes.last],
    );
    await pump(tester, repository);
    expect(repository.loadedRouteIds.last, 'route');

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(repository.loadedRouteIds.last, 'other');
    expect(find.text('J50'), findsWidgets);
    expect(find.text('J30'), findsNothing);
  });

  testWidgets('Custom opens a date range picker', (tester) async {
    await pump(tester, FakeRepository(data: dataWithTrips()));
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
  });

  testWidgets('Custom availability uses an inclusive selected end date', (
    tester,
  ) async {
    final repository = FakeRepository(data: dataWithTrips());
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
}

Future<void> pump(
  WidgetTester tester,
  RoutePerformanceRepository repository, {
  SavedOperationalReportRepository? savedRepository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RoutePerformanceDashboardPage(
        repository: repository,
        savedReportRepository: savedRepository,
        now: () => DateTime.utc(2026, 8, 26, 4),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openSaveDialog(WidgetTester tester) async {
  final button = find.byKey(const Key('save-route-performance-report'));
  await tester.drag(find.byType(ListView), const Offset(0, -900));
  await tester.pumpAndSettle();
  await tester.tap(button.hitTestable());
  await tester.pumpAndSettle();
  expect(find.text('Save Route Performance Report'), findsOneWidget);
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
  Future<SavedOperationalReport> createRoutePerformanceReport({
    required String routeId,
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
        'Unable to save report for test.',
      );
    }
    await pending?.future;
    return SavedOperationalReport(
      reportId: 'saved',
      adminId: 'admin',
      reportType: SavedOperationalReportType.routePerformance,
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

class FakeRepository
    implements RoutePerformanceRepository, PeriodRoutePerformanceRepository {
  FakeRepository({required this.data, this.fail = false, this.routesForRange});
  final RoutePerformanceData data;
  final bool fail;
  final List<RoutePerformanceRoute> Function(DateTime, DateTime)?
  routesForRange;
  int loadCount = 0;
  int availabilityCount = 0;
  Completer<RoutePerformanceData>? pending;
  final availabilityRanges = <(DateTime, DateTime)>[];
  final loadedRouteIds = <String>[];

  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() async {
    if (fail) throw const RoutePerformanceReadException('Load failed');
    return const [
      RoutePerformanceRoute(
        routeId: 'route',
        shortName: 'J30',
        longName: 'Johor route',
      ),
    ];
  }

  @override
  Future<List<RoutePerformanceRoute>> loadRoutesWithObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    if (fail) throw const RoutePerformanceReadException('Load failed');
    availabilityCount++;
    availabilityRanges.add((startUtc, endExclusiveUtc));
    return routesForRange?.call(startUtc, endExclusiveUtc) ?? [twoRoutes.first];
  }

  @override
  Future<RoutePerformanceData> loadRoutePerformance({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    loadCount++;
    loadedRouteIds.add(routeId);
    if (pending != null) return pending!.future;
    return data;
  }
}

const twoRoutes = [
  RoutePerformanceRoute(
    routeId: 'route',
    shortName: 'J30',
    longName: 'Johor route',
  ),
  RoutePerformanceRoute(
    routeId: 'other',
    shortName: 'J50',
    longName: 'Other route with a long description',
  ),
];

RoutePerformanceData dataWithTrips({
  bool complete = true,
  bool delayed = false,
}) {
  final start = DateTime.utc(2026, 8, 26, 0);
  final observations = [
    observation(start, 1, 103, 'bus'),
    observation(start.add(const Duration(minutes: 10)), 1.05, 103.05, 'bus'),
    observation(
      start.add(Duration(minutes: delayed ? 40 : 30)),
      complete ? 1.1 : 1.05,
      complete ? 103.1 : 103.05,
      'bus',
    ),
    if (complete) ...[
      observation(start, 1, 103, 'partial'),
      observation(
        start.add(const Duration(minutes: 10)),
        1.05,
        103.05,
        'partial',
      ),
      observation(
        start.add(const Duration(minutes: 20)),
        1.05,
        103.05,
        'partial',
      ),
    ],
  ];
  return RoutePerformanceData(
    observations: observations,
    schedulesByTripId: const {
      'trip': ScheduledTripReference(
        tripId: 'trip',
        startSeconds: 28800,
        endSeconds: 30600,
        startLatitude: 1,
        startLongitude: 103,
        endLatitude: 1.1,
        endLongitude: 103.1,
      ),
    },
  );
}

HistoricalVehicleObservation observation(
  DateTime time,
  double lat,
  double lon,
  String vehicle,
) => HistoricalVehicleObservation(
  routeId: 'route',
  tripId: 'trip',
  vehicleId: vehicle,
  recordedAt: time,
  latitude: lat,
  longitude: lon,
);
