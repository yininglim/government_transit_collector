import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/bus_frequency_recommendation_page.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

void main() {
  group('coordinator', () {
    test(
      'screens deterministically and orders eligible routes by display name',
      () async {
        final evidenceRepository = FakeEvidenceRepository({
          'B': evidence('B', headway: true),
          'A': evidence('A', headway: false),
          'C': evidence('C', operationalCount: 1),
        });
        final coordinator = BusFrequencyDashboardCoordinator(
          routeRepository: FakeRouteRepository(const [
            RoutePerformanceRoute(routeId: 'B', shortName: 'B', longName: null),
            RoutePerformanceRoute(routeId: 'C', shortName: 'C', longName: null),
            RoutePerformanceRoute(routeId: 'A', shortName: 'A', longName: null),
          ]),
          evidenceRepository: evidenceRepository,
          recommendationRepository: FakeRecommendationRepository(),
        );

        final candidates = await coordinator.screenCandidates(
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

        expect(candidates.map((item) => item.route.routeId), ['B', 'C']);
        expect(evidenceRepository.periods.toSet(), {(periodStart, periodEnd)});
      },
    );

    test(
      'retains deterministic exclusions and evidence loading failures',
      () async {
        final evidenceRepository = FakeEvidenceRepository(
          {'A': evidence('A', headway: true), 'B': evidence('B')},
          failingRouteIds: const {'C'},
        );
        final coordinator = BusFrequencyDashboardCoordinator(
          routeRepository: FakeRouteRepository(const [
            RoutePerformanceRoute(routeId: 'A', shortName: 'A', longName: null),
            RoutePerformanceRoute(routeId: 'B', shortName: 'B', longName: null),
            RoutePerformanceRoute(routeId: 'C', shortName: 'C', longName: null),
          ]),
          evidenceRepository: evidenceRepository,
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
          BusFrequencyDashboardExclusionReason.noSupportingEvidence,
          BusFrequencyDashboardExclusionReason.evidenceLoadingFailure,
        ]);
        expect(result.excludedRoutes.first.evidence, isNotNull);
        expect(result.excludedRoutes.last.evidence, isNull);
      },
    );

    test('analyses no more than three routes with concurrency two', () async {
      final recommendationRepository = FakeRecommendationRepository();
      final coordinator = BusFrequencyDashboardCoordinator(
        routeRepository: FakeRouteRepository(const []),
        evidenceRepository: FakeEvidenceRepository(const {}),
        recommendationRepository: recommendationRepository,
      );
      final batchCandidates = candidates(4);

      final entries = await coordinator.analyseBatch(
        candidates: batchCandidates,
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      expect(entries.length, 3);
      expect(recommendationRepository.routeIds, ['R1', 'R2', 'R3']);
      expect(recommendationRepository.maximumConcurrentCalls, 2);
      expect(recommendationRepository.evidence, [
        batchCandidates[0].evidence,
        batchCandidates[1].evidence,
        batchCandidates[2].evidence,
      ]);
    });

    test('starts the third route after a slot and preserves order', () async {
      final recommendationRepository = ControlledRecommendationRepository(
        failingRouteId: 'R2',
      );
      final coordinator = BusFrequencyDashboardCoordinator(
        routeRepository: FakeRouteRepository(const []),
        evidenceRepository: FakeEvidenceRepository(const {}),
        recommendationRepository: recommendationRepository,
      );
      final completedRouteIds = <String>[];

      final pending = coordinator.analyseBatch(
        candidates: candidates(3),
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
        onCompleted: (_, _, entry) {
          completedRouteIds.add(entry.route.routeId);
        },
      );
      await Future<void>.delayed(Duration.zero);

      expect(recommendationRepository.routeIds, ['R1', 'R2']);
      expect(recommendationRepository.maximumConcurrentCalls, 2);
      recommendationRepository.complete('R2');
      await Future<void>.delayed(Duration.zero);
      expect(recommendationRepository.routeIds, ['R1', 'R2', 'R3']);

      recommendationRepository.complete('R3');
      recommendationRepository.complete('R1');
      final entries = await pending;

      expect(entries.map((entry) => entry.route.routeId), ['R1', 'R2', 'R3']);
      expect(completedRouteIds, ['R1', 'R2', 'R3']);
      expect(
        entries[0].result.status,
        BusFrequencyRecommendationStatus.available,
      );
      expect(
        entries[1].result.status,
        BusFrequencyRecommendationStatus.temporarilyUnavailable,
      );
      expect(
        entries[2].result.status,
        BusFrequencyRecommendationStatus.available,
      );
    });

    test('supports one-route and two-route batches', () async {
      for (final count in [1, 2]) {
        final recommendations = FakeRecommendationRepository();
        final coordinator = BusFrequencyDashboardCoordinator(
          routeRepository: FakeRouteRepository(const []),
          evidenceRepository: FakeEvidenceRepository(const {}),
          recommendationRepository: recommendations,
        );

        final entries = await coordinator.analyseBatch(
          candidates: candidates(count),
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

        expect(entries, hasLength(count));
        expect(recommendations.maximumConcurrentCalls, count);
      }
    });

    test('retry analyses one route with its retained evidence', () async {
      final recommendations = FakeRecommendationRepository();
      final coordinator = BusFrequencyDashboardCoordinator(
        routeRepository: FakeRouteRepository(const []),
        evidenceRepository: FakeEvidenceRepository(const {}),
        recommendationRepository: recommendations,
      );
      final candidate = candidates(1).single;

      final entry = await coordinator.retry(
        candidate: candidate,
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      expect(entry.route.routeId, 'R1');
      expect(recommendations.routeIds, ['R1']);
      expect(recommendations.evidence.single, same(candidate.evidence));
    });
  });

  testWidgets('shows fixed period without route or date selectors', (
    tester,
  ) async {
    await pumpDashboard(tester, FakeDashboardCoordinator(candidates: const []));

    expect(find.text('Past 30 Days'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<Object>), findsNothing);
    expect(find.text('Today'), findsNothing);
    expect(find.text('Last 7 Days'), findsNothing);
    expect(find.text('Custom'), findsNothing);
  });

  testWidgets('zero eligible routes makes no recommendation calls', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(candidates: const []);
    await pumpDashboard(tester, coordinator);
    await tester.pumpAndSettle();

    expect(coordinator.analysisRouteIds, isEmpty);
    expect(coordinator.screenStartUtc, periodStart);
    expect(coordinator.screenEndUtc, periodEnd);
    expect(find.text('Eligible Routes'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('generate-ai-recommendation')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('generate-ai-recommendation')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('prepares evidence before an explicit Gemini action', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(
      candidates: candidates(2),
      excludedRoutes: [
        BusFrequencyDashboardExcludedRoute(
          route: const RoutePerformanceRoute(
            routeId: 'R3',
            shortName: 'R3',
            longName: null,
          ),
          reason: BusFrequencyDashboardExclusionReason.noSupportingEvidence,
          evidence: evidence('R3'),
        ),
      ],
    );
    await pumpDashboard(tester, coordinator);
    await tester.pumpAndSettle();

    expect(coordinator.analysisRouteIds, isEmpty);
    expect(
      find.byKey(const Key('frequency-evidence-overview')),
      findsOneWidget,
    );
    expect(find.text('Routes Analysed'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Eligible Routes'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Limited / Excluded Routes'), findsOneWidget);

    final evidenceDetails = find.byKey(const Key('view-evidence-details'));
    await tester.ensureVisible(evidenceDetails);
    await tester.pumpAndSettle();
    await tester.tap(evidenceDetails);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('frequency-evidence-details')), findsOneWidget);
    expect(coordinator.analysisRouteIds, isEmpty);
  });

  testWidgets('limited routes remain separate from recommendation cards', (
    tester,
  ) async {
    final excluded = BusFrequencyDashboardExcludedRoute(
      route: const RoutePerformanceRoute(
        routeId: 'LIMITED',
        shortName: 'A very long limited route name that must wrap safely',
        longName: null,
      ),
      reason: BusFrequencyDashboardExclusionReason.noSupportingEvidence,
      evidence: evidence('LIMITED'),
    );
    await pumpDashboard(
      tester,
      FakeDashboardCoordinator(
        candidates: candidates(1),
        excludedRoutes: [excluded],
      ),
    );
    await tester.pumpAndSettle();

    final limitedRoutes = find.byKey(const Key('view-limited-routes'));
    await tester.ensureVisible(limitedRoutes);
    await tester.pumpAndSettle();
    await tester.tap(limitedRoutes);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('limited-routes-details')), findsOneWidget);
    expect(
      find.textContaining('No headway, operational observation'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('route-result-LIMITED')), findsNothing);
  });

  testWidgets('first batch retains three results and leaves fourth queued', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(candidates: candidates(4));
    await pumpDashboard(tester, coordinator);

    await tapAnalyse(tester);
    await tester.pumpAndSettle();

    expect(coordinator.analysisRouteIds, ['R1', 'R2', 'R3']);
    expect(find.byKey(const Key('route-result-R1')), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('route-result-R3')),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    expect(find.byKey(const Key('route-result-R3')), findsOneWidget);
    expect(find.byKey(const Key('route-result-R4')), findsNothing);
    await tester.dragUntilVisible(
      find.text('3 of 4 eligible routes analysed'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    expect(find.text('3 of 4 eligible routes analysed'), findsOneWidget);
    expect(find.byKey(const Key('analyse-next-routes')), findsOneWidget);
  });

  testWidgets('next action processes only the remaining batch', (tester) async {
    final coordinator = FakeDashboardCoordinator(candidates: candidates(5));
    await pumpDashboard(tester, coordinator);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();

    expect(coordinator.analysisRouteIds, ['R1', 'R2', 'R3']);
    final next = find.byKey(const Key('analyse-next-routes'));
    await tester.dragUntilVisible(
      next,
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();

    expect(coordinator.analysisRouteIds, ['R1', 'R2', 'R3', 'R4', 'R5']);
    await tester.dragUntilVisible(
      find.text('5 of 5 eligible routes analysed'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    expect(find.text('5 of 5 eligible routes analysed'), findsOneWidget);
  });

  testWidgets('renders all action cards and keeps route failures', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(
      candidates: candidates(3),
      results: {
        'R1': result(BusFrequencyRecommendationAction.increaseService),
        'R2': result(BusFrequencyRecommendationAction.maintainService),
        'R3': unavailable(),
      },
    );
    await pumpDashboard(tester, coordinator);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();

    expect(find.text('Increase Service'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('route-result-R3')),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    expect(find.text('Maintain Service'), findsOneWidget);
    expect(find.text('Recommendation Temporarily Unavailable'), findsOneWidget);
    expect(find.textContaining('API key'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(coordinator.analysisRouteIds, ['R1', 'R2', 'R3']);
  });

  testWidgets('renders insufficient evidence as a valid recommendation card', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(
      candidates: candidates(1),
      results: {
        'R1': result(BusFrequencyRecommendationAction.insufficientEvidence),
      },
    );
    await pumpDashboard(tester, coordinator);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();

    expect(find.text('Insufficient Evidence'), findsOneWidget);
    expect(find.text('Evidence: Insufficient'), findsOneWidget);
    expect(find.text('Recommendation Temporarily Unavailable'), findsNothing);
  });

  testWidgets('details reuse generated result without another analysis call', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(candidates: candidates(1));
    await pumpDashboard(tester, coordinator);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    final calls = coordinator.analysisRouteIds.length;

    final details = find.byKey(const Key('view-details-R1'));
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recommendation-details')), findsOneWidget);
    expect(find.text('Rationale'), findsOneWidget);
    expect(find.textContaining('scheduled.summary'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Limitations'),
      find.byKey(const Key('recommendation-details')),
      const Offset(0, -200),
    );
    expect(find.text('Limitations'), findsOneWidget);
    expect(coordinator.analysisRouteIds.length, calls);
  });

  testWidgets('batch controls are disabled while sequential analysis runs', (
    tester,
  ) async {
    final gate = Completer<void>();
    final coordinator = FakeDashboardCoordinator(
      candidates: candidates(1),
      analysisGate: gate,
    );
    await pumpDashboard(tester, coordinator);

    await tapAnalyse(tester);
    await tester.pump();

    expect(find.byKey(const Key('analysis-progress')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('generate-ai-recommendation')),
          )
          .onPressed,
      isNull,
    );
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'rebuild does not analyse again and unsupported fields stay absent',
    (tester) async {
      final coordinator = FakeDashboardCoordinator(candidates: candidates(1));
      await pumpDashboard(tester, coordinator);
      await tapAnalyse(tester);
      await tester.pumpAndSettle();
      final calls = coordinator.analysisRouteIds.length;

      await tester.pumpWidget(
        MaterialApp(
          home: BusFrequencyRecommendationPage(
            coordinator: coordinator,
            now: fixedNow,
          ),
        ),
      );
      await tester.pump();

      expect(coordinator.analysisRouteIds.length, calls);
      for (final text in [
        'Recommended headway',
        'Recommended frequency',
        'Required buses',
        'Passenger demand',
        'Occupancy',
        'Capacity',
      ]) {
        expect(find.textContaining(text), findsNothing);
      }
    },
  );

  testWidgets(
    'recreated page restores results and continues with the next candidates',
    (tester) async {
      final session = BusFrequencyDashboardSession();
      final coordinator = FakeDashboardCoordinator(candidates: candidates(5));
      await pumpDashboard(tester, coordinator, session: session);
      await tapAnalyse(tester);
      await tester.pumpAndSettle();
      expect(coordinator.analysisRouteIds, ['R1', 'R2', 'R3']);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      await pumpDashboard(tester, coordinator, session: session);

      expect(find.byKey(const Key('route-result-R1')), findsOneWidget);
      expect(coordinator.analysisRouteIds, ['R1', 'R2', 'R3']);
      final next = find.byKey(const Key('analyse-next-routes'));
      await tester.dragUntilVisible(
        next,
        find.byType(ListView).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(coordinator.analysisRouteIds, ['R1', 'R2', 'R3', 'R4', 'R5']);
    },
  );

  testWidgets('new analysis replaces the retained session identity', (
    tester,
  ) async {
    var now = fixedNow();
    final session = BusFrequencyDashboardSession();
    final coordinator = FakeDashboardCoordinator(candidates: candidates(1));
    await tester.pumpWidget(
      MaterialApp(
        home: BusFrequencyRecommendationPage(
          session: session,
          coordinator: coordinator,
          now: () => now,
        ),
      ),
    );
    await tester.pump();
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    final firstStart = session.periodStartUtc;
    expect(session.entries, hasLength(1));

    now = now.add(const Duration(days: 1));
    final newAnalysis = find.byKey(const Key('analyse-routes'));
    await tester.ensureVisible(newAnalysis);
    await tester.pumpAndSettle();
    await tester.tap(newAnalysis);
    await tester.pumpAndSettle();

    expect(session.periodStartUtc, firstStart!.add(const Duration(days: 1)));
    expect(session.entries, isEmpty);
    expect(coordinator.analysisRouteIds, ['R1']);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(session.entries, hasLength(1));
    expect(coordinator.analysisRouteIds, ['R1', 'R1']);
  });

  testWidgets('repeated generation taps do not start duplicate batches', (
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

  testWidgets('short landscape and long content remain scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final longRoute = BusFrequencyDashboardCandidate(
      route: const RoutePerformanceRoute(
        routeId: 'LONG',
        shortName: 'An exceptionally long bus frequency route name',
        longName: 'with additional descriptive text for responsive layout',
      ),
      evidence: evidence('LONG', headway: true),
    );

    await pumpDashboard(
      tester,
      FakeDashboardCoordinator(candidates: [longRoute]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> pumpDashboard(
  WidgetTester tester,
  BusFrequencyDashboardCoordinator coordinator, {
  BusFrequencyDashboardSession? session,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BusFrequencyRecommendationPage(
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
  final button = find.byKey(const Key('generate-ai-recommendation'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

DateTime fixedNow() => DateTime.utc(2026, 8, 28, 4);
final periodStart = DateTime.utc(2026, 7, 29, 16);
final periodEnd = DateTime.utc(2026, 8, 28, 16);

List<BusFrequencyDashboardCandidate> candidates(int count) => List.generate(
  count,
  (index) {
    final id = 'R${index + 1}';
    return BusFrequencyDashboardCandidate(
      route: RoutePerformanceRoute(routeId: id, shortName: id, longName: null),
      evidence: evidence(id, headway: true),
    );
  },
);

BusFrequencyEvidence evidence(
  String routeId, {
  bool headway = false,
  int operationalCount = 0,
}) {
  final route = RoutePerformanceRoute(
    routeId: routeId,
    shortName: routeId,
    longName: null,
  );
  final departures = [
    ScheduledDepartureEvidence(
      tripId: '$routeId-trip-1',
      serviceDate: periodStart,
      departureSeconds: 21600,
      scheduledAt: periodStart,
      referenceStopId: 'stop',
      referenceStopSequence: 1,
    ),
    if (headway)
      ScheduledDepartureEvidence(
        tripId: '$routeId-trip-2',
        serviceDate: periodStart,
        departureSeconds: 22200,
        scheduledAt: periodStart.add(const Duration(minutes: 10)),
        referenceStopId: 'stop',
        referenceStopSequence: 1,
      ),
  ];
  return BusFrequencyEvidence(
    routeId: routeId,
    periodStart: periodStart,
    periodEnd: periodEnd,
    scheduledService: ScheduledServiceEvidence(
      route: route,
      periodStart: periodStart,
      periodEnd: periodEnd,
      directionGroups: [
        ScheduledDirectionEvidence(
          directionId: 0,
          departures: departures,
          headwaysSeconds: headway ? const [600] : const [],
          hourlyBuckets: const [],
          averageHeadwaySeconds: headway ? 600 : null,
          medianHeadwaySeconds: headway ? 600 : null,
          minimumHeadwaySeconds: headway ? 600 : null,
          maximumHeadwaySeconds: headway ? 600 : null,
        ),
      ],
      incompleteTripIds: const [],
      status: headway
          ? ScheduledServiceEvidenceStatus.available
          : ScheduledServiceEvidenceStatus.insufficientForHeadway,
      hasCompleteDirectionData: true,
    ),
    operational: AiOperationalEvidence(
      route: route,
      periodStart: periodStart,
      periodEnd: periodEnd,
      peakOperationSummary: PeakOperationSummary(
        routeId: routeId,
        periodStart: periodStart,
        periodEnd: periodEnd,
        observationCount: operationalCount,
        distinctTripOccurrences: operationalCount,
        observedDayCount: operationalCount,
        routesRepresented: operationalCount,
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

BusFrequencyRecommendationResult result(
  BusFrequencyRecommendationAction action,
) => BusFrequencyRecommendationResult(
  status: action == BusFrequencyRecommendationAction.insufficientEvidence
      ? BusFrequencyRecommendationStatus.insufficientEvidence
      : BusFrequencyRecommendationStatus.available,
  recommendation: BusFrequencyRecommendation(
    action: action,
    summary: 'Evidence-grounded route result.',
    rationale: const ['Scheduled evidence supports this result.'],
    evidenceReferences: const ['scheduled.summary'],
    limitations: const ['Operational coverage is limited.'],
    evidenceSufficiency:
        action == BusFrequencyRecommendationAction.insufficientEvidence
        ? BusFrequencyEvidenceSufficiency.insufficient
        : BusFrequencyEvidenceSufficiency.limited,
    source: BusFrequencyRecommendationSource.gemini,
  ),
  failure: null,
  evidence: null,
  payload: null,
);

BusFrequencyRecommendationResult unavailable() =>
    const BusFrequencyRecommendationResult(
      status: BusFrequencyRecommendationStatus.temporarilyUnavailable,
      recommendation: null,
      failure: BusFrequencyRecommendationFailure.network,
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

class FakeEvidenceRepository implements BusFrequencyEvidenceRepository {
  FakeEvidenceRepository(
    this.evidenceByRoute, {
    this.failingRouteIds = const {},
  });
  final Map<String, BusFrequencyEvidence> evidenceByRoute;
  final Set<String> failingRouteIds;
  final periods = <(DateTime, DateTime)>[];

  @override
  Future<BusFrequencyEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    periods.add((startUtc, endExclusiveUtc));
    if (failingRouteIds.contains(routeId)) throw StateError('load failure');
    return evidenceByRoute[routeId]!;
  }
}

class FakeRecommendationRepository
    implements BusFrequencyRecommendationRepository {
  final routeIds = <String>[];
  final evidence = <BusFrequencyEvidence?>[];
  int activeCalls = 0;
  int maximumConcurrentCalls = 0;

  @override
  Future<BusFrequencyRecommendationResult> generate({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    BusFrequencyEvidence? evidence,
  }) async {
    routeIds.add(routeId);
    this.evidence.add(evidence);
    activeCalls++;
    if (activeCalls > maximumConcurrentCalls) {
      maximumConcurrentCalls = activeCalls;
    }
    await Future<void>.delayed(Duration.zero);
    activeCalls--;
    return result(BusFrequencyRecommendationAction.maintainService);
  }
}

class ControlledRecommendationRepository
    implements BusFrequencyRecommendationRepository {
  ControlledRecommendationRepository({this.failingRouteId});

  final String? failingRouteId;
  final routeIds = <String>[];
  final _completers = <String, Completer<void>>{};
  int activeCalls = 0;
  int maximumConcurrentCalls = 0;

  void complete(String routeId) => _completers[routeId]!.complete();

  @override
  Future<BusFrequencyRecommendationResult> generate({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    BusFrequencyEvidence? evidence,
  }) async {
    routeIds.add(routeId);
    activeCalls++;
    maximumConcurrentCalls = activeCalls > maximumConcurrentCalls
        ? activeCalls
        : maximumConcurrentCalls;
    final completer = Completer<void>();
    _completers[routeId] = completer;
    try {
      await completer.future;
      if (routeId == failingRouteId) throw StateError('route failure');
      return result(BusFrequencyRecommendationAction.maintainService);
    } finally {
      activeCalls--;
    }
  }
}

class FakeDashboardCoordinator extends BusFrequencyDashboardCoordinator {
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

  final List<BusFrequencyDashboardCandidate> candidates;
  final List<BusFrequencyDashboardExcludedRoute> excludedRoutes;
  final Map<String, BusFrequencyRecommendationResult> results;
  final Completer<void>? analysisGate;
  final analysisRouteIds = <String>[];
  int analyseBatchCalls = 0;
  DateTime? screenStartUtc;
  DateTime? screenEndUtc;

  @override
  Future<BusFrequencyDashboardScreeningResult> screenRoutes({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    screenStartUtc = startUtc;
    screenEndUtc = endExclusiveUtc;
    return BusFrequencyDashboardScreeningResult(
      routesAnalysed: candidates.length + excludedRoutes.length,
      candidates: candidates,
      excludedRoutes: excludedRoutes,
    );
  }

  @override
  Future<List<BusFrequencyDashboardCandidate>> screenCandidates({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    screenStartUtc = startUtc;
    screenEndUtc = endExclusiveUtc;
    return candidates;
  }

  @override
  Future<List<BusFrequencyDashboardEntry>> analyseBatch({
    required List<BusFrequencyDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    void Function(int completed, int total, BusFrequencyDashboardEntry entry)?
    onCompleted,
  }) async {
    analyseBatchCalls++;
    final batch = candidates.take(busFrequencyDashboardBatchSize).toList();
    if (analysisGate != null) await analysisGate!.future;
    final entries = <BusFrequencyDashboardEntry>[];
    for (var index = 0; index < batch.length; index++) {
      final candidate = batch[index];
      analysisRouteIds.add(candidate.route.routeId);
      final entry = BusFrequencyDashboardEntry(
        route: candidate.route,
        result:
            results[candidate.route.routeId] ??
            result(
              index == 2
                  ? BusFrequencyRecommendationAction.decreaseService
                  : index == 1
                  ? BusFrequencyRecommendationAction.maintainService
                  : BusFrequencyRecommendationAction.increaseService,
            ),
      );
      entries.add(entry);
      onCompleted?.call(index + 1, batch.length, entry);
    }
    return entries;
  }
}
