import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/bus_frequency_recommendation_page.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

void main() {
  test(
    'screening retains eligibility, exclusions, and load failures',
    () async {
      final coordinator = BusFrequencyDashboardCoordinator(
        routeRepository: FakeRoutes(['B', 'A', 'C']),
        evidenceRepository: FakeEvidence(
          {'A': evidence('A'), 'B': evidence('B', eligible: false)},
          failures: {'C'},
        ),
        recommendationRepository: FakeRecommendations(),
      );
      final result = await coordinator.screenRoutes(
        startUtc: start,
        endExclusiveUtc: end,
      );
      expect(result.routesAnalysed, 3);
      expect(result.candidates.map((item) => item.route.routeId), ['A']);
      expect(result.excludedRoutes.map((item) => item.reason), [
        BusFrequencyDashboardExclusionReason.noSupportingEvidence,
        BusFrequencyDashboardExclusionReason.evidenceLoadingFailure,
      ]);
    },
  );

  test('screening keeps four-worker concurrency and route order', () async {
    final evidenceRepository = ConcurrentEvidence();
    final coordinator = BusFrequencyDashboardCoordinator(
      routeRepository: FakeRoutes(['E', 'D', 'C', 'B', 'A']),
      evidenceRepository: evidenceRepository,
      recommendationRepository: FakeRecommendations(),
    );

    final result = await coordinator.screenRoutes(
      startUtc: start,
      endExclusiveUtc: end,
    );

    expect(evidenceRepository.maximumActive, 4);
    expect(result.candidates.map((candidate) => candidate.route.routeId), [
      'A',
      'B',
      'C',
      'D',
      'E',
    ]);
  });

  test(
    'coordinator sends all retained evidence in one call and retry uses it',
    () async {
      final recommendations = FakeRecommendations();
      final coordinator = BusFrequencyDashboardCoordinator(
        routeRepository: FakeRoutes(const []),
        evidenceRepository: FakeEvidence(const {}),
        recommendationRepository: recommendations,
      );
      final retained = candidates(3);
      await coordinator.analyse(
        candidates: retained,
        startUtc: start,
        endExclusiveUtc: end,
      );
      await coordinator.retry(
        candidates: retained,
        startUtc: start,
        endExclusiveUtc: end,
      );
      expect(recommendations.calls, 2);
      expect(
        recommendations.evidenceHistory[0],
        retained.map((item) => item.evidence),
      );
      expect(
        recommendations.evidenceHistory[1],
        retained.map((item) => item.evidence),
      );
    },
  );

  test(
    'same-period preparation reuses in-progress and completed work',
    () async {
      final screenGate = Completer<void>();
      final coordinator = FakeCoordinator(
        candidates(1),
        screenGate: screenGate,
      );
      final session = BusFrequencyDashboardSession();
      final first = coordinator.prepareSession(
        session: session,
        startUtc: start,
        endExclusiveUtc: end,
      );
      final second = coordinator.prepareSession(
        session: session,
        startUtc: start,
        endExclusiveUtc: end,
      );
      expect(second, same(first));
      expect(coordinator.screenCalls, 1);
      screenGate.complete();
      await first;
      await coordinator.prepareSession(
        session: session,
        startUtc: start,
        endExclusiveUtc: end,
      );
      expect(coordinator.screenCalls, 1);
      expect(session.screeningComplete, isTrue);
      expect(session.candidates, hasLength(1));
    },
  );

  test(
    'stale preparation completion cannot overwrite a newer period',
    () async {
      final oldGate = Completer<void>();
      final oldCoordinator = FakeCoordinator(
        candidates(1),
        screenGate: oldGate,
      );
      final newCoordinator = FakeCoordinator(candidates(2));
      final session = BusFrequencyDashboardSession();
      final oldWork = oldCoordinator.prepareSession(
        session: session,
        startUtc: start,
        endExclusiveUtc: end,
      );
      final newStart = start.add(const Duration(days: 1));
      final newEnd = end.add(const Duration(days: 1));
      await newCoordinator.prepareSession(
        session: session,
        startUtc: newStart,
        endExclusiveUtc: newEnd,
      );
      oldGate.complete();
      await oldWork;
      expect(session.matchesPeriod(newStart, newEnd), isTrue);
      expect(session.candidates.map((item) => item.route.routeId), [
        'R1',
        'R2',
      ]);
      expect(session.routesAnalysed, 2);
    },
  );

  testWidgets('entry screens evidence and makes no recommendation request', (
    tester,
  ) async {
    final coordinator = FakeCoordinator(candidates(2));
    await pumpPage(tester, coordinator);
    await tester.pumpAndSettle();
    expect(coordinator.analysisCalls, 0);
    expect(
      find.byKey(const Key('frequency-evidence-overview')),
      findsOneWidget,
    );
    expect(find.text('Routes Analysed'), findsOneWidget);
    expect(find.text('Eligible Routes'), findsOneWidget);
  });

  testWidgets('View Evidence makes zero recommendation requests', (
    tester,
  ) async {
    final coordinator = FakeCoordinator(candidates(1));
    await pumpPage(tester, coordinator);
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('view-evidence-details'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('frequency-evidence-details')), findsOneWidget);
    expect(coordinator.analysisCalls, 0);
  });

  testWidgets('zero eligible routes disable generation', (tester) async {
    final coordinator = FakeCoordinator(const []);
    await pumpPage(tester, coordinator);
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('generate-ai-recommendation'));
    await tester.ensureVisible(button);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(coordinator.analysisCalls, 0);
  });

  testWidgets('one generation call renders action-first multiple routes', (
    tester,
  ) async {
    final coordinator = FakeCoordinator(candidates(3));
    await pumpPage(tester, coordinator);
    await tapGenerate(tester);
    await tester.pumpAndSettle();
    expect(coordinator.analysisCalls, 1);
    expect(find.byKey(const Key('overall-ai-summary')), findsOneWidget);
    expect(find.text('Overall evidence-grounded summary.'), findsOneWidget);
    expect(find.text('Maintain Current Frequency'), findsOneWidget);
    expect(find.text('AI Rationale'), findsOneWidget);
    expect(
      find.text('Scheduled evidence supports this action.'),
      findsOneWidget,
    );
    expect(find.text('3 Routes'), findsOneWidget);
    expect(find.byKey(const Key('group-route-R1')), findsOneWidget);
    expect(find.byKey(const Key('group-route-R2')), findsOneWidget);
    expect(find.byKey(const Key('group-route-R3')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('group-route-R1')),
        matching: find.byKey(const Key('action-group-maintainService')),
      ),
      findsOneWidget,
    );
    expect(find.text('Scheduled departures'), findsNWidgets(3));
    expect(find.text('Headway'), findsNWidgets(3));
  });

  testWidgets('overview counts and action filter use the retained result', (
    tester,
  ) async {
    final items = candidates(6);
    final coordinator = FakeCoordinator(
      items,
      resultOverride: groupedResult([
        (
          BusFrequencyRecommendationAction.increasePeakHourFrequency,
          ['R1', 'R2', 'R3', 'R4'],
        ),
        (BusFrequencyRecommendationAction.maintainService, ['R5']),
        (BusFrequencyRecommendationAction.decreaseService, ['R6']),
      ]),
    );
    await pumpPage(tester, coordinator);
    await tapGenerate(tester);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('recommendation-overview')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('overview-actionable')),
        matching: find.text('6'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('overview-increase')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('overview-maintain')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('overview-decrease')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('overview-requiring-change')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(find.text('All 6'), findsOneWidget);
    expect(find.text('Increase 4'), findsOneWidget);
    expect(find.text('Maintain 1'), findsOneWidget);
    expect(find.text('Decrease 1'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('action-filter-all')))
          .selected,
      isTrue,
    );
    expect(find.text('Increase Peak-Hour Frequency'), findsOneWidget);
    expect(find.text('Maintain Current Frequency'), findsOneWidget);
    expect(find.text('Decrease Frequency'), findsOneWidget);
    expect(find.text('increasePeakHourFrequency'), findsNothing);

    final showMore = find.text('Show 1 more routes');
    await tester.ensureVisible(showMore);
    await tester.tap(showMore);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group-route-R4')), findsOneWidget);

    final maintainFilter = find.byKey(const Key('action-filter-maintain'));
    await tester.ensureVisible(maintainFilter);
    await tester.tap(maintainFilter);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('action-group-increasePeakHourFrequency')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('action-group-maintainService')),
      findsOneWidget,
    );

    final increaseFilter = find.byKey(const Key('action-filter-increase'));
    await tester.ensureVisible(increaseFilter);
    await tester.tap(increaseFilter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group-route-R4')), findsOneWidget);
    expect(find.text('Show fewer'), findsOneWidget);
  });

  testWidgets('route View Evidence uses retained deterministic evidence only', (
    tester,
  ) async {
    final coordinator = FakeCoordinator(candidates(1));
    await pumpPage(tester, coordinator);
    await tapGenerate(tester);
    await tester.pumpAndSettle();
    final calls = coordinator.analysisCalls;
    final view = find.byKey(const Key('view-route-evidence-R1'));
    await tester.ensureVisible(view);
    await tester.pumpAndSettle();
    await tester.tap(view);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('route-evidence-details-R1')), findsOneWidget);
    final details = find.byKey(const Key('route-evidence-details-R1'));
    expect(
      find.descendant(of: details, matching: find.text('Scheduled Service')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: details, matching: find.text('Operational Evidence')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: details, matching: find.text('Feedback')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: details, matching: find.text('Limitations')),
      findsOneWidget,
    );
    expect(find.text('Scheduled departures: 2'), findsOneWidget);
    expect(coordinator.analysisCalls, calls);
  });

  testWidgets('saves a recommendation once and retains Saved through filters', (
    tester,
  ) async {
    final gate = Completer<void>();
    final management = RecordingManagementRepository(gate: gate);
    final coordinator = FakeCoordinator(candidates(1));
    await pumpPage(tester, coordinator, managementRepository: management);
    await tapGenerate(tester);
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('save-frequency-recommendation-R1'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(management.busFrequencySaveCalls, 1);
    expect(tester.widget<OutlinedButton>(save).onPressed, isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);

    await tester.tap(find.byKey(const Key('action-filter-maintain')));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
    await tester.tap(find.byKey(const Key('action-filter-all')));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('limited routes remain separate and absent from grouped result', (
    tester,
  ) async {
    final limited = BusFrequencyDashboardExcludedRoute(
      route: route('LIMITED'),
      reason: BusFrequencyDashboardExclusionReason.noSupportingEvidence,
      evidence: evidence('LIMITED', eligible: false),
    );
    final coordinator = FakeCoordinator(candidates(1), excluded: [limited]);
    await pumpPage(tester, coordinator);
    await tester.pumpAndSettle();
    final view = find.byKey(const Key('view-limited-routes'));
    await tester.ensureVisible(view);
    await tester.tap(view);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('limited-routes-details')), findsOneWidget);
    expect(coordinator.analysisCalls, 0);
    expect(find.byKey(const Key('group-route-LIMITED')), findsNothing);
  });

  testWidgets('repeated tap cannot create duplicate synthesis calls', (
    tester,
  ) async {
    final gate = Completer<void>();
    final coordinator = FakeCoordinator(candidates(2), gate: gate);
    await pumpPage(tester, coordinator);
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('generate-ai-recommendation'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(coordinator.analysisCalls, 1);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('session revisit restores grouped result without another call', (
    tester,
  ) async {
    final session = BusFrequencyDashboardSession();
    final coordinator = FakeCoordinator(candidates(2));
    await pumpPage(tester, coordinator, session: session);
    await tapGenerate(tester);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await pumpPage(tester, coordinator, session: session);
    await tester.pumpAndSettle();
    expect(coordinator.analysisCalls, 1);
    expect(
      find.byKey(const Key('grouped-recommendation-result')),
      findsOneWidget,
    );
  });

  testWidgets('revisit during preparation reuses the same screening work', (
    tester,
  ) async {
    final screenGate = Completer<void>();
    final session = BusFrequencyDashboardSession();
    final coordinator = FakeCoordinator(candidates(1), screenGate: screenGate);
    await pumpPage(tester, coordinator, session: session);
    expect(coordinator.screenCalls, 1);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await pumpPage(tester, coordinator, session: session);
    expect(coordinator.screenCalls, 1);
    screenGate.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('frequency-evidence-overview')),
      findsOneWidget,
    );
  });

  testWidgets('Start New Analysis clears result and screens again', (
    tester,
  ) async {
    final session = BusFrequencyDashboardSession();
    final coordinator = FakeCoordinator(candidates(1));
    await pumpPage(tester, coordinator, session: session);
    await tapGenerate(tester);
    await tester.pumpAndSettle();
    final restart = find.byKey(const Key('analyse-routes'));
    await tester.ensureVisible(restart);
    await tester.pumpAndSettle();
    await tester.tap(restart);
    await tester.pumpAndSettle();
    expect(session.recommendationResult, isNull);
    expect(coordinator.screenCalls, 2);
  });

  testWidgets('feature retry performs one call using retained candidates', (
    tester,
  ) async {
    final coordinator = FakeCoordinator(candidates(2), firstFailure: true);
    await pumpPage(tester, coordinator);
    await tapGenerate(tester);
    await tester.pumpAndSettle();
    final retry = find.byKey(const Key('retry-feature-recommendation'));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(coordinator.analysisCalls, 2);
    expect(coordinator.lastCandidateIds, ['R1', 'R2']);
  });

  testWidgets('post-Gemini insufficient routes are presentation-filtered', (
    tester,
  ) async {
    final coordinator = FakeCoordinator(
      candidates(2),
      includeInsufficient: true,
    );
    await pumpPage(tester, coordinator);
    await tapGenerate(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('post-gemini-needs-evidence')), findsNothing);
    expect(find.byKey(const Key('group-route-R2')), findsNothing);
    expect(find.text('Needs More Evidence'), findsNothing);
    expect(find.text('Save Recommendation'), findsOneWidget);
  });

  testWidgets('only insufficient evidence renders the actionable empty state', (
    tester,
  ) async {
    final item = candidates(1);
    final insufficient = BusFrequencyRecommendationGroup(
      action: BusFrequencyRecommendationAction.insufficientEvidence,
      routeRecommendations: [
        BusFrequencyRouteRecommendationRecord(
          routeId: 'R1',
          action: BusFrequencyRecommendationAction.insufficientEvidence,
          conciseRationale: 'Coverage is limited.',
          evidenceRefs: const ['route.R1.scheduled.summary'],
          limitations: const ['Operational coverage is limited.'],
          source: BusFrequencyRecommendationSource.gemini,
        ),
      ],
      source: BusFrequencyRecommendationSource.gemini,
    );
    final coordinator = FakeCoordinator(
      item,
      resultOverride: BusFrequencyRecommendationResult(
        status: BusFrequencyRecommendationStatus.available,
        synthesis: BusFrequencyRecommendationSynthesis(
          overallSummary: 'Overall evidence-grounded summary.',
          routeRecommendations: const [],
          recommendationGroups: const [],
          needsMoreEvidence: insufficient,
        ),
        failure: null,
        payload: null,
      ),
    );
    await pumpPage(tester, coordinator);
    await tapGenerate(tester);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No actionable recommendations are available with the current evidence.',
      ),
      findsOneWidget,
    );
    expect(find.text('Needs More Evidence'), findsNothing);
    expect(find.text('Save Recommendation'), findsNothing);
  });

  testWidgets('narrow portrait with long summary and route wraps safely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final item = candidates(1).single;
    final coordinator = FakeCoordinator(
      [
        BusFrequencyDashboardCandidate(
          route: const RoutePerformanceRoute(
            routeId: 'R1',
            shortName:
                'A very long route identity that must wrap without overflow',
            longName: 'Long descriptive route text',
          ),
          evidence: item.evidence,
        ),
      ],
      resultOverride: groupedResult(
        [
          (BusFrequencyRecommendationAction.maintainService, ['R1']),
        ],
        overallSummary: List.filled(
          8,
          'A long evidence-grounded overall summary must remain readable.',
        ).join(' '),
      ),
    );
    await pumpPage(tester, coordinator);
    await tapGenerate(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets(
    'short landscape and long content remain scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(900, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final long = candidates(1).single;
      final coordinator = FakeCoordinator([
        BusFrequencyDashboardCandidate(
          route: const RoutePerformanceRoute(
            routeId: 'R1',
            shortName:
                'A very long route name that must wrap on narrow and short displays',
            longName: 'Additional descriptive route content',
          ),
          evidence: long.evidence,
        ),
      ]);
      await pumpPage(tester, coordinator);
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
      await tapGenerate(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> pumpPage(
  WidgetTester tester,
  BusFrequencyDashboardCoordinator coordinator, {
  BusFrequencyDashboardSession? session,
  RecommendationManagementRepository? managementRepository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BusFrequencyRecommendationPage(
        coordinator: coordinator,
        session: session,
        now: () => DateTime.utc(2026, 8, 31, 4),
        managementRepository: managementRepository,
      ),
    ),
  );
  await tester.pump();
}

Future<void> tapGenerate(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final button = find.byKey(const Key('generate-ai-recommendation'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

final start = DateTime.utc(2026, 8, 1);
final end = DateTime.utc(2026, 8, 31);
RoutePerformanceRoute route(String id) =>
    RoutePerformanceRoute(routeId: id, shortName: id, longName: null);
List<BusFrequencyDashboardCandidate> candidates(int count) =>
    List.generate(count, (i) {
      final id = 'R${i + 1}';
      return BusFrequencyDashboardCandidate(
        route: route(id),
        evidence: evidence(id),
      );
    });

BusFrequencyEvidence evidence(String id, {bool eligible = true}) {
  final itemRoute = route(id);
  final departures = [
    ScheduledDepartureEvidence(
      tripId: '$id-1',
      serviceDate: start,
      departureSeconds: 0,
      scheduledAt: start,
      referenceStopId: 'S',
      referenceStopSequence: 1,
    ),
    if (eligible)
      ScheduledDepartureEvidence(
        tripId: '$id-2',
        serviceDate: start,
        departureSeconds: 600,
        scheduledAt: start.add(const Duration(minutes: 10)),
        referenceStopId: 'S',
        referenceStopSequence: 1,
      ),
  ];
  return BusFrequencyEvidence(
    routeId: id,
    periodStart: start,
    periodEnd: end,
    scheduledService: ScheduledServiceEvidence(
      route: itemRoute,
      periodStart: start,
      periodEnd: end,
      directionGroups: [
        ScheduledDirectionEvidence(
          directionId: 0,
          departures: departures,
          headwaysSeconds: eligible ? const [600] : const [],
          hourlyBuckets: const [],
          averageHeadwaySeconds: eligible ? 600 : null,
          medianHeadwaySeconds: eligible ? 600 : null,
          minimumHeadwaySeconds: eligible ? 600 : null,
          maximumHeadwaySeconds: eligible ? 600 : null,
        ),
      ],
      incompleteTripIds: const [],
      status: eligible
          ? ScheduledServiceEvidenceStatus.available
          : ScheduledServiceEvidenceStatus.insufficientForHeadway,
      hasCompleteDirectionData: true,
    ),
    operational: AiOperationalEvidence(
      route: itemRoute,
      periodStart: start,
      periodEnd: end,
      peakOperationSummary: PeakOperationSummary(
        routeId: id,
        periodStart: start,
        periodEnd: end,
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
    ),
    feedback: const BusFrequencyFeedbackEvidence(
      records: [],
      countByIssueType: {},
      frequencyRelevantRecords: [],
    ),
  );
}

BusFrequencyRecommendationResult success(
  List<String> ids, {
  bool includeInsufficient = false,
}) {
  final actionable = includeInsufficient ? ids.take(1).toList() : ids;
  final remaining = includeInsufficient
      ? ids.skip(1).toList()
      : const <String>[];
  BusFrequencyRecommendationGroup group(
    BusFrequencyRecommendationAction action,
    List<String> routeIds,
  ) => BusFrequencyRecommendationGroup(
    action: action,
    routeRecommendations: [
      for (final id in routeIds)
        BusFrequencyRouteRecommendationRecord(
          routeId: id,
          action: action,
          conciseRationale: 'Scheduled evidence supports this action.',
          evidenceRefs: ['route.$id.scheduled.summary'],
          limitations: const ['Operational coverage is limited.'],
          source: BusFrequencyRecommendationSource.gemini,
        ),
    ],
    source: BusFrequencyRecommendationSource.gemini,
  );
  return BusFrequencyRecommendationResult(
    status: BusFrequencyRecommendationStatus.available,
    synthesis: BusFrequencyRecommendationSynthesis(
      overallSummary: 'Overall evidence-grounded summary.',
      routeRecommendations: const [],
      recommendationGroups: [
        group(BusFrequencyRecommendationAction.maintainService, actionable),
      ],
      needsMoreEvidence: remaining.isEmpty
          ? null
          : group(
              BusFrequencyRecommendationAction.insufficientEvidence,
              remaining,
            ),
    ),
    failure: null,
    payload: null,
  );
}

BusFrequencyRecommendationResult groupedResult(
  List<(BusFrequencyRecommendationAction, List<String>)> groups, {
  String overallSummary = 'Overall evidence-grounded summary.',
}) {
  BusFrequencyRecommendationGroup group(
    BusFrequencyRecommendationAction action,
    List<String> routeIds,
  ) => BusFrequencyRecommendationGroup(
    action: action,
    routeRecommendations: [
      for (final id in routeIds)
        BusFrequencyRouteRecommendationRecord(
          routeId: id,
          action: action,
          conciseRationale: 'Scheduled evidence supports this action.',
          evidenceRefs: ['route.$id.scheduled.summary'],
          limitations: const ['Operational coverage is limited.'],
          source: BusFrequencyRecommendationSource.gemini,
        ),
    ],
    source: BusFrequencyRecommendationSource.gemini,
  );
  return BusFrequencyRecommendationResult(
    status: BusFrequencyRecommendationStatus.available,
    synthesis: BusFrequencyRecommendationSynthesis(
      overallSummary: overallSummary,
      routeRecommendations: const [],
      recommendationGroups: [
        for (final item in groups) group(item.$1, item.$2),
      ],
      needsMoreEvidence: null,
    ),
    failure: null,
    payload: null,
  );
}

class FakeRoutes implements RoutePerformanceRepository {
  FakeRoutes(List<String> ids) : routes = ids.map(route).toList();
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

class FakeEvidence implements BusFrequencyEvidenceRepository {
  FakeEvidence(this.values, {this.failures = const {}});
  final Map<String, BusFrequencyEvidence> values;
  final Set<String> failures;
  @override
  Future<BusFrequencyEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    if (failures.contains(routeId)) throw StateError('failure');
    return values[routeId]!;
  }
}

class ConcurrentEvidence implements BusFrequencyEvidenceRepository {
  int active = 0;
  int maximumActive = 0;

  @override
  Future<BusFrequencyEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    active++;
    if (active > maximumActive) maximumActive = active;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    active--;
    return evidence(routeId);
  }
}

class FakeRecommendations implements BusFrequencyRecommendationRepository {
  int calls = 0;
  final evidenceHistory = <List<BusFrequencyEvidence>>[];
  @override
  Future<BusFrequencyRecommendationResult> generate({
    required List<BusFrequencyEvidence> evidence,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    calls++;
    evidenceHistory.add(evidence);
    return success(evidence.map((item) => item.routeId).toList());
  }
}

class FakeCoordinator extends BusFrequencyDashboardCoordinator {
  FakeCoordinator(
    this.items, {
    this.excluded = const [],
    this.gate,
    this.screenGate,
    this.firstFailure = false,
    this.includeInsufficient = false,
    this.resultOverride,
  }) : super(
         routeRepository: FakeRoutes(const []),
         evidenceRepository: FakeEvidence(const {}),
         recommendationRepository: FakeRecommendations(),
       );
  final List<BusFrequencyDashboardCandidate> items;
  final List<BusFrequencyDashboardExcludedRoute> excluded;
  final Completer<void>? gate;
  final Completer<void>? screenGate;
  final bool firstFailure;
  final bool includeInsufficient;
  final BusFrequencyRecommendationResult? resultOverride;
  int screenCalls = 0;
  int analysisCalls = 0;
  List<String> lastCandidateIds = const [];

  @override
  Future<BusFrequencyDashboardScreeningResult> screenRoutes({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    screenCalls++;
    if (screenGate != null) await screenGate!.future;
    return BusFrequencyDashboardScreeningResult(
      routesAnalysed: items.length + excluded.length,
      candidates: items,
      excludedRoutes: excluded,
    );
  }

  @override
  Future<BusFrequencyRecommendationResult> analyse({
    required List<BusFrequencyDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    analysisCalls++;
    lastCandidateIds = candidates.map((item) => item.route.routeId).toList();
    if (gate != null) await gate!.future;
    if (firstFailure && analysisCalls == 1) {
      return const BusFrequencyRecommendationResult(
        status: BusFrequencyRecommendationStatus.temporarilyUnavailable,
        synthesis: null,
        failure: BusFrequencyRecommendationFailure.network,
        payload: null,
      );
    }
    return resultOverride ??
        success(lastCandidateIds, includeInsufficient: includeInsufficient);
  }

  @override
  Future<BusFrequencyRecommendationResult> retry({
    required List<BusFrequencyDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) => analyse(
    candidates: candidates,
    startUtc: startUtc,
    endExclusiveUtc: endExclusiveUtc,
  );
}

class RecordingManagementRepository
    implements RecommendationManagementRepository {
  RecordingManagementRepository({this.gate});

  final Completer<void>? gate;
  int busFrequencySaveCalls = 0;

  @override
  Future<SavedRecommendation> saveBusFrequencyRecommendation({
    required BusFrequencyRouteRecommendationRecord recommendation,
    required String routeDisplayLabel,
    required DateTime periodStart,
    required DateTime periodEnd,
    required BusFrequencyEvidence evidence,
  }) async {
    busFrequencySaveCalls++;
    if (gate != null) await gate!.future;
    return _savedRecommendation(recommendation.routeId, routeDisplayLabel);
  }

  @override
  Future<SavedRecommendation> saveRouteBusStopRecommendation({
    required RouteStopRecommendationRecord recommendation,
    required String routeDisplayLabel,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DistrictRouteStopEvidence evidence,
  }) => throw UnimplementedError();

  @override
  Future<List<SavedRecommendation>> loadSavedRecommendations() async =>
      const [];

  @override
  Future<SavedRecommendation> updateRecommendation({
    required SavedRecommendation recommendation,
    required RecommendationReviewStatus status,
    required String? adminNote,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteRecommendation(String recommendationId) =>
      throw UnimplementedError();
}

SavedRecommendation _savedRecommendation(String routeId, String routeLabel) =>
    SavedRecommendation(
      recommendationId: 'saved-$routeId',
      feature: RecommendationManagementFeature.busFrequency,
      routeId: routeId,
      routeDisplayLabel: routeLabel,
      actions: const ['maintainService'],
      title: 'Maintain service — $routeLabel',
      rationale: 'Validated rationale.',
      limitations: const [],
      evidenceReferences: const [],
      targetStopIds: const [],
      candidateArea: null,
      status: RecommendationReviewStatus.pending,
      adminNote: null,
      createdAt: DateTime(2026, 9, 10),
      updatedAt: null,
      reviewedAt: null,
    );
