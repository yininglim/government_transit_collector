import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/core/config/gemini_config.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_data_source.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

void main() {
  test('accepts a valid direct structured Bus Frequency object', () async {
    final result =
        await repository(
          gemini: FakeGeminiDataSource(
            response: validResponse('maintainService'),
          ),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(result.status, BusFrequencyRecommendationStatus.available);
    expect(
      result.recommendation?.action,
      BusFrequencyRecommendationAction.maintainService,
    );
    expect(result.failure, isNull);
  });

  for (final action in BusFrequencyRecommendationAction.values) {
    test('accepts valid ${action.name} response', () async {
      final gemini = FakeGeminiDataSource(response: validResponse(action.name));
      final result = await repository(gemini: gemini).generate(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      expect(result.recommendation?.action, action);
      expect(
        result.recommendation?.source,
        BusFrequencyRecommendationSource.gemini,
      );
      expect(
        result.status,
        action == BusFrequencyRecommendationAction.insufficientEvidence
            ? BusFrequencyRecommendationStatus.insufficientEvidence
            : BusFrequencyRecommendationStatus.available,
      );
      expect(result.failure, isNull);
      expect(result.evidence, isNotNull);
      expect(result.payload, isNotNull);
    });
  }

  test('deterministic gate avoids Gemini when departures are absent', () async {
    final gemini = FakeGeminiDataSource(
      response: validResponse('maintainService'),
    );
    final result =
        await repository(
          gemini: gemini,
          sourceEvidence: evidence(departureCount: 0),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(gemini.callCount, 0);
    expect(
      result.status,
      BusFrequencyRecommendationStatus.insufficientEvidence,
    );
    expect(
      result.recommendation?.action,
      BusFrequencyRecommendationAction.insufficientEvidence,
    );
    expect(
      result.recommendation?.source,
      BusFrequencyRecommendationSource.deterministicGate,
    );
  });

  test('zero feedback does not block generation when headway exists', () async {
    final gemini = FakeGeminiDataSource(
      response: validResponse('maintainService'),
    );

    await repository(gemini: gemini).generate(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );

    expect(gemini.callCount, 1);
  });

  test('one departure without supporting evidence is gated locally', () async {
    final gemini = FakeGeminiDataSource(
      response: validResponse('maintainService'),
    );

    final result =
        await repository(
          gemini: gemini,
          sourceEvidence: evidence(departureCount: 1),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(gemini.callCount, 0);
    expect(
      result.status,
      BusFrequencyRecommendationStatus.insufficientEvidence,
    );
  });

  test('rejects an unknown evidence reference', () async {
    final response = validResponse('increaseService');
    response['evidenceReferences'] = ['unknown.metric'];
    final result =
        await repository(
          gemini: FakeGeminiDataSource(response: response),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(result.status, BusFrequencyRecommendationStatus.invalidAiResponse);
    expect(
      result.failure,
      BusFrequencyRecommendationFailure.unknownEvidenceReference,
    );
    expect(result.recommendation, isNull);
  });

  test('rejects duplicated evidence references', () async {
    final response = validResponse('maintainService');
    response['evidenceReferences'] = ['scheduled.summary', 'scheduled.summary'];
    final result =
        await repository(
          gemini: FakeGeminiDataSource(response: response),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(result.failure, BusFrequencyRecommendationFailure.invalidResponse);
  });

  for (final invalid in [
    ('action', 'addBuses'),
    ('evidenceSufficiency', 'confident'),
  ]) {
    test('rejects invalid ${invalid.$1}', () async {
      final response = validResponse('maintainService');
      response[invalid.$1] = invalid.$2;
      final result =
          await repository(
            gemini: FakeGeminiDataSource(response: response),
          ).generate(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );

      expect(result.status, BusFrequencyRecommendationStatus.invalidAiResponse);
      expect(result.failure, BusFrequencyRecommendationFailure.invalidResponse);
    });
  }

  test('rejects a missing required field', () async {
    final response = validResponse('maintainService')..remove('summary');
    final result =
        await repository(
          gemini: FakeGeminiDataSource(response: response),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(result.failure, BusFrequencyRecommendationFailure.invalidResponse);
  });

  test('rejects prohibited numeric recommendation properties', () async {
    final response = validResponse('maintainService')
      ..['recommendedHeadway'] = 600;
    final result =
        await repository(
          gemini: FakeGeminiDataSource(response: response),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(result.failure, BusFrequencyRecommendationFailure.invalidResponse);
  });

  test('rejects contradictory action and sufficiency', () async {
    final response = validResponse('increaseService')
      ..['evidenceSufficiency'] = 'insufficient';
    final result =
        await repository(
          gemini: FakeGeminiDataSource(response: response),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(result.failure, BusFrequencyRecommendationFailure.invalidResponse);
  });

  test('rejects excessive rationale and limitation lists', () async {
    for (final field in ['rationale', 'limitations']) {
      final response = validResponse('maintainService');
      response[field] = List.filled(5, 'Bounded item');
      final result =
          await repository(
            gemini: FakeGeminiDataSource(response: response),
          ).generate(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );

      expect(result.failure, BusFrequencyRecommendationFailure.invalidResponse);
    }
  });

  test(
    'maps malformed structured transport output to invalid response',
    () async {
      final result =
          await repository(
            gemini: FakeGeminiDataSource(
              failure: GeminiTransportFailure.invalidStructuredJson,
            ),
          ).generate(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );

      expect(result.status, BusFrequencyRecommendationStatus.invalidAiResponse);
      expect(
        result.failure,
        BusFrequencyRecommendationFailure.malformedResponse,
      );
    },
  );

  for (final mapping in [
    (GeminiTransportFailure.timeout, BusFrequencyRecommendationFailure.timeout),
    (
      GeminiTransportFailure.rateLimited,
      BusFrequencyRecommendationFailure.rateLimited,
    ),
    (
      GeminiTransportFailure.notConfigured,
      BusFrequencyRecommendationFailure.geminiNotConfigured,
    ),
    (
      GeminiTransportFailure.authentication,
      BusFrequencyRecommendationFailure.authentication,
    ),
    (GeminiTransportFailure.network, BusFrequencyRecommendationFailure.network),
    (GeminiTransportFailure.http, BusFrequencyRecommendationFailure.http),
  ]) {
    test('maps ${mapping.$1.name} to typed unavailable state', () async {
      final result =
          await repository(
            gemini: FakeGeminiDataSource(failure: mapping.$1),
          ).generate(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );

      expect(
        result.status,
        BusFrequencyRecommendationStatus.temporarilyUnavailable,
      );
      expect(result.failure, mapping.$2);
      expect(result.evidence, isNotNull);
      expect(result.payload, isNotNull);
    });
  }

  test('preserves safe HTTP status only for HTTP failures', () async {
    final httpResult =
        await repository(
          gemini: FakeGeminiDataSource(
            failure: GeminiTransportFailure.http,
            statusCode: 503,
          ),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );
    final networkResult =
        await repository(
          gemini: FakeGeminiDataSource(
            failure: GeminiTransportFailure.network,
            statusCode: 503,
          ),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(httpResult.failure, BusFrequencyRecommendationFailure.http);
    expect(httpResult.httpStatusCode, 503);
    expect(networkResult.failure, BusFrequencyRecommendationFailure.network);
    expect(networkResult.httpStatusCode, isNull);
  });

  test('does not retain upstream credential or raw-body text', () async {
    const sensitiveText = 'credential-and-raw-body-sentinel';
    final result =
        await repository(
          gemini: FakeGeminiDataSource(
            failure: GeminiTransportFailure.http,
            statusCode: 400,
            failureMessage: sensitiveText,
          ),
        ).generate(
          routeId: 'J15',
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );

    expect(result.httpStatusCode, 400);
    expect(result.toString(), isNot(contains(sensitiveText)));
  });

  test('uses the bounded Part 6B payload and fixed constraints', () async {
    final gemini = FakeGeminiDataSource(
      response: validResponse('maintainService'),
    );
    await repository(gemini: gemini).generate(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );
    final request = gemini.request!;
    final input = jsonDecode(request.input) as Map<String, dynamic>;

    expect(input['payload_type'], 'bus_frequency_evidence');
    expect(input['route'], containsPair('route_id', 'J15'));
    expect(input['feedback'], containsPair('comments_included', false));
    expect(input.containsKey('records'), isFalse);
    expect(
      request.instructions,
      contains('Operational activity is not passenger demand'),
    );
    expect(request.instructions, contains('numeric recommended frequency'));
    expect(request.responseSchema, busFrequencyRecommendationResponseSchema);
    expect(
      _allKeys(request.responseSchema),
      isNot(contains('recommendedHeadway')),
    );
    expect(
      _allKeys(request.responseSchema),
      isNot(contains('recommendedFrequency')),
    );
  });

  test('uses retained evidence without loading it again', () async {
    final retainedEvidence = evidence();
    final evidenceRepository = FakeEvidenceRepository(retainedEvidence);
    final gemini = FakeGeminiDataSource(
      response: validResponse('maintainService'),
    );
    final recommendationRepository =
        DefaultBusFrequencyRecommendationRepository(
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
    expect(jsonDecode(gemini.request!.input), result.payload!.toJson());
  });

  test('uses 90 seconds while Part 6A retains its 30-second default', () {
    final recommendationRepository =
        DefaultBusFrequencyRecommendationRepository(
          evidenceRepository: FakeEvidenceRepository(evidence()),
          geminiDataSource: FakeGeminiDataSource(
            response: validResponse('maintainService'),
          ),
        );
    final defaultTransport = GeminiInteractionsDataSource(
      config: const GeminiConfig(apiKey: ''),
    );

    expect(
      recommendationRepository.requestTimeout,
      const Duration(seconds: 90),
    );
    expect(defaultTransport.requestTimeout, const Duration(seconds: 30));
  });

  test('response model has no numeric recommendation properties', () {
    final recommendation = parseBusFrequencyRecommendation(
      validResponse('maintainService'),
      allowedEvidenceReferences: const ['scheduled.summary'],
    );

    expect(
      recommendation.action,
      BusFrequencyRecommendationAction.maintainService,
    );
    expect(
      _allKeys(busFrequencyRecommendationResponseSchema),
      isNot(contains('headway')),
    );
    expect(
      _allKeys(busFrequencyRecommendationResponseSchema),
      isNot(contains('frequency')),
    );
  });
}

final periodStart = DateTime.utc(2026, 8, 20);
final periodEnd = DateTime.utc(2026, 8, 27);

const route = RoutePerformanceRoute(
  routeId: 'J15',
  shortName: 'J15',
  longName: 'Johor Bahru route',
);

DefaultBusFrequencyRecommendationRepository repository({
  FakeGeminiDataSource? gemini,
  BusFrequencyEvidence? sourceEvidence,
}) => DefaultBusFrequencyRecommendationRepository(
  evidenceRepository: FakeEvidenceRepository(sourceEvidence ?? evidence()),
  geminiDataSource:
      gemini ??
      FakeGeminiDataSource(response: validResponse('maintainService')),
);

BusFrequencyEvidence evidence({int departureCount = 2}) {
  final departures = List.generate(
    departureCount,
    (index) => ScheduledDepartureEvidence(
      tripId: 'trip-$index',
      serviceDate: periodStart,
      departureSeconds: 21600 + index * 600,
      scheduledAt: periodStart.add(Duration(minutes: index * 10)),
      referenceStopId: 'stop-a',
      referenceStopSequence: 1,
    ),
  );
  return BusFrequencyEvidence(
    routeId: 'J15',
    periodStart: periodStart,
    periodEnd: periodEnd,
    scheduledService: ScheduledServiceEvidence(
      route: route,
      periodStart: periodStart,
      periodEnd: periodEnd,
      directionGroups: [
        ScheduledDirectionEvidence(
          directionId: 0,
          departures: departures,
          headwaysSeconds: departureCount > 1 ? const [600] : const [],
          hourlyBuckets: const [],
          averageHeadwaySeconds: departureCount > 1 ? 600 : null,
          medianHeadwaySeconds: departureCount > 1 ? 600 : null,
          minimumHeadwaySeconds: departureCount > 1 ? 600 : null,
          maximumHeadwaySeconds: departureCount > 1 ? 600 : null,
        ),
      ],
      incompleteTripIds: const [],
      status: departureCount == 0
          ? ScheduledServiceEvidenceStatus.noDepartures
          : departureCount == 1
          ? ScheduledServiceEvidenceStatus.insufficientForHeadway
          : ScheduledServiceEvidenceStatus.available,
      hasCompleteDirectionData: true,
    ),
    operational: AiOperationalEvidence(
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
    ),
    feedback: const BusFrequencyFeedbackEvidence(
      records: [],
      countByIssueType: {},
      frequencyRelevantRecords: [],
    ),
  );
}

Map<String, dynamic> validResponse(String action) => {
  'action': action,
  'summary': 'Use the available evidence for the service action.',
  'rationale': ['Scheduled evidence supports this action.'],
  'evidenceReferences': ['scheduled.summary'],
  'limitations': ['Operational coverage is limited.'],
  'evidenceSufficiency': action == 'insufficientEvidence'
      ? 'insufficient'
      : 'limited',
};

class FakeEvidenceRepository implements BusFrequencyEvidenceRepository {
  FakeEvidenceRepository(this.result);

  final BusFrequencyEvidence result;
  int callCount = 0;

  @override
  Future<BusFrequencyEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    callCount++;
    return result;
  }
}

class FakeGeminiDataSource implements GeminiDataSource {
  FakeGeminiDataSource({
    this.response,
    this.failure,
    this.statusCode,
    this.failureMessage = 'sanitised',
  });

  final Map<String, dynamic>? response;
  final GeminiTransportFailure? failure;
  final int? statusCode;
  final String failureMessage;
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
        message: failureMessage,
        statusCode: statusCode,
      );
    }
    return GeminiStructuredInteractionResult(
      interactionId: 'test',
      value: response!,
    );
  }
}

Set<String> _allKeys(Object? value) {
  final result = <String>{};
  if (value is Map<String, dynamic>) {
    for (final entry in value.entries) {
      result.add(entry.key);
      result.addAll(_allKeys(entry.value));
    }
  } else if (value is List<dynamic>) {
    for (final item in value) {
      result.addAll(_allKeys(item));
    }
  }
  return result;
}
