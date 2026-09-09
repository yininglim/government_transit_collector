import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/johor_bahru_boundary_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/route_bus_stop_recommendation_page.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

void main() {
  test('screens with the backend gate and stable route ordering', () async {
    final routes = [route('B'), route('A'), route('C')];
    final evidenceRepository = FakeEvidenceRepository({
      'A': evidence('A'),
      'B': evidence('B', stopCount: 1),
      'C': evidence('C'),
    });
    final recommendationRepository = FakeRecommendationRepository();
    final coordinator = RouteStopDashboardCoordinator(
      routeRepository: FakeRouteRepository(routes),
      evidenceRepository: evidenceRepository,
      recommendationRepository: recommendationRepository,
    );

    final screened = await coordinator.screenCandidates(
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );

    expect(screened.map((item) => item.route.routeId), ['A', 'C']);
    expect(recommendationRepository.routeIds, isEmpty);
    expect(evidenceRepository.periods, everyElement((periodStart, periodEnd)));
  });

  test(
    'screening retains deterministic exclusions and load failures',
    () async {
      final coordinator = RouteStopDashboardCoordinator(
        routeRepository: FakeRouteRepository([
          route('A'),
          route('B'),
          route('C'),
        ]),
        evidenceRepository: FakeEvidenceRepository({
          'A': evidence('A'),
          'B': evidence('B', stopCount: 1),
        }),
        recommendationRepository: FakeRecommendationRepository(),
      );

      final result = await coordinator.screenRoutes(
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      expect(result.routesAnalysed, 3);
      expect(result.candidates.single.route.routeId, 'A');
      expect(result.excludedRoutes.map((item) => item.route.routeId), [
        'B',
        'C',
      ]);
      expect(result.excludedRoutes.map((item) => item.reason), [
        RouteStopDashboardExclusionReason.unusableTripStructure,
        RouteStopDashboardExclusionReason.evidenceLoadingFailure,
      ]);
      expect(result.excludedRoutes.first.evidence, isNotNull);
      expect(result.excludedRoutes.last.evidence, isNull);
    },
  );

  test('caps batches at three with recommendation concurrency two', () async {
    final recommendationRepository = FakeRecommendationRepository();
    final coordinator = RouteStopDashboardCoordinator(
      routeRepository: FakeRouteRepository(const []),
      evidenceRepository: FakeEvidenceRepository(const {}),
      recommendationRepository: recommendationRepository,
    );
    final batchCandidates = candidates(4);

    await coordinator.analyseBatch(
      candidates: batchCandidates,
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );

    expect(recommendationRepository.routeIds, ['R1', 'R2', 'R3']);
    expect(recommendationRepository.maximumConcurrentCalls, 2);
    expect(recommendationRepository.evidence, [
      batchCandidates[0].evidence,
      batchCandidates[1].evidence,
      batchCandidates[2].evidence,
    ]);
  });

  testWidgets('entry prepares evidence and map without Gemini', (tester) async {
    final coordinator = FakeDashboardCoordinator(
      candidates: [
        RouteStopDashboardCandidate(
          route: route('R1'),
          evidence: evidence(
            'R1',
            includeShape: true,
            includeDistanceAndSpacing: true,
          ),
        ),
      ],
    );
    await pumpDashboard(tester, coordinator);
    await tester.pumpAndSettle();

    expect(coordinator.analysisRouteIds, isEmpty);
    expect(
      find.byKey(const Key('route-stop-evidence-overview')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('existing-network-map')), findsOneWidget);
    expect(find.byKey(const Key('existing-route-shape')), findsOneWidget);
    expect(
      find.byKey(const Key('existing-stop-marker-stop-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('existing-stop-marker-stop-b')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('generate-ai-recommendation')), findsOneWidget);
  });

  testWidgets('coverage uses Available Limited and Missing states', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(
      candidates: [
        RouteStopDashboardCandidate(
          route: route('R1'),
          evidence: evidence('R1', secondCoordinateAvailable: false),
        ),
      ],
    );
    await pumpDashboard(tester, coordinator);
    await tester.pumpAndSettle();

    expect(find.text('Available'), findsWidgets);
    expect(find.text('Limited'), findsWidgets);
    expect(find.text('Missing'), findsWidgets);
  });

  testWidgets('limited routes remain separate from AI results', (tester) async {
    final excluded = RouteStopDashboardExcludedRoute(
      route: route('LIMITED'),
      reason: RouteStopDashboardExclusionReason.unusableTripStructure,
      evidence: evidence('LIMITED', stopCount: 1),
    );
    final coordinator = FakeDashboardCoordinator(
      candidates: candidates(1),
      excludedRoutes: [excluded],
    );
    await pumpDashboard(tester, coordinator);
    await tester.pumpAndSettle();
    final view = find.byKey(const Key('view-limited-routes'));
    await tester.ensureVisible(view);
    await tester.pumpAndSettle();
    await tester.tap(view);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('limited-routes-details')), findsOneWidget);
    expect(find.text('LIMITED'), findsOneWidget);
    expect(find.textContaining('at least two ordered stops'), findsOneWidget);
    expect(coordinator.analysisRouteIds, isEmpty);
    expect(find.byKey(const Key('route-result-LIMITED')), findsNothing);
  });

  testWidgets('route selection updates retained deterministic map only', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(candidates: candidates(2));
    await pumpDashboard(tester, coordinator);
    await tester.pumpAndSettle();
    expect(find.text('R1'), findsWidgets);
    final selector = find.byKey(const Key('route-map-selector'));
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('R2').last);
    await tester.pumpAndSettle();

    expect(find.text('R2'), findsWidgets);
    expect(
      find.byKey(const ValueKey('existing-network-map-R2')),
      findsOneWidget,
    );
    expect(coordinator.analysisRouteIds, isEmpty);
  });

  testWidgets('missing stop coordinates never create markers', (tester) async {
    final coordinator = FakeDashboardCoordinator(
      candidates: [
        RouteStopDashboardCandidate(
          route: route('R1'),
          evidence: evidence('R1', secondCoordinateAvailable: false),
        ),
      ],
    );
    await pumpDashboard(tester, coordinator);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('existing-stop-marker-stop-a')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('existing-stop-marker-stop-b')), findsNothing);
    expect(
      find.textContaining('1 stop occurrences cannot be mapped'),
      findsOneWidget,
    );
  });

  testWidgets('deterministic View Evidence makes zero Gemini calls', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(candidates: candidates(1));
    await pumpDashboard(tester, coordinator);
    await tester.pumpAndSettle();
    final view = find.byKey(const Key('view-route-stop-evidence'));
    await tester.ensureVisible(view);
    await tester.pumpAndSettle();
    await tester.tap(view);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('deterministic-evidence-R1')), findsOneWidget);
    final details = find.byKey(const Key('deterministic-evidence-R1'));
    final detailsScrollable = find.descendant(
      of: details,
      matching: find.byType(Scrollable),
    );
    for (final section in [
      'route-structure',
      'stop-coverage',
      'distance-spacing',
      'operational-evidence',
      'feedback',
      'limitations',
    ]) {
      final sectionFinder = find.byKey(Key('evidence-section-$section'));
      await tester.scrollUntilVisible(
        sectionFinder,
        160,
        scrollable: detailsScrollable,
      );
      expect(sectionFinder, findsOneWidget);
    }
    expect(coordinator.analysisRouteIds, isEmpty);
  });

  testWidgets(
    'shows fixed period and waits for an intentional analysis action',
    (tester) async {
      final coordinator = FakeDashboardCoordinator(candidates: const []);
      await pumpDashboard(tester, coordinator);

      expect(find.text('Past 30 Days'), findsOneWidget);
      expect(find.byKey(const Key('analyse-routes')), findsOneWidget);
      expect(find.byType(DropdownButtonFormField), findsNothing);
      expect(find.text('Today'), findsNothing);
      expect(find.text('Custom'), findsNothing);
      expect(coordinator.analysisRouteIds, isEmpty);

      await tapAnalyse(tester);
      await tester.pumpAndSettle();

      expect(coordinator.analysisRouteIds, isEmpty);
      expect(find.text('No eligible routes'), findsOneWidget);
      expect(coordinator.screenStartUtc, periodStart);
      expect(coordinator.screenEndUtc, periodEnd);
    },
  );

  testWidgets(
    'retains first batch and analyses remaining routes only on demand',
    (tester) async {
      final coordinator = FakeDashboardCoordinator(candidates: candidates(4));
      await pumpDashboard(tester, coordinator);
      await tapAnalyse(tester);
      await tester.pumpAndSettle();

      expect(coordinator.analysisRouteIds, ['R1', 'R2', 'R3']);
      expect(find.byKey(const Key('route-result-R1')), findsOneWidget);
      await reveal(tester, find.byKey(const Key('route-result-R3')));
      expect(find.byKey(const Key('route-result-R3')), findsOneWidget);
      expect(find.byKey(const Key('route-result-R4')), findsNothing);
      expect(find.byKey(const Key('analyse-next-routes')), findsOneWidget);
      await tester.pump();
      expect(coordinator.analysisRouteIds.length, 3);

      await tester.ensureVisible(find.byKey(const Key('analyse-next-routes')));
      await tester.tap(find.byKey(const Key('analyse-next-routes')));
      await tester.pumpAndSettle();

      expect(coordinator.analysisRouteIds, ['R1', 'R2', 'R3', 'R4']);
      await reveal(
        tester,
        find.byKey(const Key('route-result-R1')),
        delta: -300,
      );
      expect(find.byKey(const Key('route-result-R1')), findsOneWidget);
      await reveal(tester, find.byKey(const Key('route-result-R4')));
      expect(find.byKey(const Key('route-result-R4')), findsOneWidget);
    },
  );

  testWidgets(
    'renders every action, failures, and candidate-area evidence safely',
    (tester) async {
      final items = candidates(6);
      final coordinator = FakeDashboardCoordinator(
        candidates: items,
        results: {
          'R1': result(RouteStopRecommendationAction.routeImprovement),
          'R2': result(RouteStopRecommendationAction.stopImprovement),
          'R3': result(RouteStopRecommendationAction.additionalStopCoverage),
          'R4': result(
            RouteStopRecommendationAction.maintainCurrentConfiguration,
          ),
          'R5': result(RouteStopRecommendationAction.insufficientEvidence),
          'R6': unavailable(),
        },
      );
      await pumpDashboard(tester, coordinator);
      await tapAnalyse(tester);
      await tester.pumpAndSettle();

      expect(find.text('Route Improvement'), findsOneWidget);
      await reveal(tester, find.text('Bus Stop Improvement'));
      expect(find.text('Bus Stop Improvement'), findsOneWidget);
      await reveal(tester, find.text('Additional Stop Coverage'));
      expect(find.text('Additional Stop Coverage'), findsOneWidget);
      expect(
        find.text('Suggested Area for Further Evaluation'),
        findsOneWidget,
      );
      expect(find.text('Between Stop A and Stop B'), findsOneWidget);
      expect(find.text('Evaluate the existing stop gap.'), findsOneWidget);
      expect(find.textContaining('latitude'), findsNothing);
      expect(find.textContaining('longitude'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('analyse-next-routes')));
      await tester.tap(find.byKey(const Key('analyse-next-routes')));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Maintain Current Configuration'));
      expect(find.text('Maintain Current Configuration'), findsOneWidget);
      await reveal(tester, find.text('Insufficient Evidence'));
      expect(find.text('Insufficient Evidence'), findsOneWidget);
      await reveal(tester, find.text('Recommendation Temporarily Unavailable'));
      expect(
        find.text('Recommendation Temporarily Unavailable'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'details use the stored result without another recommendation call',
    (tester) async {
      final coordinator = FakeDashboardCoordinator(
        candidates: candidates(1),
        results: {
          'R1': result(RouteStopRecommendationAction.additionalStopCoverage),
        },
      );
      await pumpDashboard(tester, coordinator);
      await tapAnalyse(tester);
      await tester.pumpAndSettle();
      final calls = coordinator.analysisRouteIds.length;

      await reveal(tester, find.byKey(const Key('view-details-R1')));
      await tester.tap(find.byKey(const Key('view-details-R1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recommendation-details')), findsOneWidget);
      expect(find.text('Rationale'), findsOneWidget);
      await revealDetails(tester, find.text('Supporting Evidence'));
      expect(find.text('Supporting Evidence'), findsOneWidget);
      await revealDetails(tester, find.text('Limitations'));
      expect(find.text('Limitations'), findsOneWidget);
      await revealDetails(tester, find.textContaining('network.trip.0'));
      expect(find.textContaining('network.trip.0'), findsOneWidget);
      await revealDetails(tester, find.textContaining('Stop A (stop-a)'));
      expect(find.textContaining('Stop A (stop-a)'), findsOneWidget);
      expect(find.textContaining('Stop B (stop-b)'), findsOneWidget);
      expect(coordinator.analysisRouteIds.length, calls);
    },
  );

  testWidgets(
    'disables controls during analysis and rebuild does not duplicate calls',
    (tester) async {
      final gate = Completer<void>();
      final coordinator = FakeDashboardCoordinator(
        candidates: candidates(1),
        analysisGate: gate,
      );
      await pumpDashboard(tester, coordinator);
      await tapAnalyse(tester);
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('analyse-routes')),
      );
      expect(button.onPressed, isNull);
      expect(find.byKey(const Key('analysis-progress')), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: RouteBusStopRecommendationPage(
            coordinator: coordinator,
            now: fixedNow,
          ),
        ),
      );
      await tester.pump();
      expect(coordinator.analysisRouteIds, isEmpty);

      gate.complete();
      await tester.pumpAndSettle();
      expect(coordinator.analysisRouteIds, ['R1']);
    },
  );

  testWidgets('duplicate Generate taps start one existing batch', (
    tester,
  ) async {
    final gate = Completer<void>();
    final coordinator = FakeDashboardCoordinator(
      candidates: candidates(1),
      analysisGate: gate,
    );
    await pumpDashboard(tester, coordinator);
    await tester.pumpAndSettle();
    final generate = find.byKey(const Key('generate-ai-recommendation'));
    await tester.ensureVisible(generate);
    await tester.pumpAndSettle();
    await tester.tap(generate);
    await tester.pump();
    await tester.tap(generate);
    await tester.pump();
    expect(coordinator.analyseBatchCalls, 1);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('revisit restores screening and map selection without calls', (
    tester,
  ) async {
    final session = RouteStopDashboardSession();
    final coordinator = FakeDashboardCoordinator(candidates: candidates(2));
    await pumpDashboard(tester, coordinator, session: session);
    await tester.pumpAndSettle();
    final selector = find.byKey(const Key('route-map-selector'));
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('R2').last);
    await tester.pumpAndSettle();
    expect(coordinator.screenCalls, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await pumpDashboard(tester, coordinator, session: session);
    await tester.pumpAndSettle();

    expect(coordinator.screenCalls, 1);
    expect(coordinator.analysisRouteIds, isEmpty);
    expect(
      find.byKey(const ValueKey('existing-network-map-R2')),
      findsOneWidget,
    );
  });

  testWidgets('Start New Analysis clears stale recommendations', (
    tester,
  ) async {
    final session = RouteStopDashboardSession();
    final coordinator = FakeDashboardCoordinator(candidates: candidates(1));
    await pumpDashboard(tester, coordinator, session: session);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(session.entries, isNotEmpty);
    final restart = find.byKey(const Key('analyse-routes'));
    await tester.ensureVisible(restart);
    await tester.pumpAndSettle();
    await tester.tap(restart);
    await tester.pumpAndSettle();
    expect(session.entries, isEmpty);
    expect(coordinator.screenCalls, 2);
    expect(coordinator.analysisRouteIds, ['R1']);
  });

  testWidgets(
    'portrait and short landscape remain scrollable without overflow',
    (tester) async {
      for (final size in [const Size(320, 640), const Size(900, 320)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final coordinator = FakeDashboardCoordinator(
          candidates: [
            RouteStopDashboardCandidate(
              route: const RoutePerformanceRoute(
                routeId: 'LONG',
                shortName:
                    'A very long existing route name that must wrap safely',
                longName: 'Additional deterministic route description',
              ),
              evidence: evidence(
                'LONG',
                secondCoordinateAvailable: false,
                includeShape: true,
              ),
            ),
          ],
        );
        await pumpDashboard(tester, coordinator);
        await tester.pumpAndSettle();
        expect(find.byType(ListView), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'a failed route remains beside successes and retry targets only it',
    (tester) async {
      final coordinator = FakeDashboardCoordinator(
        candidates: candidates(2),
        results: {
          'R1': result(RouteStopRecommendationAction.routeImprovement),
          'R2': unavailable(),
        },
      );
      await pumpDashboard(tester, coordinator);
      await tapAnalyse(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('route-result-R1')), findsOneWidget);
      await reveal(tester, find.byKey(const Key('route-result-R2')));
      expect(find.byKey(const Key('route-result-R2')), findsOneWidget);
      expect(coordinator.retryRouteIds, isEmpty);
      await reveal(tester, find.byKey(const Key('retry-R2')));
      await tester.tap(find.byKey(const Key('retry-R2')));
      await tester.pumpAndSettle();
      expect(coordinator.retryRouteIds, ['R2']);
      expect(coordinator.analysisRouteIds, ['R1', 'R2']);

      for (final text in [
        'Passenger demand',
        'Occupancy',
        'Capacity',
        'Construction feasibility',
        'Build Here',
        'Confirmed New Stop',
      ]) {
        expect(find.textContaining(text), findsNothing);
      }
    },
  );

  testWidgets('recreated page restores route and stop results', (tester) async {
    final session = RouteStopDashboardSession();
    final retainedCandidates = candidates(1);
    final coordinator = FakeDashboardCoordinator(
      candidates: retainedCandidates,
    );
    await pumpDashboard(tester, coordinator, session: session);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(coordinator.analysisRouteIds, ['R1']);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    await pumpDashboard(tester, coordinator, session: session);

    expect(find.byKey(const Key('route-result-R1')), findsOneWidget);
    expect(coordinator.analysisRouteIds, ['R1']);
    expect(
      session.candidates.single.evidence,
      same(retainedCandidates.single.evidence),
    );
  });
}

Future<void> pumpDashboard(
  WidgetTester tester,
  RouteStopDashboardCoordinator coordinator, {
  RouteStopDashboardSession? session,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RouteBusStopRecommendationPage(
        session: session,
        coordinator: coordinator,
        now: fixedNow,
      ),
    ),
  );
  await tester.pump();
}

Future<void> tapAnalyse(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final generate = find.byKey(const Key('generate-ai-recommendation'));
  if (generate.evaluate().isEmpty) return;
  await tester.ensureVisible(generate);
  await tester.pumpAndSettle();
  await tester.tap(generate);
  await tester.pump();
}

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> revealDetails(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(
      of: find.byKey(const Key('recommendation-details')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pump();
}

DateTime fixedNow() => DateTime.utc(2026, 8, 28, 4);
final periodStart = DateTime.utc(2026, 7, 29, 16);
final periodEnd = DateTime.utc(2026, 8, 28, 16);

RoutePerformanceRoute route(String id) =>
    RoutePerformanceRoute(routeId: id, shortName: id, longName: null);

List<RouteStopDashboardCandidate> candidates(int count) =>
    List.generate(count, (index) {
      final id = 'R${index + 1}';
      return RouteStopDashboardCandidate(
        route: route(id),
        evidence: evidence(id),
      );
    });

DistrictRouteStopEvidence evidence(
  String routeId, {
  int stopCount = 2,
  bool secondCoordinateAvailable = true,
  bool includeShape = false,
  bool includeDistanceAndSpacing = false,
}) {
  final routeValue = route(routeId);
  final stops = [
    const AiRouteStopEvidence(
      stopId: 'stop-a',
      stopName: 'Stop A',
      stopSequence: 1,
      coordinate: MapCoordinate(1.49, 103.74),
      scheduledArrivalSeconds: null,
      scheduledDepartureSeconds: null,
    ),
    if (stopCount > 1)
      AiRouteStopEvidence(
        stopId: 'stop-b',
        stopName: 'Stop B',
        stopSequence: 2,
        coordinate: secondCoordinateAvailable
            ? const MapCoordinate(1.50, 103.75)
            : null,
        scheduledArrivalSeconds: null,
        scheduledDepartureSeconds: null,
      ),
  ];
  final network = AiRouteNetworkEvidence(
    route: routeValue,
    trips: [
      AiRouteTripEvidence(
        tripId: '$routeId-trip',
        shapeId: null,
        stops: stops,
        shapePoints: includeShape
            ? const [
                ShapePoint(
                  sequence: 1,
                  coordinate: MapCoordinate(1.49, 103.74),
                ),
                ShapePoint(
                  sequence: 2,
                  coordinate: MapCoordinate(1.50, 103.75),
                ),
              ]
            : const [],
        routeDistanceMeters: includeDistanceAndSpacing ? 1500 : null,
      ),
    ],
  );
  final operational = AiOperationalEvidence(
    route: routeValue,
    periodStart: periodStart,
    periodEnd: periodEnd,
    peakOperationSummary: PeakOperationSummary(
      routeId: routeId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      observationCount: 0,
      distinctTripOccurrences: 0,
      observedDayCount: 0,
      routesRepresented: 0,
      bucketBreakdown: const [],
      peakBuckets: const [],
      averageActivity: 0,
      activityDifferencePercent: 0,
      dailyActivity: const [],
      routeActivity: const [],
      observedWindowStart: null,
      observedWindowEnd: null,
      hasReliablePeak: false,
      hasLimitedCoverage: true,
    ),
    routePerformanceSummary: const RoutePerformanceSummary(
      trips: [],
      totalObservations: 0,
      averageTravelTime: null,
      delayedTripCount: 0,
      delayFrequencyPercent: null,
      scheduleAdherencePercent: null,
    ),
  );
  final routeStop = RouteStopEvidence(
    routeId: routeId,
    periodStart: periodStart,
    periodEnd: periodEnd,
    network: network,
    operational: operational,
    feedback: const RouteStopFeedbackEvidence(
      records: [],
      countByIssueType: {},
      routeStopRelevantRecords: [],
    ),
    stopSpacingByTrip: includeDistanceAndSpacing
        ? [
            TripStopSpacingEvidence(
              tripId: '$routeId-trip',
              consecutiveStops: const [
                ConsecutiveStopSpacingEvidence(
                  fromStopId: 'stop-a',
                  fromStopSequence: 1,
                  toStopId: 'stop-b',
                  toStopSequence: 2,
                  distanceMeters: 1500,
                ),
              ],
            ),
          ]
        : const [],
  );
  return DistrictRouteStopEvidence(
    routeStopEvidence: routeStop,
    boundary: const DistrictBoundaryEvidence(
      status: DistrictBoundaryStatus.unavailable,
      geometry: null,
      source: johorBahruDistrictBoundarySource,
    ),
    tripStopMembership: const [],
    stopOccurrenceCounts: DistrictMembershipCounts(
      insideJohorBahruDistrict: 0,
      outsideJohorBahruDistrict: 0,
      unverifiable: stopCount,
    ),
    uniqueStopCounts: DistrictMembershipCounts(
      insideJohorBahruDistrict: 0,
      outsideJohorBahruDistrict: 0,
      unverifiable: stopCount,
    ),
  );
}

RouteStopRecommendationResult result(RouteStopRecommendationAction action) =>
    RouteStopRecommendationResult(
      status: action == RouteStopRecommendationAction.insufficientEvidence
          ? RouteStopRecommendationStatus.insufficientEvidence
          : RouteStopRecommendationStatus.available,
      recommendation: RouteStopRecommendation(
        action: action,
        summary: 'Evidence-grounded route result.',
        rationale: const ['Existing network evidence supports review.'],
        evidenceReferences: const ['network.trip.0'],
        limitations: const ['Operational coverage is limited.'],
        evidenceSufficiency:
            action == RouteStopRecommendationAction.insufficientEvidence
            ? RouteStopEvidenceSufficiency.insufficient
            : RouteStopEvidenceSufficiency.limited,
        candidateArea:
            action == RouteStopRecommendationAction.additionalStopCoverage
            ? const RouteStopCandidateArea(
                fromStopId: 'stop-a',
                fromStopName: 'Stop A',
                toStopId: 'stop-b',
                toStopName: 'Stop B',
                areaDescription: 'Evaluate the existing stop gap.',
              )
            : null,
        source: RouteStopRecommendationSource.gemini,
      ),
      failure: null,
      evidence: null,
      payload: null,
    );

RouteStopRecommendationResult unavailable() =>
    const RouteStopRecommendationResult(
      status: RouteStopRecommendationStatus.temporarilyUnavailable,
      recommendation: null,
      failure: RouteStopRecommendationFailure.network,
      evidence: null,
      payload: null,
    );

class FakeRouteRepository implements RoutePerformanceRepository {
  FakeRouteRepository(this.routes);
  final List<RoutePerformanceRoute> routes;

  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() async => routes;

  @override
  Future<RoutePerformanceData> loadRoutePerformance({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) => throw UnimplementedError();
}

class FakeEvidenceRepository implements DistrictRouteStopEvidenceRepository {
  FakeEvidenceRepository(this.evidenceByRoute);
  final Map<String, DistrictRouteStopEvidence> evidenceByRoute;
  final periods = <(DateTime, DateTime)>[];

  @override
  Future<DistrictRouteStopEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    periods.add((startUtc, endExclusiveUtc));
    return evidenceByRoute[routeId]!;
  }
}

class FakeRecommendationRepository
    implements RouteStopRecommendationRepository {
  final routeIds = <String>[];
  final evidence = <DistrictRouteStopEvidence?>[];
  int activeCalls = 0;
  int maximumConcurrentCalls = 0;

  @override
  Future<RouteStopRecommendationResult> generate({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    DistrictRouteStopEvidence? evidence,
  }) async {
    routeIds.add(routeId);
    this.evidence.add(evidence);
    activeCalls++;
    maximumConcurrentCalls = activeCalls > maximumConcurrentCalls
        ? activeCalls
        : maximumConcurrentCalls;
    await Future<void>.delayed(Duration.zero);
    activeCalls--;
    return result(RouteStopRecommendationAction.maintainCurrentConfiguration);
  }
}

class FakeDashboardCoordinator extends RouteStopDashboardCoordinator {
  FakeDashboardCoordinator({
    required this.candidates,
    this.excludedRoutes = const [],
    this.results = const {},
    this.analysisGate,
  }) : super(
         routeRepository: FakeRouteRepository(const []),
         evidenceRepository: FakeEvidenceRepository(const {}),
         recommendationRepository: FakeRecommendationRepository(),
       );

  final List<RouteStopDashboardCandidate> candidates;
  final List<RouteStopDashboardExcludedRoute> excludedRoutes;
  final Map<String, RouteStopRecommendationResult> results;
  final Completer<void>? analysisGate;
  final analysisRouteIds = <String>[];
  final retryRouteIds = <String>[];
  DateTime? screenStartUtc;
  DateTime? screenEndUtc;
  int screenCalls = 0;
  int analyseBatchCalls = 0;

  @override
  Future<RouteStopDashboardScreeningResult> screenRoutes({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    screenCalls++;
    screenStartUtc = startUtc;
    screenEndUtc = endExclusiveUtc;
    return RouteStopDashboardScreeningResult(
      routesAnalysed: candidates.length + excludedRoutes.length,
      candidates: candidates,
      excludedRoutes: excludedRoutes,
    );
  }

  @override
  Future<List<RouteStopDashboardCandidate>> screenCandidates({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    screenStartUtc = startUtc;
    screenEndUtc = endExclusiveUtc;
    return candidates;
  }

  @override
  Future<List<RouteStopDashboardEntry>> analyseBatch({
    required List<RouteStopDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    void Function(int completed, int total, RouteStopDashboardEntry entry)?
    onCompleted,
  }) async {
    analyseBatchCalls++;
    final batch = candidates.take(routeStopDashboardBatchSize).toList();
    if (analysisGate != null) await analysisGate!.future;
    final entries = <RouteStopDashboardEntry>[];
    for (var index = 0; index < batch.length; index++) {
      final candidate = batch[index];
      analysisRouteIds.add(candidate.route.routeId);
      final entry = RouteStopDashboardEntry(
        route: candidate.route,
        result:
            results[candidate.route.routeId] ??
            result(RouteStopRecommendationAction.routeImprovement),
      );
      entries.add(entry);
      onCompleted?.call(index + 1, batch.length, entry);
    }
    return entries;
  }

  @override
  Future<RouteStopDashboardEntry> retry({
    required RouteStopDashboardCandidate candidate,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    retryRouteIds.add(candidate.route.routeId);
    return RouteStopDashboardEntry(
      route: candidate.route,
      result: result(RouteStopRecommendationAction.stopImprovement),
    );
  }
}
