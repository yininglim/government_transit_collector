import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_data_source.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/johor_bahru_boundary_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

void main() {
  for (final action in RouteStopRecommendationAction.values) {
    test('accepts valid ${action.name} response', () async {
      final response = validResponse(action);
      final result = await repository(response: response).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      expect(result.recommendation?.action, action);
      expect(
        result.status,
        action == RouteStopRecommendationAction.insufficientEvidence
            ? RouteStopRecommendationStatus.insufficientEvidence
            : RouteStopRecommendationStatus.available,
      );
      expect(result.failure, isNull);
    });
  }

  test('accepts candidate area between submitted consecutive stops', () async {
    final result =
        await repository(
          response: validResponse(
            RouteStopRecommendationAction.additionalStopCoverage,
          ),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(result.recommendation?.candidateArea?.fromStopId, 'stop-a');
    expect(result.recommendation?.candidateArea?.toStopId, 'stop-b');
  });

  for (final mutation in <void Function(Map<String, dynamic>)>[
    (response) =>
        (response['candidateArea'] as Map<String, dynamic>)['toStopId'] =
            'invented-stop',
    (response) =>
        (response['candidateArea'] as Map<String, dynamic>)['toStopName'] =
            'Invented name',
  ]) {
    test('rejects fabricated candidate stop references', () async {
      final response = validResponse(
        RouteStopRecommendationAction.additionalStopCoverage,
      );
      mutation(response);

      final result = await repository(response: response).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      expect(
        result.failure,
        RouteStopRecommendationFailure.unknownStopReference,
      );
    });
  }

  test('rejects coordinate properties in candidate area', () async {
    final response = validResponse(
      RouteStopRecommendationAction.additionalStopCoverage,
    );
    (response['candidateArea'] as Map<String, dynamic>)['latitude'] = 1.5;

    final result = await repository(response: response).generate(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );

    expect(result.failure, RouteStopRecommendationFailure.invalidResponse);
    expect(
      _allKeys(routeStopRecommendationResponseSchema),
      isNot(anyOf(contains('latitude'), contains('longitude'))),
    );
  });

  test('rejects unknown and duplicate evidence references', () async {
    for (final references in [
      ['invented.reference'],
      ['network.trip.0', 'network.trip.0'],
    ]) {
      final response = validResponse(
        RouteStopRecommendationAction.routeImprovement,
      )..['evidenceReferences'] = references;
      final result = await repository(response: response).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      expect(
        result.failure,
        references.first == 'invented.reference'
            ? RouteStopRecommendationFailure.unknownEvidenceReference
            : RouteStopRecommendationFailure.invalidResponse,
      );
    }
  });

  test('rejects missing fields and unknown properties', () async {
    final missing = validResponse(
      RouteStopRecommendationAction.routeImprovement,
    )..remove('summary');
    final unknown = validResponse(
      RouteStopRecommendationAction.routeImprovement,
    )..['constructionFeasibility'] = true;
    for (final response in [missing, unknown]) {
      final result = await repository(response: response).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );
      expect(result.failure, RouteStopRecommendationFailure.invalidResponse);
    }
  });

  test('rejects invalid action and contradictory sufficiency', () async {
    final invalidAction = validResponse(
      RouteStopRecommendationAction.routeImprovement,
    )..['action'] = 'buildRouteExtension';
    final contradictory = validResponse(
      RouteStopRecommendationAction.routeImprovement,
    )..['evidenceSufficiency'] = 'insufficient';
    for (final response in [invalidAction, contradictory]) {
      final result = await repository(response: response).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );
      expect(result.failure, RouteStopRecommendationFailure.invalidResponse);
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
        );

    expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
    expect(result.failure, RouteStopRecommendationFailure.malformedResponse);
  });

  test(
    'deterministic gate prevents Gemini for unusable network evidence',
    () async {
      final gemini = FakeGeminiDataSource(
        response: validResponse(RouteStopRecommendationAction.routeImprovement),
      );
      final result =
          await repository(
            gemini: gemini,
            sourceEvidence: evidence(stopCount: 1),
          ).generate(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );

      expect(gemini.callCount, 0);
      expect(result.status, RouteStopRecommendationStatus.insufficientEvidence);
      expect(
        result.recommendation?.source,
        RouteStopRecommendationSource.deterministicGate,
      );
    },
  );

  test('zero feedback does not prevent analysis with usable stops', () async {
    final gemini = FakeGeminiDataSource(
      response: validResponse(RouteStopRecommendationAction.stopImprovement),
    );
    await repository(gemini: gemini).generate(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );

    expect(gemini.callCount, 1);
  });

  for (final mapping in [
    (GeminiTransportFailure.timeout, RouteStopRecommendationFailure.timeout),
    (
      GeminiTransportFailure.rateLimited,
      RouteStopRecommendationFailure.rateLimited,
    ),
    (
      GeminiTransportFailure.authentication,
      RouteStopRecommendationFailure.authentication,
    ),
    (GeminiTransportFailure.network, RouteStopRecommendationFailure.network),
    (GeminiTransportFailure.http, RouteStopRecommendationFailure.http),
    (
      GeminiTransportFailure.notConfigured,
      RouteStopRecommendationFailure.geminiNotConfigured,
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
      );

      expect(result.failure, mapping.$2);
      expect(gemini.callCount, 1);
      expect(
        result.httpStatusCode,
        mapping.$1 == GeminiTransportFailure.http ? 503 : isNull,
      );
    });
  }

  test(
    'request uses bounded Part 6B payload and safety instructions',
    () async {
      final gemini = FakeGeminiDataSource(
        response: validResponse(RouteStopRecommendationAction.routeImprovement),
      );
      await repository(gemini: gemini).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      expect(gemini.request?.input, contains('route_stop_evidence'));
      expect(
        gemini.request?.instructions,
        contains('Do not fabricate stop coordinates'),
      );
      expect(
        gemini.request?.instructions,
        contains('Operational activity is not passenger demand'),
      );
      expect(
        _allKeys(gemini.request!.responseSchema),
        isNot(contains('capacity')),
      );
    },
  );

  test('uses retained evidence without loading it again', () async {
    final retainedEvidence = evidence();
    final evidenceRepository = FakeEvidenceRepository(retainedEvidence);
    final gemini = FakeGeminiDataSource(
      response: validResponse(RouteStopRecommendationAction.routeImprovement),
    );
    final recommendationRepository = DefaultRouteStopRecommendationRepository(
      evidenceRepository: evidenceRepository,
      geminiDataSource: gemini,
    );

    final result = await recommendationRepository.generate(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
      evidence: retainedEvidence,
    );

    expect(evidenceRepository.callCount, 0);
    expect(result.evidence, same(retainedEvidence));
    expect(gemini.request!.input, contains('route_stop_evidence'));
    expect(
      result.payload!.toJson()['evidence_references'],
      contains('network.trip.0'),
    );
  });
}

final periodStart = DateTime.utc(2026, 7, 1);
final periodEnd = DateTime.utc(2026, 8, 1);

DefaultRouteStopRecommendationRepository repository({
  Map<String, dynamic>? response,
  GeminiTransportFailure? failure,
  FakeGeminiDataSource? gemini,
  DistrictRouteStopEvidence? sourceEvidence,
}) => DefaultRouteStopRecommendationRepository(
  evidenceRepository: FakeEvidenceRepository(sourceEvidence ?? evidence()),
  geminiDataSource:
      gemini ??
      FakeGeminiDataSource(
        response:
            response ??
            validResponse(RouteStopRecommendationAction.routeImprovement),
        failure: failure,
      ),
);

Map<String, dynamic> validResponse(RouteStopRecommendationAction action) => {
  'action': action.name,
  'summary': 'Review the existing route and stop evidence.',
  'rationale': ['Existing route evidence supports this result.'],
  'evidenceReferences':
      action == RouteStopRecommendationAction.additionalStopCoverage
      ? ['network.trip.0', 'stop.stop-a', 'stop.stop-b']
      : ['network.trip.0'],
  'limitations': action == RouteStopRecommendationAction.insufficientEvidence
      ? ['Additional route evidence is required.']
      : ['Operational coverage is limited.'],
  'evidenceSufficiency':
      action == RouteStopRecommendationAction.insufficientEvidence
      ? 'insufficient'
      : 'limited',
  'candidateArea':
      action == RouteStopRecommendationAction.additionalStopCoverage
      ? <String, dynamic>{
          'fromStopId': 'stop-a',
          'fromStopName': 'Stop A',
          'toStopId': 'stop-b',
          'toStopName': 'Stop B',
          'areaDescription':
              'Evaluate additional stop coverage between Stop A and Stop B.',
        }
      : null,
};

DistrictRouteStopEvidence evidence({int stopCount = 2}) {
  const route = RoutePerformanceRoute(
    routeId: 'J15',
    shortName: 'J15',
    longName: 'Johor Bahru route',
  );
  final stops = [
    const AiRouteStopEvidence(
      stopId: 'stop-a',
      stopName: 'Stop A',
      stopSequence: 1,
      coordinate: MapCoordinate(1.49, 103.74),
      scheduledArrivalSeconds: 21600,
      scheduledDepartureSeconds: 21630,
    ),
    if (stopCount > 1)
      const AiRouteStopEvidence(
        stopId: 'stop-b',
        stopName: 'Stop B',
        stopSequence: 2,
        coordinate: MapCoordinate(1.50, 103.75),
        scheduledArrivalSeconds: 22200,
        scheduledDepartureSeconds: 22230,
      ),
  ];
  final network = AiRouteNetworkEvidence(
    route: route,
    trips: [
      AiRouteTripEvidence(
        tripId: 'trip-1',
        shapeId: 'shape-1',
        stops: stops,
        shapePoints: const [],
        routeDistanceMeters: 1200,
      ),
    ],
  );
  final operational = AiOperationalEvidence(
    route: route,
    periodStart: periodStart,
    periodEnd: periodEnd,
    peakOperationSummary: PeakOperationSummary(
      routeId: 'J15',
      periodStart: periodStart,
      periodEnd: periodEnd,
      observationCount: 0,
      distinctTripOccurrences: 0,
      observedDayCount: 0,
      routesRepresented: 0,
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
  );
  final routeStop = RouteStopEvidence(
    routeId: 'J15',
    periodStart: periodStart,
    periodEnd: periodEnd,
    network: network,
    operational: operational,
    feedback: const RouteStopFeedbackEvidence(
      records: [],
      countByIssueType: {},
      routeStopRelevantRecords: [],
    ),
    stopSpacingByTrip: [
      TripStopSpacingEvidence(
        tripId: 'trip-1',
        consecutiveStops: stopCount > 1
            ? const [
                ConsecutiveStopSpacingEvidence(
                  fromStopId: 'stop-a',
                  fromStopSequence: 1,
                  toStopId: 'stop-b',
                  toStopSequence: 2,
                  distanceMeters: 1200,
                ),
              ]
            : const [],
      ),
    ],
  );
  return DistrictRouteStopEvidence(
    routeStopEvidence: routeStop,
    boundary: const DistrictBoundaryEvidence(
      status: DistrictBoundaryStatus.unavailable,
      geometry: null,
      source: johorBahruDistrictBoundarySource,
    ),
    tripStopMembership: [
      TripDistrictStopEvidence(
        tripId: 'trip-1',
        stops: stops
            .map(
              (stop) => DistrictStopEvidence(
                stopId: stop.stopId,
                stopSequence: stop.stopSequence,
                membership: DistrictStopMembership.unverifiable,
              ),
            )
            .toList(),
      ),
    ],
    stopOccurrenceCounts: DistrictMembershipCounts(
      insideJohorBahruDistrict: 0,
      outsideJohorBahruDistrict: 0,
      unverifiable: stops.length,
    ),
    uniqueStopCounts: DistrictMembershipCounts(
      insideJohorBahruDistrict: 0,
      outsideJohorBahruDistrict: 0,
      unverifiable: stops.length,
    ),
  );
}

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

class FakeEvidenceRepository implements DistrictRouteStopEvidenceRepository {
  FakeEvidenceRepository(this.result);
  final DistrictRouteStopEvidence result;
  int callCount = 0;

  @override
  Future<DistrictRouteStopEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
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
