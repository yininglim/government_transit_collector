import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_evidence_payloads.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/cost_estimation_report_page.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

void main() {
  test('screens with the Part 6E gate and stable route ordering', () async {
    final evidenceRepository = FakeEvidenceRepository({
      'A': evidence('A'),
      'B': evidence(
        'B',
        priceAvailable: false,
        status: FuelCostCalculationStatus.fuelPriceUnavailable,
      ),
      'C': evidence('C', status: FuelCostCalculationStatus.partial),
    });
    final recommendationRepository = FakeRecommendationRepository();
    final coordinator = CostDashboardCoordinator(
      routeRepository: FakeRouteRepository([
        route('B'),
        route('A'),
        route('C'),
      ]),
      evidenceRepository: evidenceRepository,
      recommendationRepository: recommendationRepository,
    );

    final screened = await coordinator.screenCandidates(
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
      referenceDate: referenceDate,
    );

    expect(screened.map((item) => item.route.routeId), ['A', 'C']);
    expect(recommendationRepository.routeIds, isEmpty);
    expect(
      evidenceRepository.periods,
      everyElement((periodStart, periodEnd, referenceDate)),
    );
  });

  test('caps batches at three with recommendation concurrency two', () async {
    final recommendations = FakeRecommendationRepository();
    final coordinator = CostDashboardCoordinator(
      routeRepository: FakeRouteRepository(const []),
      evidenceRepository: FakeEvidenceRepository(const {}),
      recommendationRepository: recommendations,
    );
    final batchCandidates = candidates(4);
    await coordinator.analyseBatch(
      candidates: batchCandidates,
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
      referenceDate: referenceDate,
    );
    expect(recommendations.routeIds, ['R1', 'R2', 'R3']);
    expect(recommendations.maximumConcurrentCalls, 2);
    expect(recommendations.evidence, [
      batchCandidates[0].evidence,
      batchCandidates[1].evidence,
      batchCandidates[2].evidence,
    ]);
  });

  testWidgets('shows fixed period and requires an intentional action', (
    tester,
  ) async {
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
    expect(find.text('No eligible routes'), findsOneWidget);
    expect(coordinator.analysisRouteIds, isEmpty);
    expect(coordinator.screenStartUtc, periodStart);
    expect(coordinator.screenEndUtc, periodEnd);
    expect(coordinator.screenReferenceDate, referenceDate);
  });

  testWidgets('retains batches and waits for Analyse Next Routes', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(candidates: candidates(4));
    await pumpDashboard(tester, coordinator);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(coordinator.analysisRouteIds, ['R1', 'R2', 'R3']);
    expect(find.byKey(const Key('route-result-R1')), findsOneWidget);
    await reveal(tester, find.byKey(const Key('route-result-R3')));
    expect(find.byKey(const Key('route-result-R3')), findsOneWidget);
    expect(find.byKey(const Key('route-result-R4')), findsNothing);
    await tester.pump();
    expect(coordinator.analysisRouteIds.length, 3);

    await reveal(tester, find.byKey(const Key('analyse-next-routes')));
    await tester.tap(find.byKey(const Key('analyse-next-routes')));
    await tester.pumpAndSettle();
    expect(coordinator.analysisRouteIds, ['R1', 'R2', 'R3', 'R4']);
    await reveal(tester, find.byKey(const Key('route-result-R4')));
    expect(find.byKey(const Key('route-result-R4')), findsOneWidget);
  });

  testWidgets('renders every action, failure, and deterministic cost values', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(
      candidates: candidates(5),
      results: {
        'R1': result('R1', CostRecommendationAction.costEfficiencyReview),
        'R2': result('R2', CostRecommendationAction.fuelCostConcern),
        'R3': result('R3', CostRecommendationAction.maintainCurrentCostProfile),
        'R4': result('R4', CostRecommendationAction.insufficientEvidence),
        'R5': unavailable(),
      },
    );
    await pumpDashboard(tester, coordinator);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(find.text('Cost Efficiency Review'), findsOneWidget);
    expect(find.text('RM 12.01 – RM 15.89'), findsOneWidget);
    await reveal(tester, find.text('Fuel Cost Concern'));
    expect(find.text('Fuel Cost Concern'), findsOneWidget);
    await reveal(tester, find.text('Maintain Current Cost Profile'));
    expect(find.text('Maintain Current Cost Profile'), findsOneWidget);

    await reveal(tester, find.byKey(const Key('analyse-next-routes')));
    await tester.tap(find.byKey(const Key('analyse-next-routes')));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Insufficient Evidence'));
    expect(find.text('Insufficient Evidence'), findsOneWidget);
    await reveal(tester, find.text('Recommendation Temporarily Unavailable'));
    expect(find.text('Recommendation Temporarily Unavailable'), findsOneWidget);
  });

  testWidgets(
    'details use stored deterministic evidence without another call',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final coordinator = FakeDashboardCoordinator(
        candidates: candidates(1),
        results: {
          'R1': result('R1', CostRecommendationAction.costEfficiencyReview),
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
      expect(find.textContaining('cost.fuel_range'), findsOneWidget);
      await revealDetails(tester, find.text('Limitations'));
      expect(find.text('Limitations'), findsOneWidget);
      await revealDetails(tester, find.text('Deterministic Cost Evidence'));
      expect(find.text('Unavailable Cost Categories'), findsOneWidget);
      expect(find.textContaining('Driver and staff cost'), findsOneWidget);
      expect(find.textContaining('Maintenance cost'), findsOneWidget);
      await revealDetails(tester, find.text('RM 2.15 per litre'));
      expect(find.text('RM 2.15 per litre'), findsOneWidget);
      expect(find.text('2026-08-28'), findsOneWidget);
      expect(find.text('20.00'), findsOneWidget);
      expect(find.text('RM 12.01 – RM 15.89'), findsWidgets);
      expect(find.text('2'), findsWidgets);
      await revealDetails(
        tester,
        find.text('Fuel expenditure is only one component of operating cost.'),
      );
      expect(
        find.text('Fuel expenditure is only one component of operating cost.'),
        findsOneWidget,
      );
      expect(find.textContaining('Total Operating Cost'), findsNothing);
      expect(coordinator.analysisRouteIds.length, calls);
    },
  );

  testWidgets(
    'disables controls while running and rebuild does not call automatically',
    (tester) async {
      final gate = Completer<void>();
      final coordinator = FakeDashboardCoordinator(
        candidates: candidates(1),
        analysisGate: gate,
      );
      await pumpDashboard(tester, coordinator);
      await tapAnalyse(tester);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('analyse-routes')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('analysis-progress')), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: CostEstimationReportPage(
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

  testWidgets('retains success and retries only the failed route', (
    tester,
  ) async {
    final coordinator = FakeDashboardCoordinator(
      candidates: candidates(2),
      results: {
        'R1': result('R1', CostRecommendationAction.costEfficiencyReview),
        'R2': unavailable(),
      },
    );
    await pumpDashboard(tester, coordinator);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('route-result-R1')), findsOneWidget);
    await reveal(tester, find.byKey(const Key('retry-R2')));
    expect(coordinator.retryRouteIds, isEmpty);
    await tester.tap(find.byKey(const Key('retry-R2')));
    await tester.pumpAndSettle();
    expect(coordinator.retryRouteIds, ['R2']);
    expect(coordinator.analysisRouteIds, ['R1', 'R2']);

    for (final unsupported in [
      'Labour Cost',
      'Maintenance Cost',
      'Capital Cost',
      'Savings Amount',
      'Savings Percentage',
      'ROI',
      'Profitability',
      'Recommended Budget',
      'Fare Revenue',
      'Subsidy Impact',
    ]) {
      expect(find.textContaining(unsupported), findsNothing);
    }
  });

  testWidgets('recreated page restores cost results for the same date', (
    tester,
  ) async {
    final session = CostDashboardSession();
    final coordinator = FakeDashboardCoordinator(candidates: candidates(1));
    await pumpDashboard(tester, coordinator, session: session);
    await tapAnalyse(tester);
    await tester.pumpAndSettle();
    expect(coordinator.analysisRouteIds, ['R1']);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    await pumpDashboard(tester, coordinator, session: session);

    expect(find.byKey(const Key('route-result-R1')), findsOneWidget);
    expect(coordinator.analysisRouteIds, ['R1']);
    expect(session.referenceDate, referenceDate);
  });

  testWidgets('different reference date clears the retained cost session', (
    tester,
  ) async {
    final session = CostDashboardSession()
      ..begin(periodStart, periodEnd, referenceDate)
      ..candidates.addAll(candidates(1))
      ..entries.add(
        CostDashboardEntry(
          route: route('R1'),
          result: result('R1', CostRecommendationAction.costEfficiencyReview),
        ),
      )
      ..nextCandidateIndex = 1;
    final coordinator = FakeDashboardCoordinator(candidates: candidates(1));

    await tester.pumpWidget(
      MaterialApp(
        home: CostEstimationReportPage(
          session: session,
          coordinator: coordinator,
          now: () => fixedNow().add(const Duration(days: 1)),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('route-result-R1')), findsNothing);
    expect(session.referenceDate, isNull);
    expect(coordinator.analysisRouteIds, isEmpty);
  });
}

Future<void> pumpDashboard(
  WidgetTester tester,
  CostDashboardCoordinator coordinator, {
  CostDashboardSession? session,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CostEstimationReportPage(
        session: session,
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

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> revealDetails(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pump();
}

DateTime fixedNow() => DateTime.utc(2026, 8, 28, 4);
final periodStart = DateTime.utc(2026, 7, 29, 16);
final periodEnd = DateTime.utc(2026, 8, 28, 16);
final referenceDate = DateTime(2026, 8, 28);

RoutePerformanceRoute route(String id) =>
    RoutePerformanceRoute(routeId: id, shortName: id, longName: null);

List<CostDashboardCandidate> candidates(int count) =>
    List.generate(count, (index) {
      final id = 'R${index + 1}';
      return CostDashboardCandidate(route: route(id), evidence: evidence(id));
    });

FuelCostCalculationEvidence evidence(
  String routeId, {
  bool priceAvailable = true,
  FuelCostCalculationStatus status = FuelCostCalculationStatus.available,
}) => FuelCostCalculationEvidence(
  route: route(routeId),
  periodStart: periodStart,
  periodEnd: periodEnd,
  referenceDate: referenceDate,
  dieselPrice: DieselPriceEvidence(
    status: priceAvailable
        ? DieselPriceEvidenceStatus.available
        : DieselPriceEvidenceStatus.unavailable,
    source: fuelPriceSource,
    effectiveDate: priceAvailable ? referenceDate : null,
    rmPerLitre: priceAvailable ? 2.15 : null,
  ),
  benchmark: malaysianUrbanBusFuelConsumptionBenchmark,
  directionGroups: const [],
  totalScheduledDepartureCount: 2,
  costableScheduledDepartureCount: 2,
  uncostableDepartures: const [],
  scheduledVehicleKilometres: 20,
  lowEstimatedLitres: 5.588,
  highEstimatedLitres: 7.39,
  lowEstimatedFuelCostRm: priceAvailable ? 12.0142 : null,
  highEstimatedFuelCostRm: priceAvailable ? 15.8885 : null,
  status: status,
  scheduledServiceStatus: ScheduledServiceEvidenceStatus.available,
  incompleteTripIds: const [],
  hasCompleteDirectionData: true,
);

CostRecommendationResult result(
  String routeId,
  CostRecommendationAction action,
) {
  final costEvidence = evidence(routeId);
  return CostRecommendationResult(
    status: action == CostRecommendationAction.insufficientEvidence
        ? CostRecommendationStatus.insufficientEvidence
        : CostRecommendationStatus.available,
    recommendation: CostRecommendation(
      action: action,
      summary: 'Evidence-grounded fuel-cost result.',
      rationale: const ['Deterministic fuel evidence supports review.'],
      evidenceReferences: const ['cost.fuel_range'],
      limitations: const ['Labour and maintenance evidence is unavailable.'],
      evidenceSufficiency:
          action == CostRecommendationAction.insufficientEvidence
          ? CostEvidenceSufficiency.insufficient
          : CostEvidenceSufficiency.limited,
      source: CostRecommendationSource.gemini,
    ),
    failure: null,
    evidence: costEvidence,
    payload: const CostGeminiPayloadBuilder().build(costEvidence),
  );
}

CostRecommendationResult unavailable() => const CostRecommendationResult(
  status: CostRecommendationStatus.temporarilyUnavailable,
  recommendation: null,
  failure: CostRecommendationFailure.network,
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

class FakeEvidenceRepository implements FuelCostCalculationRepository {
  FakeEvidenceRepository(this.evidenceByRoute);
  final Map<String, FuelCostCalculationEvidence> evidenceByRoute;
  final periods = <(DateTime, DateTime, DateTime)>[];

  @override
  Future<FuelCostCalculationEvidence> calculate({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  }) async {
    periods.add((startUtc, endExclusiveUtc, referenceDate));
    return evidenceByRoute[routeId]!;
  }
}

class FakeRecommendationRepository implements CostRecommendationRepository {
  final routeIds = <String>[];
  final evidence = <FuelCostCalculationEvidence?>[];
  int activeCalls = 0;
  int maximumConcurrentCalls = 0;

  @override
  Future<CostRecommendationResult> generate({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
    FuelCostCalculationEvidence? evidence,
  }) async {
    routeIds.add(routeId);
    this.evidence.add(evidence);
    activeCalls++;
    maximumConcurrentCalls = activeCalls > maximumConcurrentCalls
        ? activeCalls
        : maximumConcurrentCalls;
    await Future<void>.delayed(Duration.zero);
    activeCalls--;
    return result(routeId, CostRecommendationAction.maintainCurrentCostProfile);
  }
}

class FakeDashboardCoordinator extends CostDashboardCoordinator {
  FakeDashboardCoordinator({
    required this.candidates,
    this.results = const {},
    this.analysisGate,
  }) : super(
         routeRepository: FakeRouteRepository(const []),
         evidenceRepository: FakeEvidenceRepository(const {}),
         recommendationRepository: FakeRecommendationRepository(),
       );

  final List<CostDashboardCandidate> candidates;
  final Map<String, CostRecommendationResult> results;
  final Completer<void>? analysisGate;
  final analysisRouteIds = <String>[];
  final retryRouteIds = <String>[];
  DateTime? screenStartUtc;
  DateTime? screenEndUtc;
  DateTime? screenReferenceDate;

  @override
  Future<List<CostDashboardCandidate>> screenCandidates({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  }) async {
    screenStartUtc = startUtc;
    screenEndUtc = endExclusiveUtc;
    screenReferenceDate = referenceDate;
    return candidates;
  }

  @override
  Future<List<CostDashboardEntry>> analyseBatch({
    required List<CostDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
    void Function(int completed, int total, CostDashboardEntry entry)?
    onCompleted,
  }) async {
    final batch = candidates.take(costDashboardBatchSize).toList();
    if (analysisGate != null) await analysisGate!.future;
    final entries = <CostDashboardEntry>[];
    for (var index = 0; index < batch.length; index++) {
      final candidate = batch[index];
      analysisRouteIds.add(candidate.route.routeId);
      final entry = CostDashboardEntry(
        route: candidate.route,
        result:
            results[candidate.route.routeId] ??
            result(
              candidate.route.routeId,
              CostRecommendationAction.costEfficiencyReview,
            ),
      );
      entries.add(entry);
      onCompleted?.call(index + 1, batch.length, entry);
    }
    return entries;
  }

  @override
  Future<CostDashboardEntry> retry({
    required CostDashboardCandidate candidate,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  }) async {
    retryRouteIds.add(candidate.route.routeId);
    return CostDashboardEntry(
      route: candidate.route,
      result: result(
        candidate.route.routeId,
        CostRecommendationAction.maintainCurrentCostProfile,
      ),
    );
  }
}
