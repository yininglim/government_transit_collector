import 'dart:convert';

import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_data_source.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_evidence_payloads.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_models.dart';

const costRecommendationTimeout = Duration(seconds: 90);
const maxCostRationaleItems = 4;
const maxCostLimitationItems = 4;
const maxCostEvidenceReferenceItems = 8;
const maxCostSummaryLength = 240;
const maxCostItemLength = 240;
const maxCostIdentityLength = 160;

const costRecommendationInstructions = '''
Use only the supplied deterministic cost evidence and preserve every submitted value exactly.
Do not independently recalculate costs or invent cost values.
Do not infer missing labour, maintenance, capital, staffing, infrastructure, ticketing, passenger demand, occupancy, capacity, fare revenue, subsidy, total operating cost, profitability, savings, return on investment, or budget impact.
Fuel expenditure is not total operating cost.
Distinguish fuel expenditure from unavailable cost categories and recognise the supplied diesel price reference and effective dates.
Use only submitted evidence-reference IDs and clearly state unavailable categories and evidence limitations.
Choose insufficientEvidence when deterministic fuel-cost evidence cannot responsibly support a recommendation.
Return only the requested concise structured result and no hidden reasoning.
''';

const costRecommendationResponseSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'action': {
      'type': 'string',
      'enum': [
        'costEfficiencyReview',
        'fuelCostConcern',
        'maintainCurrentCostProfile',
        'insufficientEvidence',
      ],
    },
    'summary': {'type': 'string', 'maxLength': maxCostSummaryLength},
    'rationale': {
      'type': 'array',
      'maxItems': maxCostRationaleItems,
      'items': {'type': 'string', 'maxLength': maxCostItemLength},
    },
    'evidenceReferences': {
      'type': 'array',
      'maxItems': maxCostEvidenceReferenceItems,
      'items': {'type': 'string', 'maxLength': maxCostIdentityLength},
    },
    'limitations': {
      'type': 'array',
      'maxItems': maxCostLimitationItems,
      'items': {'type': 'string', 'maxLength': maxCostItemLength},
    },
    'evidenceSufficiency': {
      'type': 'string',
      'enum': ['sufficient', 'limited', 'insufficient'],
    },
  },
  'required': [
    'action',
    'summary',
    'rationale',
    'evidenceReferences',
    'limitations',
    'evidenceSufficiency',
  ],
  'additionalProperties': false,
};

abstract interface class CostRecommendationRepository {
  Future<CostRecommendationResult> generate({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
    FuelCostCalculationEvidence? evidence,
  });
}

class DefaultCostRecommendationRepository
    implements CostRecommendationRepository {
  DefaultCostRecommendationRepository({
    FuelCostCalculationRepository? evidenceRepository,
    CostGeminiPayloadBuilder? payloadBuilder,
    GeminiDataSource? geminiDataSource,
    this.requestTimeout = costRecommendationTimeout,
  }) : _evidenceRepository =
           evidenceRepository ?? DefaultFuelCostCalculationRepository(),
       _payloadBuilder = payloadBuilder ?? const CostGeminiPayloadBuilder(),
       _geminiDataSource =
           geminiDataSource ??
           GeminiInteractionsDataSource(requestTimeout: requestTimeout);

  final FuelCostCalculationRepository _evidenceRepository;
  final CostGeminiPayloadBuilder _payloadBuilder;
  final GeminiDataSource _geminiDataSource;
  final Duration requestTimeout;

  @override
  Future<CostRecommendationResult> generate({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
    FuelCostCalculationEvidence? evidence,
  }) async {
    late final FuelCostCalculationEvidence resolvedEvidence;
    try {
      resolvedEvidence = evidence == null
          ? await _evidenceRepository.calculate(
              routeId: routeId,
              startUtc: startUtc,
              endExclusiveUtc: endExclusiveUtc,
              referenceDate: referenceDate,
            )
          : _validatedEvidence(
              evidence,
              routeId: routeId,
              startUtc: startUtc,
              endExclusiveUtc: endExclusiveUtc,
              referenceDate: referenceDate,
            );
    } on Object {
      return const CostRecommendationResult(
        status: CostRecommendationStatus.temporarilyUnavailable,
        recommendation: null,
        failure: CostRecommendationFailure.evidenceUnavailable,
        evidence: null,
        payload: null,
      );
    }
    final payload = _payloadBuilder.build(resolvedEvidence);
    if (!hasUsableCostRecommendationEvidence(resolvedEvidence)) {
      return CostRecommendationResult(
        status: CostRecommendationStatus.insufficientEvidence,
        recommendation: const CostRecommendation(
          action: CostRecommendationAction.insufficientEvidence,
          summary:
              'Deterministic fuel-cost evidence is insufficient for assessment.',
          rationale: [
            'A usable diesel price and fuel-expenditure range are required.',
          ],
          evidenceReferences: [],
          limitations: [
            'Core deterministic fuel-cost evidence is unavailable.',
          ],
          evidenceSufficiency: CostEvidenceSufficiency.insufficient,
          source: CostRecommendationSource.deterministicGate,
        ),
        failure: null,
        evidence: resolvedEvidence,
        payload: payload,
      );
    }
    final payloadJson = payload.toJson();
    try {
      final response = await _geminiDataSource.createStructuredInteraction(
        GeminiStructuredInteractionRequest(
          input: jsonEncode(payloadJson),
          instructions: costRecommendationInstructions,
          responseSchema: costRecommendationResponseSchema,
        ),
      );
      final recommendation = parseCostRecommendation(
        response.value,
        payload: payloadJson,
      );
      return CostRecommendationResult(
        status:
            recommendation.action ==
                CostRecommendationAction.insufficientEvidence
            ? CostRecommendationStatus.insufficientEvidence
            : CostRecommendationStatus.available,
        recommendation: recommendation,
        failure: null,
        evidence: resolvedEvidence,
        payload: payload,
      );
    } on CostRecommendationValidationException catch (error) {
      return CostRecommendationResult(
        status: CostRecommendationStatus.invalidAiResponse,
        recommendation: null,
        failure: error.failure,
        evidence: resolvedEvidence,
        payload: payload,
      );
    } on GeminiTransportException catch (error) {
      return _transportFailure(
        error,
        evidence: resolvedEvidence,
        payload: payload,
      );
    }
  }
}

FuelCostCalculationEvidence _validatedEvidence(
  FuelCostCalculationEvidence evidence, {
  required String routeId,
  required DateTime startUtc,
  required DateTime endExclusiveUtc,
  required DateTime referenceDate,
}) {
  if (evidence.route.routeId != routeId ||
      !evidence.periodStart.isAtSameMomentAs(startUtc) ||
      !evidence.periodEnd.isAtSameMomentAs(endExclusiveUtc) ||
      !_sameDate(evidence.referenceDate, referenceDate)) {
    throw ArgumentError('The retained evidence does not match the request.');
  }
  return evidence;
}

bool _sameDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

bool hasUsableCostRecommendationEvidence(FuelCostCalculationEvidence evidence) {
  final usableStatus =
      evidence.status == FuelCostCalculationStatus.available ||
      evidence.status == FuelCostCalculationStatus.partial;
  final price = evidence.dieselPrice.rmPerLitre;
  final low = evidence.lowEstimatedFuelCostRm;
  final high = evidence.highEstimatedFuelCostRm;
  return evidence.route.routeId.trim().isNotEmpty &&
      usableStatus &&
      evidence.dieselPrice.isAvailable &&
      price != null &&
      price.isFinite &&
      price > 0 &&
      evidence.costableScheduledDepartureCount > 0 &&
      evidence.scheduledVehicleKilometres.isFinite &&
      evidence.scheduledVehicleKilometres > 0 &&
      low != null &&
      low.isFinite &&
      low >= 0 &&
      high != null &&
      high.isFinite &&
      high >= low;
}

CostRecommendation parseCostRecommendation(
  Map<String, dynamic> value, {
  required Map<String, dynamic> payload,
}) {
  const expectedKeys = {
    'action',
    'summary',
    'rationale',
    'evidenceReferences',
    'limitations',
    'evidenceSufficiency',
  };
  if (value.keys.toSet().difference(expectedKeys).isNotEmpty ||
      expectedKeys.difference(value.keys.toSet()).isNotEmpty) {
    _invalid();
  }
  final action = _action(value['action']);
  final sufficiency = _sufficiency(value['evidenceSufficiency']);
  final summary = _requiredString(value['summary'], maxCostSummaryLength);
  final rationale = _stringList(
    value['rationale'],
    maxItems: maxCostRationaleItems,
    allowEmpty: false,
  );
  final limitations = _stringList(
    value['limitations'],
    maxItems: maxCostLimitationItems,
    allowEmpty: true,
  );
  final references = _stringList(
    value['evidenceReferences'],
    maxItems: maxCostEvidenceReferenceItems,
    allowEmpty: false,
    maxLength: maxCostIdentityLength,
  );
  if (references.toSet().length != references.length) _invalid();
  final allowedReferences = (payload['evidence_references'] as List<dynamic>)
      .cast<String>()
      .toSet();
  if (references.any((reference) => !allowedReferences.contains(reference))) {
    throw const CostRecommendationValidationException(
      failure: CostRecommendationFailure.unknownEvidenceReference,
    );
  }
  final isInsufficient =
      action == CostRecommendationAction.insufficientEvidence;
  if (isInsufficient != (sufficiency == CostEvidenceSufficiency.insufficient) ||
      (sufficiency != CostEvidenceSufficiency.sufficient &&
          limitations.isEmpty)) {
    _invalid();
  }
  return CostRecommendation(
    action: action,
    summary: summary,
    rationale: List.unmodifiable(rationale),
    evidenceReferences: List.unmodifiable(references),
    limitations: List.unmodifiable(limitations),
    evidenceSufficiency: sufficiency,
    source: CostRecommendationSource.gemini,
  );
}

CostRecommendationAction _action(Object? value) =>
    CostRecommendationAction.values
        .where((item) => item.name == value)
        .firstOrNull ??
    _invalid();

CostEvidenceSufficiency _sufficiency(Object? value) =>
    CostEvidenceSufficiency.values
        .where((item) => item.name == value)
        .firstOrNull ??
    _invalid();

String _requiredString(Object? value, int maxLength) {
  if (value is! String || value.trim().isEmpty || value.length > maxLength) {
    _invalid();
  }
  return value.trim();
}

List<String> _stringList(
  Object? value, {
  required int maxItems,
  required bool allowEmpty,
  int maxLength = maxCostItemLength,
}) {
  if (value is! List<dynamic> ||
      value.length > maxItems ||
      (!allowEmpty && value.isEmpty)) {
    _invalid();
  }
  return value
      .map((item) => _requiredString(item, maxLength))
      .toList(growable: false);
}

Never _invalid() => throw const CostRecommendationValidationException(
  failure: CostRecommendationFailure.invalidResponse,
);

CostRecommendationResult _transportFailure(
  GeminiTransportException error, {
  required FuelCostCalculationEvidence evidence,
  required CostGeminiEvidencePayload payload,
}) {
  final mapped = switch (error.failure) {
    GeminiTransportFailure.notConfigured =>
      CostRecommendationFailure.geminiNotConfigured,
    GeminiTransportFailure.timeout => CostRecommendationFailure.timeout,
    GeminiTransportFailure.rateLimited => CostRecommendationFailure.rateLimited,
    GeminiTransportFailure.authentication =>
      CostRecommendationFailure.authentication,
    GeminiTransportFailure.malformedResponse ||
    GeminiTransportFailure.missingStructuredOutput ||
    GeminiTransportFailure.invalidStructuredJson =>
      CostRecommendationFailure.malformedResponse,
    GeminiTransportFailure.network => CostRecommendationFailure.network,
    GeminiTransportFailure.http => CostRecommendationFailure.http,
  };
  return CostRecommendationResult(
    status: mapped == CostRecommendationFailure.malformedResponse
        ? CostRecommendationStatus.invalidAiResponse
        : CostRecommendationStatus.temporarilyUnavailable,
    recommendation: null,
    failure: mapped,
    evidence: evidence,
    payload: payload,
    httpStatusCode: error.failure == GeminiTransportFailure.http
        ? error.statusCode
        : null,
  );
}
