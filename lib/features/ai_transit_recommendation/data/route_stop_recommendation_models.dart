import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_evidence_payloads.dart';

enum RouteStopRecommendationAction {
  routeImprovement,
  stopImprovement,
  additionalStopCoverage,
  maintainCurrentConfiguration,
  insufficientEvidence,
}

enum RouteStopEvidenceSufficiency { sufficient, limited, insufficient }

enum RouteStopRecommendationStatus {
  available,
  insufficientEvidence,
  temporarilyUnavailable,
  invalidAiResponse,
}

enum RouteStopRecommendationFailure {
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
  unknownStopReference,
}

enum RouteStopRecommendationSource { deterministicGate, gemini }

class RouteStopCandidateArea {
  const RouteStopCandidateArea({
    required this.fromStopId,
    required this.fromStopName,
    required this.toStopId,
    required this.toStopName,
    required this.areaDescription,
  });

  final String fromStopId;
  final String fromStopName;
  final String toStopId;
  final String toStopName;
  final String areaDescription;
}

class RouteStopRecommendation {
  const RouteStopRecommendation({
    required this.action,
    required this.summary,
    required this.rationale,
    required this.evidenceReferences,
    required this.limitations,
    required this.evidenceSufficiency,
    required this.candidateArea,
    required this.source,
  });

  final RouteStopRecommendationAction action;
  final String summary;
  final List<String> rationale;
  final List<String> evidenceReferences;
  final List<String> limitations;
  final RouteStopEvidenceSufficiency evidenceSufficiency;
  final RouteStopCandidateArea? candidateArea;
  final RouteStopRecommendationSource source;
}

class RouteStopRecommendationResult {
  const RouteStopRecommendationResult({
    required this.status,
    required this.recommendation,
    required this.failure,
    required this.evidence,
    required this.payload,
    this.httpStatusCode,
  });

  final RouteStopRecommendationStatus status;
  final RouteStopRecommendation? recommendation;
  final RouteStopRecommendationFailure? failure;
  final DistrictRouteStopEvidence? evidence;
  final RouteStopGeminiEvidencePayload? payload;
  final int? httpStatusCode;
}

class RouteStopRecommendationValidationException implements Exception {
  const RouteStopRecommendationValidationException({required this.failure});

  final RouteStopRecommendationFailure failure;
}
