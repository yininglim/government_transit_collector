import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_evidence_payloads.dart';

enum BusFrequencyRecommendationAction {
  increaseService,
  maintainService,
  decreaseService,
  insufficientEvidence,
}

enum BusFrequencyEvidenceSufficiency { sufficient, limited, insufficient }

enum BusFrequencyRecommendationStatus {
  available,
  insufficientEvidence,
  temporarilyUnavailable,
  invalidAiResponse,
}

enum BusFrequencyRecommendationFailure {
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

enum BusFrequencyRecommendationSource { deterministicGate, gemini }

class BusFrequencyRecommendation {
  const BusFrequencyRecommendation({
    required this.action,
    required this.summary,
    required this.rationale,
    required this.evidenceReferences,
    required this.limitations,
    required this.evidenceSufficiency,
    required this.source,
  });

  final BusFrequencyRecommendationAction action;
  final String summary;
  final List<String> rationale;
  final List<String> evidenceReferences;
  final List<String> limitations;
  final BusFrequencyEvidenceSufficiency evidenceSufficiency;
  final BusFrequencyRecommendationSource source;
}

class BusFrequencyRecommendationResult {
  const BusFrequencyRecommendationResult({
    required this.status,
    required this.recommendation,
    required this.failure,
    required this.evidence,
    required this.payload,
    this.httpStatusCode,
  });

  final BusFrequencyRecommendationStatus status;
  final BusFrequencyRecommendation? recommendation;
  final BusFrequencyRecommendationFailure? failure;
  final BusFrequencyEvidence? evidence;
  final BusFrequencyGeminiEvidencePayload? payload;
  final int? httpStatusCode;
}

class BusFrequencyRecommendationValidationException implements Exception {
  const BusFrequencyRecommendationValidationException({required this.failure});

  final BusFrequencyRecommendationFailure failure;
}
