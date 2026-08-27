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

    test('analyses no more than three routes sequentially', () async {
      final recommendationRepository = FakeRecommendationRepository();
      final coordinator = BusFrequencyDashboardCoordinator(
        routeRepository: FakeRouteRepository(const []),
        evidenceRepository: FakeEvidenceRepository(const {}),
        recommendationRepository: recommendationRepository,
      );

      final entries = await coordinator.analyseBatch(
        candidates: candidates(4),
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      expect(entries.length, 3);
      expect(recommendationRepository.routeIds, ['R1', 'R2', 'R3']);
      expect(recommendationRepository.maximumConcurrentCalls, 1);
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

    await tapAnalyse(tester);
    await tester.pumpAndSettle();

    expect(coordinator.analysisRouteIds, isEmpty);
    expect(coordinator.screenStartUtc, periodStart);
    expect(coordinator.screenEndUtc, periodEnd);
    expect(find.text('No eligible routes'), findsOneWidget);
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
          .widget<FilledButton>(find.byKey(const Key('analyse-routes')))
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
}

Future<void> pumpDashboard(
  WidgetTester tester,
  BusFrequencyDashboardCoordinator coordinator,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BusFrequencyRecommendationPage(
        coordinator: coordinator,
        now: fixedNow,
      ),
    ),
  );
  await tester.pump();
}

Future<void> tapAnalyse(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('analyse-routes')));
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
  FakeEvidenceRepository(this.evidenceByRoute);
  final Map<String, BusFrequencyEvidence> evidenceByRoute;
  final periods = <(DateTime, DateTime)>[];

  @override
  Future<BusFrequencyEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    periods.add((startUtc, endExclusiveUtc));
    return evidenceByRoute[routeId]!;
  }
}

class FakeRecommendationRepository
    implements BusFrequencyRecommendationRepository {
  final routeIds = <String>[];
  int activeCalls = 0;
  int maximumConcurrentCalls = 0;

  @override
  Future<BusFrequencyRecommendationResult> generate({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    routeIds.add(routeId);
    activeCalls++;
    if (activeCalls > maximumConcurrentCalls) {
      maximumConcurrentCalls = activeCalls;
    }
    await Future<void>.delayed(Duration.zero);
    activeCalls--;
    return result(BusFrequencyRecommendationAction.maintainService);
  }
}

class FakeDashboardCoordinator extends BusFrequencyDashboardCoordinator {
  FakeDashboardCoordinator({
    required this.candidates,
    this.results = const {},
    this.analysisGate,
  }) : super(
         routeRepository: FakeRouteRepository(const []),
         evidenceRepository: FakeEvidenceRepository(const {}),
         recommendationRepository: FakeRecommendationRepository(),
       );

  final List<BusFrequencyDashboardCandidate> candidates;
  final Map<String, BusFrequencyRecommendationResult> results;
  final Completer<void>? analysisGate;
  final analysisRouteIds = <String>[];
  DateTime? screenStartUtc;
  DateTime? screenEndUtc;

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
