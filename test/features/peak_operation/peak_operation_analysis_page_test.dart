import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/admin_home/presentation/admin_home_page.dart';
import 'package:government_transit_collector/features/authentication/data/auth_repository.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_repository.dart';
import 'package:government_transit_collector/features/peak_operation/presentation/peak_operation_analysis_page.dart';
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
  PeakOperationRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PeakOperationAnalysisPage(
        repository: repository,
        now: () => DateTime.utc(2026, 8, 26, 4),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> selectScope(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('peak-scope-selector')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class FakeRepository
    implements PeakOperationRepository, PeriodPeakOperationRepository {
  FakeRepository({required this.rows, this.routesForRange});
  final List<PeakOperationObservation> rows;
  final List<PeakOperationRoute> Function(DateTime, DateTime)? routesForRange;
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
