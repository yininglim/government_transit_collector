import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_data_source.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_evidence_payloads.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

void main() {
  test('multiple eligible routes use one compact feature request', () async {
    final gemini = FakeGemini(
      validResponse({'R1': 'maintainService', 'R2': 'maintainService'}),
    );
    final evidence = [routeEvidence('R1'), routeEvidence('R2')];
    final result = await repository(
      gemini,
    ).generate(evidence: evidence, startUtc: start, endExclusiveUtc: end);
    expect(gemini.calls, 1);
    expect(result.status, BusFrequencyRecommendationStatus.available);
    expect(
      result.synthesis!.overallSummary,
      'Overall evidence-grounded summary.',
    );
    expect(result.synthesis!.recommendationGroups.single.routeIds, [
      'R1',
      'R2',
    ]);
    final payload = jsonDecode(gemini.request!.input) as Map<String, dynamic>;
    expect(payload['payload_type'], 'bus_frequency_feature_evidence');
    expect(payload['eligible_route_ids'], ['R1', 'R2']);
    expect((payload['routes'] as List), hasLength(2));
    expect(payload.containsKey('records'), isFalse);
  });

  test('21 eligible routes fit one recommendation group and request', () async {
    final ids = List.generate(21, (index) => 'R$index');
    final gemini = FakeGemini(
      validResponse({for (final id in ids) id: 'maintainService'}),
    );
    final result = await repository(gemini).generate(
      evidence: [for (final id in ids) routeEvidence(id)],
      startUtc: start,
      endExclusiveUtc: end,
    );
    expect(gemini.calls, 1);
    expect(result.failure, isNull);
    expect(result.synthesis!.recommendationGroups.single.routeIds, ids);
  });

  test('empty evidence causes zero requests', () async {
    final gemini = FakeGemini(validResponse({'R1': 'maintainService'}));
    final empty = await repository(
      gemini,
    ).generate(evidence: const [], startUtc: start, endExclusiveUtc: end);
    expect(gemini.calls, 0);
    expect(
      empty.failure,
      BusFrequencyRecommendationFailure.evidenceUnavailable,
    );
  });

  test('22 and larger eligible route sets remain supported', () async {
    for (final count in [22, 35]) {
      final ids = List.generate(count, (index) => 'R$index');
      final gemini = FakeGemini(
        validResponse({for (final id in ids) id: 'maintainService'}),
      );
      final result = await repository(gemini).generate(
        evidence: [for (final id in ids) routeEvidence(id)],
        startUtc: start,
        endExclusiveUtc: end,
      );
      expect(gemini.calls, 1);
      expect(result.failure, isNull);
      expect(result.synthesis!.recommendationGroups.single.routeIds, ids);
    }
  });

  test(
    'payload route references are namespaced and comments remain absent',
    () async {
      final gemini = FakeGemini(validResponse({'R1': 'maintainService'}));
      await repository(gemini).generate(
        evidence: [routeEvidence('R1')],
        startUtc: start,
        endExclusiveUtc: end,
      );
      final payload = jsonDecode(gemini.request!.input) as Map<String, dynamic>;
      final route = (payload['routes'] as List).single as Map<String, dynamic>;
      expect(
        route['evidence_references'],
        contains('route.R1.scheduled.summary'),
      );
      expect(route['feedback'], containsPair('comments_included', false));
    },
  );

  test(
    'increase peak-hour frequency accepts submitted hourly evidence',
    () async {
      final gemini = FakeGemini(
        validResponse({'R1': 'increasePeakHourFrequency'}),
      );
      final result = await repository(gemini).generate(
        evidence: [routeEvidence('R1', hourly: true)],
        startUtc: start,
        endExclusiveUtc: end,
      );
      expect(result.status, BusFrequencyRecommendationStatus.available);
      expect(
        result.synthesis!.recommendationGroups.single.action,
        BusFrequencyRecommendationAction.increasePeakHourFrequency,
      );
    },
  );

  test(
    'increase peak-hour frequency rejects routes without peak evidence',
    () async {
      final gemini = FakeGemini(
        validResponse({'R1': 'increasePeakHourFrequency'}),
      );
      final result = await repository(gemini).generate(
        evidence: [routeEvidence('R1')],
        startUtc: start,
        endExclusiveUtc: end,
      );
      expect(result.status, BusFrequencyRecommendationStatus.invalidAiResponse);
      expect(result.failure, BusFrequencyRecommendationFailure.invalidResponse);
    },
  );

  test('post-Gemini insufficient routes remain separate', () async {
    final response = validResponse({
      'R1': 'maintainService',
      'R2': 'insufficientEvidence',
    });
    final result = await repository(FakeGemini(response)).generate(
      evidence: [routeEvidence('R1'), routeEvidence('R2')],
      startUtc: start,
      endExclusiveUtc: end,
    );
    expect(result.synthesis!.recommendationGroups.single.routeIds, ['R1']);
    expect(result.synthesis!.needsMoreEvidence!.routeIds, ['R2']);
  });

  for (final mutation in [
    'fabricated',
    'duplicate-route',
    'unknown-reference',
    'duplicate-reference',
    'cross-route-reference',
    'missing-route',
    'extra-property',
  ]) {
    test('rejects $mutation grouped response', () async {
      final response = validResponse({
        'R1': 'maintainService',
        'R2': 'decreaseService',
      });
      final records = response['routeRecommendations'] as List<dynamic>;
      switch (mutation) {
        case 'fabricated':
          (records[0] as Map<String, dynamic>)['routeId'] = 'UNKNOWN';
        case 'duplicate-route':
          records.add(Map<String, dynamic>.from(records[0] as Map));
        case 'unknown-reference':
          (records[0] as Map<String, dynamic>)['evidenceRefs'] = [
            'unknown',
          ];
        case 'duplicate-reference':
          (records[0] as Map<String, dynamic>)['evidenceRefs'] = [
            'route.R1.scheduled.summary',
            'route.R1.scheduled.summary',
          ];
        case 'cross-route-reference':
          (records[0] as Map<String, dynamic>)['evidenceRefs'] = [
            'route.R2.scheduled.summary',
          ];
        case 'missing-route':
          records.removeLast();
        case 'extra-property':
          response['invented'] = true;
      }
      final result = await repository(FakeGemini(response)).generate(
        evidence: [routeEvidence('R1'), routeEvidence('R2')],
        startUtc: start,
        endExclusiveUtc: end,
      );
      expect(result.status, BusFrequencyRecommendationStatus.invalidAiResponse);
      expect(
        result.failure,
        mutation == 'fabricated'
            ? BusFrequencyRecommendationFailure.unknownRoute
            : isNotNull,
      );
    });
  }

  test('rejects empty route IDs', () async {
    final response = validResponse({'R1': 'maintainService'});
    ((response['routeRecommendations'] as List).single
        as Map<String, dynamic>)['routeId'] = '';
    final result = await repository(FakeGemini(response)).generate(
      evidence: [routeEvidence('R1')],
      startUtc: start,
      endExclusiveUtc: end,
    );
    expect(result.failure, BusFrequencyRecommendationFailure.invalidResponse);
  });

  test('retained evidence period mismatch does not call Gemini', () async {
    final gemini = FakeGemini(validResponse({'R1': 'maintainService'}));
    final result = await repository(gemini).generate(
      evidence: [routeEvidence('R1')],
      startUtc: start.add(const Duration(days: 1)),
      endExclusiveUtc: end,
    );
    expect(gemini.calls, 0);
    expect(
      result.failure,
      BusFrequencyRecommendationFailure.evidenceUnavailable,
    );
  });

  test('transport failures preserve safe mapping and payload', () async {
    final gemini = FakeGemini(null, failure: GeminiTransportFailure.timeout);
    final result = await repository(gemini).generate(
      evidence: [routeEvidence('R1')],
      startUtc: start,
      endExclusiveUtc: end,
    );
    expect(result.failure, BusFrequencyRecommendationFailure.timeout);
    expect(result.payload, isNotNull);
  });

  test(
    'schema is strict, grouped, bounded, and excludes numeric recommendations',
    () {
      expect(
        busFrequencyRecommendationResponseSchema['additionalProperties'],
        false,
      );
      expect(
        _keys(busFrequencyRecommendationResponseSchema),
        containsAll(['overallSummary', 'routeRecommendations']),
      );
      expect(
        _keys(busFrequencyRecommendationResponseSchema),
        isNot(contains('recommendedHeadway')),
      );
      final groupProperties =
          (busFrequencyRecommendationResponseSchema['properties']
                  as Map<String, dynamic>)['routeRecommendations']
              as Map<String, dynamic>;
      final itemProperties =
          (groupProperties['items'] as Map<String, dynamic>)['properties']
              as Map<String, dynamic>;
      expect(itemProperties, contains('routeId'));
      expect(itemProperties, contains('evidenceRefs'));
    },
  );

  test('Phase 3 request constraints remain fixed', () async {
    final gemini = FakeGemini(validResponse({'R1': 'maintainService'}));
    final repo = repository(gemini);
    await repo.generate(
      evidence: [routeEvidence('R1')],
      startUtc: start,
      endExclusiveUtc: end,
    );
    expect(repo.requestTimeout, const Duration(seconds: 90));
    expect(
      gemini.request!.responseSchema,
      busFrequencyRecommendationResponseSchema,
    );
    expect(gemini.request!.instructions, contains('one feature-level result'));
  });
}

final start = DateTime.utc(2026, 8, 1);
final end = DateTime.utc(2026, 8, 31);

DefaultBusFrequencyRecommendationRepository repository(FakeGemini gemini) =>
    DefaultBusFrequencyRecommendationRepository(geminiDataSource: gemini);

Map<String, dynamic> validResponse(Map<String, String> routes) {
  return {
    'overallSummary': 'Overall evidence-grounded summary.',
    'routeRecommendations': [
      for (final entry in routes.entries)
        {
          'action': entry.value,
          'routeId': entry.key,
          'conciseRationale': 'Submitted scheduled evidence supports the action.',
          'evidenceRefs': ['route.${entry.key}.scheduled.summary'],
          'limitations': ['Operational coverage is limited.'],
        },
    ],
  };
}

BusFrequencyEvidence routeEvidence(String id, {bool hourly = false}) {
  final route = RoutePerformanceRoute(
    routeId: id,
    shortName: id,
    longName: null,
  );
  final departures = [
    ScheduledDepartureEvidence(
      tripId: '$id-1',
      serviceDate: start,
      departureSeconds: 21600,
      scheduledAt: start,
      referenceStopId: 'S',
      referenceStopSequence: 1,
    ),
    ScheduledDepartureEvidence(
      tripId: '$id-2',
      serviceDate: start,
      departureSeconds: 22200,
      scheduledAt: start.add(const Duration(minutes: 10)),
      referenceStopId: 'S',
      referenceStopSequence: 1,
    ),
  ];
  return BusFrequencyEvidence(
    routeId: id,
    periodStart: start,
    periodEnd: end,
    scheduledService: ScheduledServiceEvidence(
      route: route,
      periodStart: start,
      periodEnd: end,
      directionGroups: [
        ScheduledDirectionEvidence(
          directionId: 0,
          departures: departures,
          headwaysSeconds: const [600],
          hourlyBuckets: hourly
              ? [
                  ScheduledServiceHourBucket(
                    serviceDate: start,
                    startMinute: 360,
                    scheduledDepartureCount: 2,
                    scheduledTripsPerHour: 2,
                  ),
                ]
              : const [],
          averageHeadwaySeconds: 600,
          medianHeadwaySeconds: 600,
          minimumHeadwaySeconds: 600,
          maximumHeadwaySeconds: 600,
        ),
      ],
      incompleteTripIds: const [],
      status: ScheduledServiceEvidenceStatus.available,
      hasCompleteDirectionData: true,
    ),
    operational: AiOperationalEvidence(
      route: route,
      periodStart: start,
      periodEnd: end,
      peakOperationSummary: PeakOperationSummary(
        routeId: id,
        periodStart: start,
        periodEnd: end,
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

class FakeGemini implements GeminiDataSource {
  FakeGemini(this.response, {this.failure});
  final Map<String, dynamic>? response;
  final GeminiTransportFailure? failure;
  int calls = 0;
  GeminiStructuredInteractionRequest? request;
  @override
  Future<GeminiStructuredInteractionResult> createStructuredInteraction(
    GeminiStructuredInteractionRequest request,
  ) async {
    calls++;
    this.request = request;
    if (failure != null)
      throw GeminiTransportException(failure: failure!, message: 'safe');
    return GeminiStructuredInteractionResult(
      interactionId: 'test',
      value: response!,
    );
  }
}

Set<String> _keys(Object? value) {
  final result = <String>{};
  if (value is Map<String, dynamic>) {
    for (final entry in value.entries) {
      result.add(entry.key);
      result.addAll(_keys(entry.value));
    }
  } else if (value is List<dynamic>) {
    for (final item in value) result.addAll(_keys(item));
  }
  return result;
}
