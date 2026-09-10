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

class BusFrequencyRouteRecommendationRecord {
  const BusFrequencyRouteRecommendationRecord({
    required this.routeId,
    required this.action,
    required this.conciseRationale,
    required this.evidenceRefs,
    required this.limitations,
    required this.source,
  });

  final String routeId;
  final BusFrequencyRecommendationAction action;
  final String conciseRationale;
  final List<String> evidenceRefs;
  final List<String> limitations;
  final BusFrequencyRecommendationSource source;
}

class BusFrequencyRecommendationGroup {
  const BusFrequencyRecommendationGroup({
    required this.action,
    this.routeRecommendations = const [],
    required this.source,
  });

  final BusFrequencyRecommendationAction action;
  final List<BusFrequencyRouteRecommendationRecord> routeRecommendations;
  final BusFrequencyRecommendationSource source;

  List<String> get routeIds =>
      routeRecommendations.map((record) => record.routeId).toList(growable: false);
  String get summary {
    final count = routeIds.length;
    final routes = count == 1 ? 'route' : 'routes';
    final verb = count == 1 ? 'is' : 'are';
    final wording = switch (action) {
      BusFrequencyRecommendationAction.increasePeakHourFrequency =>
        'recommended for increased peak-hour frequency',
      BusFrequencyRecommendationAction.maintainService =>
        'recommended to maintain the current frequency',
      BusFrequencyRecommendationAction.decreaseService =>
        'recommended for reduced frequency',
      BusFrequencyRecommendationAction.insufficientEvidence =>
        'need more evidence',
    };
    return '$count $routes $verb $wording.';
  }
  List<String> get rationale => routeRecommendations
      .map((record) => record.conciseRationale)
      .toList(growable: false);
  List<String> get evidenceReferences => routeRecommendations
      .expand((record) => record.evidenceRefs)
      .toList(growable: false);
  List<String> get limitations => routeRecommendations
      .expand((record) => record.limitations)
      .toList(growable: false);
}

class BusFrequencyRecommendationSynthesis {
  const BusFrequencyRecommendationSynthesis({
    required this.overallSummary,
    required this.routeRecommendations,
    required this.recommendationGroups,
    required this.needsMoreEvidence,
  });

  final String overallSummary;
  final List<BusFrequencyRouteRecommendationRecord> routeRecommendations;
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
