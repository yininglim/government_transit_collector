import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_evidence_payloads.dart';

enum BusFrequencyRecommendationAction {
  increasePeakHourFrequency,
  maintainService,
  decreaseService,
  insufficientEvidence,
}

enum BusFrequencyRecommendationStatus {
  available,
  insufficientEvidence,
  temporarilyUnavailable,
  invalidAiResponse,
}

enum BusFrequencyRecommendationFailure {
  evidenceUnavailable,
  routeLimitExceeded,
  geminiNotConfigured,
  timeout,
  rateLimited,
  authentication,
  network,
  http,
  malformedResponse,
  invalidResponse,
  unknownRoute,
  unknownEvidenceReference,
}

enum BusFrequencyRecommendationSource { gemini }

class BusFrequencyRecommendationGroup {
  const BusFrequencyRecommendationGroup({
    required this.action,
    required this.summary,
    required this.rationale,
    required this.evidenceReferences,
    required this.limitations,
    required this.routeIds,
    required this.source,
  });

  final BusFrequencyRecommendationAction action;
  final String summary;
  final List<String> rationale;
  final List<String> evidenceReferences;
  final List<String> limitations;
  final List<String> routeIds;
  final BusFrequencyRecommendationSource source;
}

class BusFrequencyRecommendationSynthesis {
  const BusFrequencyRecommendationSynthesis({
    required this.overallSummary,
    required this.recommendationGroups,
    required this.needsMoreEvidence,
  });

  final String overallSummary;
  final List<BusFrequencyRecommendationGroup> recommendationGroups;
  final BusFrequencyRecommendationGroup? needsMoreEvidence;
}

class BusFrequencyRecommendationResult {
  const BusFrequencyRecommendationResult({
    required this.status,
    required this.synthesis,
    required this.failure,
    required this.payload,
    this.httpStatusCode,
  });

  final BusFrequencyRecommendationStatus status;
  final BusFrequencyRecommendationSynthesis? synthesis;
  final BusFrequencyRecommendationFailure? failure;
  final BusFrequencyGeminiEvidencePayload? payload;
  final int? httpStatusCode;
}

class BusFrequencyRecommendationValidationException implements Exception {
  const BusFrequencyRecommendationValidationException({required this.failure});

  final BusFrequencyRecommendationFailure failure;
}
