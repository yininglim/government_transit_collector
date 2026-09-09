import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';
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
  test(
    '21-route generation and retry each use one retained-evidence request',
    () async {
      final repository = FakeRecommendationRepository();
      final coordinator = RouteStopDashboardCoordinator(
        routeRepository: FakeRouteRepository(const []),
        evidenceRepository: FakeEvidenceRepository(const {}),
        recommendationRepository: repository,
      );
      final candidates = List.generate(
        21,
        (index) => candidate('R${index + 1}'),
      );
      await coordinator.analyse(
        candidates: candidates,
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );
      await coordinator.retry(
        candidates: candidates,
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );
      expect(repository.calls, 2);
      final expected = List.generate(21, (index) => 'R${index + 1}');
      expect(repository.evidenceCalls, [expected, expected]);
    },
  );

  testWidgets(
    'entry and B1 interactions make zero AI calls; Generate makes one',
    (tester) async {
      final coordinator = FakeDashboardCoordinator(
        candidates: [candidate('R1'), candidate('R2')],
      );
      final session = screenedSession([candidate('R1'), candidate('R2')]);
      await pumpPage(tester, coordinator, session);
      expect(coordinator.analyseCalls, 0);
      expect(find.text('Route / Stop Evidence Coverage'), findsOneWidget);
      final selector = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('route-map-selector')),
      );
      selector.onChanged!('R2');
      await tester.pump();
      expect(coordinator.analyseCalls, 0);
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('view-route-stop-evidence')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(coordinator.analyseCalls, 0);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(
            find.byKey(const Key('generate-ai-recommendation')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(coordinator.analyseCalls, 1);
      expect(find.text('Overall Route & Stop Analysis'), findsOneWidget);
      expect(
        find.byKey(const Key('action-group-routeImprovement')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'revisit restores grouped result and Start New clears without auto generation',
    (tester) async {
      final coordinator = FakeDashboardCoordinator(
        candidates: [candidate('R1')],
      );
      final session = screenedSession([candidate('R1')])
        ..recommendationResult = groupedResult(['R1']);
      await pumpPage(tester, coordinator, session);
      expect(find.text('Cross-route summary'), findsOneWidget);
      expect(coordinator.analyseCalls, 0);
      await tester.tap(find.byKey(const Key('analyse-routes')));
      await tester.pumpAndSettle();
      expect(session.recommendationResult, isNull);
      expect(coordinator.analyseCalls, 0);
    },
  );

  testWidgets('duplicate generation taps are blocked', (tester) async {
    final gate = Completer<void>();
    final coordinator = FakeDashboardCoordinator(
      candidates: [candidate('R1')],
      gate: gate,
    );
    await pumpPage(tester, coordinator, screenedSession([candidate('R1')]));
    final onPressed = tester
        .widget<FilledButton>(
          find.byKey(const Key('generate-ai-recommendation')),
        )
        .onPressed!;
    onPressed();
    await tester.pump();
    onPressed();
    expect(coordinator.analyseCalls, 1);
    gate.complete();
    await tester.pumpAndSettle();
  });

  for (final size in [const Size(390, 844), const Size(844, 360)]) {
    testWidgets('grouped result remains scrollable at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final longId = 'ROUTE-WITH-A-LONG-DETERMINISTIC-NAME-123456789';
      final session = screenedSession([candidate(longId)])
        ..recommendationResult = groupedResult([
          longId,
        ], summary: List.filled(25, 'Long evidence summary').join(' '));
      await pumpPage(
        tester,
        FakeDashboardCoordinator(candidates: session.candidates),
        session,
      );
      expect(find.byType(ListView), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'screening preserves gate, ordering, exclusions, and load failures',
    () async {
      final coordinator = RouteStopDashboardCoordinator(
        routeRepository: FakeRouteRepository([
          route('B'),
          route('A'),
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
      expect(result.candidates.map((item) => item.route.routeId), ['A']);
      expect(result.excludedRoutes.map((item) => item.route.routeId), [
        'B',
        'C',
      ]);
      expect(result.excludedRoutes.map((item) => item.reason), [
        RouteStopDashboardExclusionReason.unusableTripStructure,
        RouteStopDashboardExclusionReason.evidenceLoadingFailure,
      ]);
    },
  );

  testWidgets(
    'coverage reports supported Available Limited and Missing states',
    (tester) async {
      final routes = [
        candidateWithEvidence(
          'FULL',
          evidence(
            'FULL',
            includeDistanceAndSpacing: true,
            observationCount: 2,
            feedbackCount: 1,
          ),
        ),
        candidateWithEvidence(
          'PARTIAL',
          evidence('PARTIAL', secondCoordinateAvailable: false),
        ),
      ];
      await pumpPage(
        tester,
        FakeDashboardCoordinator(candidates: routes),
        screenedSession(routes),
      );
      expect(coverageValue(tester, 'Route / Trip Structure'), 'Available');
      expect(coverageValue(tester, 'Ordered Stops'), 'Available');
      expect(coverageValue(tester, 'Stop Coordinates'), 'Limited');
      expect(coverageValue(tester, 'Route Distance / Spacing'), 'Limited');
      expect(coverageValue(tester, 'Operational Evidence'), 'Limited');
      expect(coverageValue(tester, 'Relevant Feedback'), 'Limited');
      final missing = [candidate('MISSING')];
      await tester.pumpWidget(const SizedBox());
      await pumpPage(
        tester,
        FakeDashboardCoordinator(candidates: missing),
        screenedSession(missing),
      );
      expect(coverageValue(tester, 'Route Distance / Spacing'), 'Missing');
      expect(coverageValue(tester, 'Operational Evidence'), 'Missing');
      expect(coverageValue(tester, 'Relevant Feedback'), 'Missing');
    },
  );

  testWidgets('limited routes render separately from grouped AI results', (
    tester,
  ) async {
    final eligible = [candidate('R1')];
    final excluded = RouteStopDashboardExcludedRoute(
      route: route('LIMITED'),
      reason: RouteStopDashboardExclusionReason.unusableTripStructure,
      evidence: evidence('LIMITED', stopCount: 1),
    );
    final session = screenedSession(eligible)
      ..excludedRoutes.add(excluded)
      ..routesAnalysed = 2
      ..recommendationResult = groupedResult(['R1']);
    await pumpPage(
      tester,
      FakeDashboardCoordinator(candidates: eligible),
      session,
    );
    tester
        .widget<OutlinedButton>(find.byKey(const Key('view-limited-routes')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('limited-routes-details')), findsOneWidget);
    expect(find.text('LIMITED'), findsOneWidget);
    expect(find.textContaining('at least two ordered stops'), findsOneWidget);
    expect(find.byKey(const Key('group-route-LIMITED')), findsNothing);
  });

  testWidgets(
    'deterministic map renders shape and only coordinate-backed stops',
    (tester) async {
      final item = candidateWithEvidence(
        'R1',
        evidence('R1', includeShape: true, secondCoordinateAvailable: false),
      );
      await pumpPage(
        tester,
        FakeDashboardCoordinator(candidates: [item]),
        screenedSession([item]),
      );
      expect(find.byKey(const Key('existing-route-shape')), findsOneWidget);
      expect(
        find.byKey(const Key('existing-stop-marker-stop-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('existing-stop-marker-stop-b')),
        findsNothing,
      );
      expect(
        find.textContaining('1 stop occurrences cannot be mapped'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'missing shape and coordinates are disclosed without fake geometry',
    (tester) async {
      final item = candidateWithEvidence(
        'R1',
        evidence('R1', secondCoordinateAvailable: false),
      );
      await pumpPage(
        tester,
        FakeDashboardCoordinator(candidates: [item]),
        screenedSession([item]),
      );
      expect(find.byKey(const Key('existing-route-shape')), findsNothing);
      expect(find.textContaining('route shape is unavailable'), findsOneWidget);
      expect(
        find.byKey(const Key('existing-stop-marker-stop-b')),
        findsNothing,
      );
    },
  );

  testWidgets('route selection updates retained map route without AI', (
    tester,
  ) async {
    final items = [candidate('R1'), candidate('R2')];
    final coordinator = FakeDashboardCoordinator(candidates: items);
    await pumpPage(tester, coordinator, screenedSession(items));
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const Key('route-map-selector')),
        )
        .onChanged!('R2');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('existing-network-map-R2')),
      findsOneWidget,
    );
    expect(find.text('R2'), findsWidgets);
    expect(coordinator.analyseCalls, 0);
  });

  testWidgets(
    'View Evidence exposes every retained deterministic section without AI',
    (tester) async {
      final item = candidateWithEvidence(
        'R1',
        evidence('R1', includeDistanceAndSpacing: true),
      );
      final coordinator = FakeDashboardCoordinator(candidates: [item]);
      await pumpPage(tester, coordinator, screenedSession([item]));
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('view-route-stop-evidence')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      final details = find.byKey(const Key('deterministic-evidence-R1'));
      final scrollable = find.descendant(
        of: details,
        matching: find.byType(Scrollable),
      );
      for (final item in [
        ('route-structure', 'Usable trips: 1'),
        ('stop-coverage', 'Stops with coordinates: 2 of 2'),
        ('distance-spacing', 'Trips with route distance: 1 of 1'),
        ('operational-evidence', 'Peak Operation observations: 0'),
        ('feedback', 'Relevant route/stop feedback: 0'),
        ('limitations', null),
      ]) {
        final finder = find.byKey(Key('evidence-section-${item.$1}'));
        await tester.scrollUntilVisible(finder, 160, scrollable: scrollable);
        expect(finder, findsOneWidget);
        if (item.$2 case final value?) {
          expect(find.text(value), findsOneWidget);
        }
      }
      expect(coordinator.analyseCalls, 0);
    },
  );

  testWidgets('fixed period and zero eligible routes cannot generate AI', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(candidates: const []);
    final session = screenedSession(const []);
    await pumpPage(tester, coordinator, session);
    expect(find.text('Past 30 Days'), findsOneWidget);
    expect(find.text('No eligible routes'), findsOneWidget);
    expect(find.byKey(const Key('generate-ai-recommendation')), findsNothing);
    expect(coordinator.analyseCalls, 0);
  });

  testWidgets('revisit restores screening exclusions and selected map route', (
    tester,
  ) async {
    final items = [candidate('R1'), candidate('R2')];
    final session = screenedSession(items)
      ..selectedRouteId = 'R2'
      ..excludedRoutes.add(
        RouteStopDashboardExcludedRoute(
          route: route('LIMITED'),
          reason: RouteStopDashboardExclusionReason.unusableTripStructure,
          evidence: evidence('LIMITED', stopCount: 1),
        ),
      )
      ..routesAnalysed = 3;
    final coordinator = FakeDashboardCoordinator(candidates: items);
    await pumpPage(tester, coordinator, session);
    expect(
      find.byKey(const ValueKey('existing-network-map-R2')),
      findsOneWidget,
    );
    expect(find.text('Limited / Excluded Routes'), findsWidgets);
    expect(coordinator.screenCalls, 0);
    expect(coordinator.analyseCalls, 0);
  });

  testWidgets('harmless rebuild does not generate AI', (tester) async {
    final items = [candidate('R1')];
    final coordinator = FakeDashboardCoordinator(candidates: items);
    final session = screenedSession(items);
    await pumpPage(tester, coordinator, session);
    await pumpPage(tester, coordinator, session);
    await tester.pump();
    expect(coordinator.analyseCalls, 0);
  });

  testWidgets('renders feature summary with action groups as route parents', (
    tester,
  ) async {
    final items = [
      namedCandidate('J10', 'JB Sentral - Terminal Bas Kota Tinggi'),
      namedCandidate('J100', 'JB Sentral KSL - JB Sentral'),
      namedCandidate('J11', 'JB Sentral - AEON Dato Onn via Setia Indah'),
      namedCandidate('J20', 'Taman Route'),
      namedCandidate('J30', 'Limited Evidence Route'),
    ];
    final session = screenedSession(items)
      ..recommendationResult = RouteStopRecommendationResult(
        status: RouteStopRecommendationStatus.available,
        synthesis: const RouteStopRecommendationSynthesis(
          overallSummary: 'Retained cross-route analysis.',
          recommendationGroups: [
            RouteStopRecommendationGroup(
              action: RouteStopRecommendationAction.routeImprovement,
              summary: 'Review these route structures.',
              rationale: [],
              evidenceReferences: [],
              limitations: [],
              routeIds: ['J10', 'J100', 'J11'],
              candidateAreas: [],
            ),
            RouteStopRecommendationGroup(
              action: RouteStopRecommendationAction.stopImprovement,
              summary: 'Review these existing stops.',
              rationale: [],
              evidenceReferences: [],
              limitations: [],
              routeIds: ['J20'],
              candidateAreas: [],
            ),
          ],
          needsMoreEvidence: RouteStopRecommendationGroup(
            action: RouteStopRecommendationAction.insufficientEvidence,
            summary: 'More evidence is required.',
            rationale: [],
            evidenceReferences: [],
            limitations: ['Limited evidence.'],
            routeIds: ['J30'],
            candidateAreas: [],
          ),
        ),
        failure: null,
        evidence: [],
        payload: null,
      )
      ..excludedRoutes.add(
        RouteStopDashboardExcludedRoute(
          route: route('EXCLUDED'),
          reason: RouteStopDashboardExclusionReason.unusableTripStructure,
          evidence: evidence('EXCLUDED', stopCount: 1),
        ),
      );
    final coordinator = FakeDashboardCoordinator(candidates: items);
    await pumpPage(tester, coordinator, session);

    expect(find.text('Overall Route & Stop Analysis'), findsOneWidget);
    expect(find.text('Retained cross-route analysis.'), findsOneWidget);
    expect(find.text('Route Improvement'), findsOneWidget);
    expect(find.text('Stop Improvement'), findsOneWidget);
    final routeGroup = find.byKey(const Key('action-group-routeImprovement'));
    expect(
      find.descendant(of: routeGroup, matching: find.text('3 Routes')),
      findsOneWidget,
    );
    for (final routeId in ['J10', 'J100', 'J11']) {
      expect(
        find.descendant(
          of: routeGroup,
          matching: find.byKey(Key('group-route-$routeId')),
        ),
        findsOneWidget,
      );
    }
    expect(find.byKey(const Key('route-result-J10')), findsNothing);
    expect(find.textContaining('Evidence: Sufficient'), findsNothing);
    expect(find.byKey(const Key('view-details-J10')), findsNothing);
    expect(find.byKey(const Key('needs-more-evidence')), findsOneWidget);
    expect(find.text('Limited / Excluded Routes'), findsWidgets);
    expect(coordinator.analyseCalls, 0);
  });

  testWidgets('revisit restores summary and grouped routes without AI', (
    tester,
  ) async {
    final items = [candidate('J10'), candidate('J100'), candidate('J11')];
    final session = screenedSession(items)
      ..recommendationResult = groupedResult([
        'J10',
        'J100',
        'J11',
      ], summary: 'Restored overall summary.');
    final coordinator = FakeDashboardCoordinator(candidates: items);
    await pumpPage(tester, coordinator, session);
    expect(find.text('Restored overall summary.'), findsOneWidget);
    expect(find.text('Route Improvement'), findsOneWidget);
    expect(find.text('3 Routes'), findsOneWidget);
    expect(coordinator.analyseCalls, 0);
    expect(
      find.byKey(const ValueKey('existing-network-map-J10')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('view-route-stop-evidence')), findsOneWidget);
  });
}

Future<void> pumpPage(
  WidgetTester tester,
  RouteStopDashboardCoordinator coordinator,
  RouteStopDashboardSession session,
) => tester.pumpWidget(
  MaterialApp(
    home: RouteBusStopRecommendationPage(
      session: session,
      coordinator: coordinator,
      now: () => DateTime(2026, 8, 28),
    ),
  ),
);
RouteStopDashboardCandidate candidate(String id) =>
    RouteStopDashboardCandidate(route: route(id), evidence: evidence(id));
RouteStopDashboardCandidate namedCandidate(String id, String name) =>
    RouteStopDashboardCandidate(
      route: RoutePerformanceRoute(routeId: id, shortName: id, longName: name),
      evidence: evidence(id),
    );
RouteStopDashboardCandidate candidateWithEvidence(
  String id,
  DistrictRouteStopEvidence value,
) => RouteStopDashboardCandidate(route: route(id), evidence: value);

String coverageValue(WidgetTester tester, String label) {
  final row = find.ancestor(of: find.text(label), matching: find.byType(Row));
  return tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .last
      .data!;
}

RouteStopDashboardSession screenedSession(
  List<RouteStopDashboardCandidate> candidates,
) {
  final session = RouteStopDashboardSession();
  session.periodStartUtc = periodStart;
  session.periodEndUtc = periodEnd;
  session.screeningComplete = true;
  session.routesAnalysed = candidates.length;
  session.empty = candidates.isEmpty;
  session.candidates.addAll(candidates);
  session.selectedRouteId = candidates.firstOrNull?.route.routeId;
  return session;
}

RouteStopRecommendationResult groupedResult(
  List<String> ids, {
  String summary = 'Cross-route summary',
}) => RouteStopRecommendationResult(
  status: RouteStopRecommendationStatus.available,
  synthesis: RouteStopRecommendationSynthesis(
    overallSummary: summary,
    recommendationGroups: [
      RouteStopRecommendationGroup(
        action: RouteStopRecommendationAction.routeImprovement,
        summary: 'Review routes.',
        rationale: const ['Evidence supports review.'],
        evidenceReferences: const [],
        limitations: const [],
        routeIds: ids,
        candidateAreas: const [],
      ),
    ],
    needsMoreEvidence: null,
  ),
  failure: null,
  evidence: const [],
  payload: null,
);
final periodStart = DateTime.utc(2026, 7, 29, 16);
final periodEnd = DateTime.utc(2026, 8, 28, 16);

RoutePerformanceRoute route(String id) =>
    RoutePerformanceRoute(routeId: id, shortName: id, longName: null);

AdminFeedbackRecord feedbackRecord(String routeId, int index) =>
    AdminFeedbackRecord(
      feedbackId: 'feedback-$index',
      routeId: routeId,
      tripId: null,
      stopId: 'stop-a',
      issueType: 'missing_bus_stop',
      comment: '',
      createdAt: periodStart,
    );

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
  int observationCount = 0,
  int feedbackCount = 0,
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
      observationCount: observationCount,
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
    routePerformanceSummary: RoutePerformanceSummary(
      trips: const [],
      totalObservations: observationCount,
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
    feedback: RouteStopFeedbackEvidence(
      records: [
        for (var index = 0; index < feedbackCount; index++)
          feedbackRecord(routeId, index),
      ],
      countByIssueType: feedbackCount == 0
          ? const {}
          : const {'missing_bus_stop': 1},
      routeStopRelevantRecords: [
        for (var index = 0; index < feedbackCount; index++)
          feedbackRecord(routeId, index),
      ],
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
  FakeEvidenceRepository(this.values);
  final Map<String, DistrictRouteStopEvidence> values;
  int calls = 0;
  @override
  Future<DistrictRouteStopEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    calls++;
    return values[routeId]!;
  }
}

class FakeRecommendationRepository
    implements RouteStopRecommendationRepository {
  int calls = 0;
  final evidenceCalls = <List<String>>[];
  @override
  Future<RouteStopRecommendationResult> generate({
    required List<DistrictRouteStopEvidence> evidence,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    calls++;
    evidenceCalls.add(
      evidence.map((item) => item.routeStopEvidence.routeId).toList(),
    );
    return groupedResult(evidenceCalls.last);
  }
}

class FakeDashboardCoordinator extends RouteStopDashboardCoordinator {
  FakeDashboardCoordinator({required this.candidates, this.gate})
    : super(
        routeRepository: FakeRouteRepository(const []),
        evidenceRepository: FakeEvidenceRepository(const {}),
        recommendationRepository: FakeRecommendationRepository(),
      );
  final List<RouteStopDashboardCandidate> candidates;
  final Completer<void>? gate;
  int analyseCalls = 0;
  int screenCalls = 0;
  @override
  Future<RouteStopDashboardScreeningResult> screenRoutes({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    screenCalls++;
    return RouteStopDashboardScreeningResult(
      routesAnalysed: candidates.length,
      candidates: candidates,
      excludedRoutes: const [],
    );
  }

  @override
  Future<RouteStopRecommendationResult> analyse({
    required List<RouteStopDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    analyseCalls++;
    if (gate != null) await gate!.future;
    return groupedResult(candidates.map((item) => item.route.routeId).toList());
  }

  @override
  Future<RouteStopRecommendationResult> retry({
    required List<RouteStopDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) => analyse(
    candidates: candidates,
    startUtc: startUtc,
    endExclusiveUtc: endExclusiveUtc,
  );
}
