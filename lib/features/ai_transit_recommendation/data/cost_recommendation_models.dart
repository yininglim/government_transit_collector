import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_evidence_payloads.dart';

enum CostRecommendationAction {
  costEfficiencyReview,
  fuelCostConcern,
  maintainCurrentCostProfile,
  insufficientEvidence,
}

enum CostEvidenceSufficiency { sufficient, limited, insufficient }

enum CostRecommendationStatus {
  available,
  insufficientEvidence,
  temporarilyUnavailable,
  invalidAiResponse,
}

enum CostRecommendationFailure {
  evidenceUnavailable,
  geminiNotConfigured,
  timeout,
  rateLimited,
  authentication,
  network,
  http,
  malformedResponse,
  invalidResponse,
  unknownEvidenceReference,
}

enum CostRecommendationSource { deterministicGate, gemini }

class CostRecommendation {
  const CostRecommendation({
    required this.action,
    required this.summary,
    required this.rationale,
    required this.evidenceReferences,
    required this.limitations,
    required this.evidenceSufficiency,
    required this.source,
  });

  final CostRecommendationAction action;
  final String summary;
  final List<String> rationale;
  final List<String> evidenceReferences;
  final List<String> limitations;
  final CostEvidenceSufficiency evidenceSufficiency;
  final CostRecommendationSource source;
}

class CostRecommendationResult {
  const CostRecommendationResult({
    required this.status,
    required this.recommendation,
    required this.failure,
    required this.evidence,
    required this.payload,
    this.httpStatusCode,
  });

  final CostRecommendationStatus status;
  final CostRecommendation? recommendation;
  final CostRecommendationFailure? failure;
  final FuelCostCalculationEvidence? evidence;
  final CostGeminiEvidencePayload? payload;
  final int? httpStatusCode;
}

class CostRecommendationValidationException implements Exception {
  const CostRecommendationValidationException({required this.failure});

  final CostRecommendationFailure failure;
}
