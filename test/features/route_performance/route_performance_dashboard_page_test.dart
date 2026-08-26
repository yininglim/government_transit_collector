import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/admin_home/presentation/admin_home_page.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
import 'package:government_transit_collector/features/route_performance/presentation/route_performance_dashboard_page.dart';
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
    expect(
      find.textContaining('not yet enough complete trip coverage'),
      findsOneWidget,
    );
    expect(find.text('—'), findsNWidgets(3));
  });

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
  });

  testWidgets('Custom opens a date range picker', (tester) async {
    await pump(tester, FakeRepository(data: dataWithTrips()));
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
  });
}

Future<void> pump(
  WidgetTester tester,
  RoutePerformanceRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RoutePerformanceDashboardPage(
        repository: repository,
        now: () => DateTime.utc(2026, 8, 26, 4),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class FakeRepository implements RoutePerformanceRepository {
  FakeRepository({required this.data, this.fail = false});
  final RoutePerformanceData data;
  final bool fail;
  int loadCount = 0;
  Completer<RoutePerformanceData>? pending;

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
  Future<RoutePerformanceData> loadRoutePerformance({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    loadCount++;
    if (pending != null) return pending!.future;
    return data;
  }
}

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
