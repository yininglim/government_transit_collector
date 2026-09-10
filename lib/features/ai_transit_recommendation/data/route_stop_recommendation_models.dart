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

enum RouteStopValidationDiagnostic {
  malformedStructuredResponse,
  missingRequiredField,
  unknownProperty,
  invalidField,
  invalidAction,
  duplicateAction,
  duplicateRoute,
  unknownRoute,
  missingRoute,
  duplicateEvidenceReference,
  unknownEvidenceReference,
  crossRouteEvidenceReference,
  missingEvidenceReference,
  invalidCandidatePair,
  reversedCandidatePair,
  nonAdjacentCandidatePair,
  emptyActionList,
  incompatibleActionCombination,
  candidateAreaRequired,
  candidateAreaProhibited,
  targetStopsRequired,
  targetStopsProhibited,
  duplicateTargetStop,
  unknownTargetStop,
  crossRouteTargetStop,
  unavailableTargetStop,
}

enum RouteStopInvalidField {
  overallSummary,
  routeRecommendations,
  routeId,
  conciseRationale,
  routeOwnedEvidenceRefs,
  targetStopIds,
  candidateAreaFromStopId,
  candidateAreaToStopId,
  limitations,
  insufficientEvidenceLimitations,
}

enum RouteStopRecommendationSource { deterministicGate, gemini }

class RouteStopCandidateArea {
  const RouteStopCandidateArea({
    required this.routeId,
    required this.fromStopId,
    required this.fromStopName,
    required this.toStopId,
    required this.toStopName,
    required this.areaDescription,
  });

  final String routeId;
  final String fromStopId;
  final String fromStopName;
  final String toStopId;
  final String toStopName;
  final String areaDescription;
}

class RouteStopRecommendationGroup {
  const RouteStopRecommendationGroup({
    required this.action,
    required this.summary,
    required this.rationale,
    required this.evidenceReferences,
    required this.limitations,
    required this.routeIds,
    required this.candidateAreas,
  });

  final RouteStopRecommendationAction action;
  final String summary;
  final List<String> rationale;
  final List<String> evidenceReferences;
  final List<String> limitations;
  final List<String> routeIds;
  final List<RouteStopCandidateArea> candidateAreas;
}

class RouteStopRecommendationRecord {
  const RouteStopRecommendationRecord({
    required this.routeId,
    required this.actions,
    required this.conciseRationale,
    required this.routeOwnedEvidenceRefs,
    required this.candidateArea,
    required this.limitations,
    this.targetStopIds = const [],
  });

  final String routeId;
  final List<RouteStopRecommendationAction> actions;
  final String conciseRationale;
  final List<String> routeOwnedEvidenceRefs;
  final List<String> targetStopIds;
  final RouteStopCandidateArea? candidateArea;
  final List<String> limitations;
}

class RouteStopRecommendationSynthesis {
  const RouteStopRecommendationSynthesis({
    required this.overallSummary,
    required this.recommendationGroups,
    required this.needsMoreEvidence,
    this.routeRecommendations = const [],
  });

  final String overallSummary;
  final List<RouteStopRecommendationGroup> recommendationGroups;
  final RouteStopRecommendationGroup? needsMoreEvidence;
  final List<RouteStopRecommendationRecord> routeRecommendations;
}

class RouteStopRecommendationResult {
  const RouteStopRecommendationResult({
    required this.status,
    required this.synthesis,
    required this.failure,
    required this.evidence,
    required this.payload,
  });

  final RouteStopRecommendationStatus status;
  final RouteStopRecommendationSynthesis? synthesis;
  final RouteStopRecommendationFailure? failure;
  final List<DistrictRouteStopEvidence> evidence;
  final RouteStopGeminiEvidencePayload? payload;
}

class RouteStopRecommendationValidationException implements Exception {
  const RouteStopRecommendationValidationException({
    required this.failure,
    this.diagnostic = RouteStopValidationDiagnostic.invalidField,
    this.invalidField,
  });

  final RouteStopRecommendationFailure failure;
  final RouteStopValidationDiagnostic diagnostic;
  final RouteStopInvalidField? invalidField;
}
