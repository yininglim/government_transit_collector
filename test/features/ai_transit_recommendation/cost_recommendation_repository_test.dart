import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_data_source.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

void main() {
  for (final action in CostRecommendationAction.values) {
    test('accepts valid ${action.name} response', () async {
      final result = await repository(response: validResponse(action)).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
        referenceDate: referenceDate,
      );

      expect(
        result.status,
        action == CostRecommendationAction.insufficientEvidence
            ? CostRecommendationStatus.insufficientEvidence
            : CostRecommendationStatus.available,
      );
      expect(result.recommendation?.action, action);
    });
  }

  test('accepts sufficient and limited evidence responses', () async {
    for (final sufficiency in ['sufficient', 'limited']) {
      final response =
          validResponse(CostRecommendationAction.costEfficiencyReview)
            ..['evidenceSufficiency'] = sufficiency
            ..['limitations'] = sufficiency == 'limited'
                ? ['Fuel evidence is limited.']
                : <String>[];
      final result = await repository(response: response).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
        referenceDate: referenceDate,
      );
      expect(result.status, CostRecommendationStatus.available);
      expect(result.recommendation?.evidenceSufficiency.name, sufficiency);
    }
  });

  test('accepts submitted deterministic evidence references', () async {
    final response = validResponse(CostRecommendationAction.fuelCostConcern)
      ..['evidenceReferences'] = [
        'cost.diesel_price',
        'cost.scheduled_vehicle_km',
        'cost.fuel_range',
      ];
    final result = await repository(response: response).generate(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
      referenceDate: referenceDate,
    );
    expect(result.status, CostRecommendationStatus.available);
  });

  test('rejects unknown and duplicate evidence references', () async {
    for (final references in [
      ['cost.unknown'],
      ['cost.fuel_range', 'cost.fuel_range'],
      [''],
    ]) {
      final response = validResponse(
        CostRecommendationAction.costEfficiencyReview,
      )..['evidenceReferences'] = references;
      final result = await repository(response: response).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
        referenceDate: referenceDate,
      );
      expect(result.status, CostRecommendationStatus.invalidAiResponse);
      expect(
        result.failure,
        references.singleOrNull == 'cost.unknown'
            ? CostRecommendationFailure.unknownEvidenceReference
            : CostRecommendationFailure.invalidResponse,
      );
    }
  });

  test(
    'rejects missing fields, unknown properties, and fabricated numeric fields',
    () async {
      for (final mutation in <void Function(Map<String, dynamic>)>[
        (value) => value.remove('summary'),
        (value) => value['unexpected'] = true,
        (value) => value['recommendedCost'] = 100,
        (value) => value['savingsAmount'] = 20,
        (value) => value['savingsPercentage'] = 5,
        (value) => value['totalOperatingCost'] = 500,
        (value) => value['passengerDemand'] = 10,
        (value) => value['occupancy'] = 0.5,
        (value) => value['capacity'] = 40,
        (value) => value['fareRevenue'] = 100,
        (value) => value['subsidy'] = 50,
        (value) => value['roi'] = 2,
      ]) {
        final response = validResponse(
          CostRecommendationAction.costEfficiencyReview,
        );
        mutation(response);
        final result = await repository(response: response).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
          referenceDate: referenceDate,
        );
        expect(result.failure, CostRecommendationFailure.invalidResponse);
      }
    },
  );

  test('rejects invalid action and contradictory sufficiency', () async {
    final responses = [
      validResponse(CostRecommendationAction.costEfficiencyReview)
        ..['action'] = 'optimiseEverything',
      validResponse(CostRecommendationAction.costEfficiencyReview)
        ..['evidenceSufficiency'] = 'insufficient',
      validResponse(CostRecommendationAction.insufficientEvidence)
        ..['evidenceSufficiency'] = 'limited',
    ];
    for (final response in responses) {
      final result = await repository(response: response).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
        referenceDate: referenceDate,
      );
      expect(result.failure, CostRecommendationFailure.invalidResponse);
    }
  });

  test('maps malformed structured transport output safely', () async {
    final result =
        await repository(
          failure: GeminiTransportFailure.invalidStructuredJson,
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
          referenceDate: referenceDate,
        );
    expect(result.status, CostRecommendationStatus.invalidAiResponse);
    expect(result.failure, CostRecommendationFailure.malformedResponse);
  });

  test(
    'deterministic gate blocks missing diesel price and expenditure without Gemini',
    () async {
      for (final source in [
        evidence(
          priceAvailable: false,
          status: FuelCostCalculationStatus.fuelPriceUnavailable,
        ),
        evidence(includeExpenditure: false),
        evidence(
          costableCount: 0,
          status: FuelCostCalculationStatus.noCostableDepartures,
        ),
      ]) {
        final gemini = FakeGeminiDataSource(
          response: validResponse(
            CostRecommendationAction.costEfficiencyReview,
          ),
        );
        final result = await repository(gemini: gemini, sourceEvidence: source)
            .generate(
              routeId: 'J15',
              startUtc: periodStart,
              endExclusiveUtc: periodEnd,
              referenceDate: referenceDate,
            );
        expect(result.status, CostRecommendationStatus.insufficientEvidence);
        expect(
          result.recommendation?.source,
          CostRecommendationSource.deterministicGate,
        );
        expect(gemini.callCount, 0);
      }
    },
  );

  test(
    'partial evidence and unavailable labour or maintenance do not block fuel analysis',
    () async {
      final gemini = FakeGeminiDataSource(
        response: validResponse(CostRecommendationAction.costEfficiencyReview),
      );
      final result =
          await repository(
            gemini: gemini,
            sourceEvidence: evidence(status: FuelCostCalculationStatus.partial),
          ).generate(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
            referenceDate: referenceDate,
          );
      expect(result.status, CostRecommendationStatus.available);
      expect(gemini.callCount, 1);
      expect(
        result.payload?.toJson()['unavailable_cost_categories'],
        containsAll(['driver_staff_cost', 'maintenance_cost']),
      );
    },
  );

  for (final mapping in <(GeminiTransportFailure, CostRecommendationFailure)>[
    (GeminiTransportFailure.timeout, CostRecommendationFailure.timeout),
    (GeminiTransportFailure.rateLimited, CostRecommendationFailure.rateLimited),
    (
      GeminiTransportFailure.authentication,
      CostRecommendationFailure.authentication,
    ),
    (GeminiTransportFailure.network, CostRecommendationFailure.network),
    (GeminiTransportFailure.http, CostRecommendationFailure.http),
    (
      GeminiTransportFailure.notConfigured,
      CostRecommendationFailure.geminiNotConfigured,
    ),
  ]) {
    test('maps ${mapping.$1.name} safely without retry', () async {
      final gemini = FakeGeminiDataSource(
        failure: mapping.$1,
        statusCode: mapping.$1 == GeminiTransportFailure.http ? 503 : null,
      );
      final result = await repository(gemini: gemini).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
        referenceDate: referenceDate,
      );
      expect(result.status, CostRecommendationStatus.temporarilyUnavailable);
      expect(result.failure, mapping.$2);
      expect(
        result.httpStatusCode,
        mapping.$1 == GeminiTransportFailure.http ? 503 : null,
      );
      expect(gemini.callCount, 1);
    });
  }

  test('request uses Part 6B payload and strict non-numeric schema', () async {
    final gemini = FakeGeminiDataSource(
      response: validResponse(CostRecommendationAction.costEfficiencyReview),
    );
    await repository(gemini: gemini).generate(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
      referenceDate: referenceDate,
    );
    final request = gemini.request!;
    expect(request.input, contains('cost_estimation_evidence'));
    expect(request.input, contains('low_estimated_fuel_expenditure_rm'));
    expect(
      request.instructions,
      contains('Do not independently recalculate costs'),
    );
    expect(
      request.instructions,
      contains('Fuel expenditure is not total operating cost'),
    );
    final keys = _allKeys(request.responseSchema);
    for (final prohibited in [
      'recommendedCost',
      'targetCost',
      'savingsAmount',
      'savingsPercentage',
      'totalOperatingCost',
      'labourCost',
      'maintenanceCost',
      'capitalCost',
    ]) {
      expect(keys, isNot(contains(prohibited)));
    }
  });

  test('uses retained evidence without calculating it again', () async {
    final retainedEvidence = evidence();
    final evidenceRepository = FakeEvidenceRepository(retainedEvidence);
    final gemini = FakeGeminiDataSource(
      response: validResponse(CostRecommendationAction.costEfficiencyReview),
    );
    final recommendationRepository = DefaultCostRecommendationRepository(
      evidenceRepository: evidenceRepository,
      geminiDataSource: gemini,
    );

    final result = await recommendationRepository.generate(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
      referenceDate: referenceDate,
      evidence: retainedEvidence,
    );

    expect(evidenceRepository.callCount, 0);
    expect(result.evidence, same(retainedEvidence));
    expect(gemini.request!.input, contains('cost_estimation_evidence'));
    expect(result.payload!.toJson()['fuel_estimate'], isNotNull);
  });
}

final periodStart = DateTime.utc(2026, 7, 1);
final periodEnd = DateTime.utc(2026, 8, 1);
final referenceDate = DateTime.utc(2026, 8, 1);

DefaultCostRecommendationRepository repository({
  Map<String, dynamic>? response,
  GeminiTransportFailure? failure,
  FakeGeminiDataSource? gemini,
  FuelCostCalculationEvidence? sourceEvidence,
}) => DefaultCostRecommendationRepository(
  evidenceRepository: FakeEvidenceRepository(sourceEvidence ?? evidence()),
  geminiDataSource:
      gemini ??
      FakeGeminiDataSource(
        response:
            response ??
            validResponse(CostRecommendationAction.costEfficiencyReview),
        failure: failure,
      ),
);

Map<String, dynamic> validResponse(CostRecommendationAction action) => {
  'action': action.name,
  'summary': 'Review the deterministic fuel-cost evidence.',
  'rationale': ['The submitted fuel-cost range supports this result.'],
  'evidenceReferences': ['cost.fuel_range'],
  'limitations': action == CostRecommendationAction.insufficientEvidence
      ? ['Core fuel evidence is unavailable.']
      : ['Labour and maintenance costs are unavailable.'],
  'evidenceSufficiency': action == CostRecommendationAction.insufficientEvidence
      ? 'insufficient'
      : 'limited',
};

FuelCostCalculationEvidence evidence({
  bool priceAvailable = true,
  bool includeExpenditure = true,
  int costableCount = 2,
  FuelCostCalculationStatus status = FuelCostCalculationStatus.available,
}) => FuelCostCalculationEvidence(
  route: const RoutePerformanceRoute(
    routeId: 'J15',
    shortName: 'J15',
    longName: 'Johor Bahru route',
  ),
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
  costableScheduledDepartureCount: costableCount,
  uncostableDepartures: const [],
  scheduledVehicleKilometres: costableCount > 0 ? 20 : 0,
  lowEstimatedLitres: costableCount > 0 ? 5.588 : null,
  highEstimatedLitres: costableCount > 0 ? 7.39 : null,
  lowEstimatedFuelCostRm: includeExpenditure && priceAvailable ? 12.0142 : null,
  highEstimatedFuelCostRm: includeExpenditure && priceAvailable
      ? 15.8885
      : null,
  status: status,
  scheduledServiceStatus: ScheduledServiceEvidenceStatus.available,
  incompleteTripIds: const [],
  hasCompleteDirectionData: true,
);

Set<String> _allKeys(Object? value) {
  final keys = <String>{};
  if (value is Map<String, dynamic>) {
    keys.addAll(value.keys);
    for (final item in value.values) {
      keys.addAll(_allKeys(item));
    }
  } else if (value is List<dynamic>) {
    for (final item in value) {
      keys.addAll(_allKeys(item));
    }
  }
  return keys;
}

class FakeEvidenceRepository implements FuelCostCalculationRepository {
  FakeEvidenceRepository(this.result);
  final FuelCostCalculationEvidence result;
  int callCount = 0;

  @override
  Future<FuelCostCalculationEvidence> calculate({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  }) async {
    callCount++;
    return result;
  }
}

class FakeGeminiDataSource implements GeminiDataSource {
  FakeGeminiDataSource({this.response, this.failure, this.statusCode});
  final Map<String, dynamic>? response;
  final GeminiTransportFailure? failure;
  final int? statusCode;
  int callCount = 0;
  GeminiStructuredInteractionRequest? request;

  @override
  Future<GeminiStructuredInteractionResult> createStructuredInteraction(
    GeminiStructuredInteractionRequest request,
  ) async {
    callCount++;
    this.request = request;
    if (failure != null) {
      throw GeminiTransportException(
        failure: failure!,
        message: 'sanitised',
        statusCode: statusCode,
      );
    }
    return GeminiStructuredInteractionResult(
      interactionId: null,
      value: response!,
    );
  }
}
