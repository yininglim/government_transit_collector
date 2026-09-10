import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_data_source.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_evidence_payloads.dart';
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
  test('response schema keeps supported structure without string length keywords', () {
    final encoded = jsonEncode(routeStopRecommendationResponseSchemaFor(21));
    expect(encoded, isNot(contains('maxLength')));
    final root = routeStopRecommendationResponseSchemaFor(21)['properties']
        as Map<String, dynamic>;
    final recommendations = root['routeRecommendations'] as Map<String, dynamic>;
    expect(recommendations.containsKey('minItems'), isFalse);
    expect(recommendations.containsKey('maxItems'), isFalse);
    final record = recommendations['items'] as Map<String, dynamic>;
    final actions = (record['properties'] as Map<String, dynamic>)['actions']
        as Map<String, dynamic>;
    final targets = (record['properties'] as Map<String, dynamic>)['targetStopIds']
        as Map<String, dynamic>;
    expect(actions['minItems'], 1);
    expect(actions['maxItems'], 3);
    expect(targets.containsKey('minItems'), isFalse);
    expect(targets['maxItems'], 3);
    expect(record['required'], isNot(contains('targetStopIds')));
    for (final keyword in ['type', 'properties', 'required', 'additionalProperties', 'items', 'minItems', 'maxItems', 'enum']) {
      expect(encoded, contains(keyword));
    }
  });

  test('local reconciliation rejects 20 or 22 records for 21 eligible routes', () async {
    final ids = List.generate(21, (index) => 'R${index + 1}');
    final retained = [for (final id in ids) evidence(routeId: id)];
    final omitted = await repository(
      FakeGeminiDataSource(response: response(ids.take(20).toList())),
    ).generate(evidence: retained, startUtc: periodStart, endExclusiveUtc: periodEnd);
    final extra = await repository(
      FakeGeminiDataSource(response: response([...ids, 'R22'])),
    ).generate(evidence: retained, startUtc: periodStart, endExclusiveUtc: periodEnd);
    expect(omitted.status, RouteStopRecommendationStatus.invalidAiResponse);
    expect(omitted.failure, RouteStopRecommendationFailure.invalidResponse);
    expect(extra.status, RouteStopRecommendationStatus.invalidAiResponse);
    expect(extra.failure, RouteStopRecommendationFailure.invalidResponse);
  });

  test('application validation still rejects overlong summaries and rationales', () async {
    final longSummary = response(['R1'])..['overallSummary'] = 'x' * 481;
    final longRationale = response(['R1']);
    (longRationale['routeRecommendations'] as List<dynamic>).single['conciseRationale'] = 'x' * 241;
    for (final value in [longSummary, longRationale]) {
      final result = await generateResponse(value);
      expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
    }
  });

  test('one request includes all eligible routes and compact allow-lists', () async {
    final gemini = FakeGeminiDataSource(response: response(['R1', 'R2']));
    final result = await repository(gemini).generate(evidence: [evidence(routeId: 'R1'), evidence(routeId: 'R2')], startUtc: periodStart, endExclusiveUtc: periodEnd);
    expect(gemini.callCount, 1);
    expect(result.synthesis!.routeRecommendations.map((r) => r.routeId), ['R1', 'R2']);
    expect(result.synthesis!.recommendationGroups.single.routeIds, ['R1', 'R2']);
    final payload = jsonDecode(gemini.request!.input) as Map<String, dynamic>;
    expect(payload['eligible_route_ids'], ['R1', 'R2']);
  });

  test('zero routes make zero requests', () async {
    final gemini = FakeGeminiDataSource(response: response(['R1']));
    final result = await repository(gemini).generate(evidence: const [], startUtc: periodStart, endExclusiveUtc: periodEnd);
    expect(result.status, RouteStopRecommendationStatus.insufficientEvidence);
    expect(gemini.callCount, 0);
  });

  test('instructions define optimized input and route-record contract', () async {
    final gemini = FakeGeminiDataSource(response: response(['R1']));
    await repository(gemini).generate(evidence: [evidence(routeId: 'R1')], startUtc: periodStart, endExclusiveUtc: periodEnd);
    final instructions = gemini.request!.instructions;
    for (final text in ['shared_stop_catalog', 'served_stop_ids', 'targetStopIds', 'ordered_stop_field_order', 'positional ordered-stop row', 'one routeRecommendation record', 'multiple compatible improvement actions', "route's allow-list", 'consecutive in the directed order']) { expect(instructions, contains(text)); }
  });

  test('21 eligible routes use one request and reconcile all records', () async {
    final ids = List.generate(21, (i) => 'R${i + 1}');
    final gemini = FakeGeminiDataSource(response: response(ids));
    final result = await repository(gemini).generate(evidence: [for (final id in ids) evidence(routeId: id)], startUtc: periodStart, endExclusiveUtc: periodEnd);
    expect(gemini.callCount, 1);
    expect(result.synthesis!.routeRecommendations.map((r) => r.routeId), ids);
  });

  test('supports compatible multi-action route records', () async {
    final result = await generateResponse(response(['R1'], actions: ['routeImprovement', 'stopImprovement', 'additionalStopCoverage'], withArea: true));
    expect(result.failure, isNull);
    expect(result.synthesis!.recommendationGroups.map((g) => g.action), [RouteStopRecommendationAction.routeImprovement, RouteStopRecommendationAction.stopImprovement, RouteStopRecommendationAction.additionalStopCoverage]);
  });

  test('accepts one and three validated target stops', () async {
    final one = await generateResponse(
      response(['R1'], actions: const ['stopImprovement']),
    );
    final three = await repository(
      FakeGeminiDataSource(
        response: response(
          ['R1'],
          actions: const ['stopImprovement'],
          targetStopIds: const ['stop-a', 'stop-b', 'stop-c'],
        ),
      ),
    ).generate(
      evidence: [evidence(routeId: 'R1', stopCount: 3)],
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );
    expect(one.synthesis!.routeRecommendations.single.targetStopIds, ['stop-a']);
    expect(three.synthesis!.routeRecommendations.single.targetStopIds, [
      'stop-a',
      'stop-b',
      'stop-c',
    ]);
  });

  test('rejects invalid target stop cardinality and ownership', () async {
    final values = [
      response(
        ['R1'],
        actions: const ['stopImprovement'],
        includeTargetStopIds: false,
      ),
      response(
        ['R1'],
        actions: const ['stopImprovement'],
        targetStopIds: const [],
      ),
      response(
        ['R1'],
        actions: const ['stopImprovement'],
        targetStopIds: const ['stop-a', 'stop-b', 'stop-c', 'stop-d'],
      ),
      response(
        ['R1'],
        actions: const ['stopImprovement'],
        targetStopIds: const ['stop-a', 'stop-a'],
      ),
      response(
        ['R1'],
        actions: const ['stopImprovement'],
        targetStopIds: const ['unknown-stop'],
      ),
      response(
        ['R1'],
        actions: const ['stopImprovement'],
        targetStopIds: const [' stop-a'],
      ),
      response(['R1'], targetStopIds: const ['stop-a']),
    ];
    for (final value in values) {
      final result = await generateResponse(value);
      expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
    }
  });

  test('rejects cross-route-only target stops', () {
    final payload = _twoRouteTargetPayload();
    final value = response(
      ['R1', 'R2'],
      actions: const ['stopImprovement'],
    );
    final records = value['routeRecommendations'] as List<dynamic>;
    records[0]['targetStopIds'] = ['stop-b'];
    records[1]['targetStopIds'] = ['stop-b'];
    expect(
      () => parseRouteStopRecommendationSynthesis(value, payload: payload),
      throwsA(
        isA<RouteStopRecommendationValidationException>().having(
          (error) => error.diagnostic,
          'diagnostic',
          RouteStopValidationDiagnostic.crossRouteTargetStop,
        ),
      ),
    );
  });

  test('rejects target stops without deterministic name or coordinates', () {
    for (final invalid in <(String, Object?)>[
      ('stop_name', null),
      ('stop_name', ''),
      ('latitude', null),
      ('longitude', null),
      ('latitude', 91),
      ('longitude', 181),
      ('latitude', double.nan),
    ]) {
      final payload = const RouteStopGeminiPayloadBuilder()
          .buildFeature([evidence(routeId: 'R1')])
          .toJson();
      final catalog = payload['shared_stop_catalog'] as Map<String, dynamic>;
      (catalog['stop-a'] as Map<String, dynamic>)[invalid.$1] = invalid.$2;
      expect(
        () => parseRouteStopRecommendationSynthesis(
          response(['R1'], actions: const ['stopImprovement']),
          payload: payload,
        ),
        throwsA(isA<RouteStopRecommendationValidationException>()),
      );
    }
  });

  test('multi-action record preserves target stops and candidate area', () async {
    final result = await generateResponse(
      response(
        ['R1'],
        actions: const ['stopImprovement', 'additionalStopCoverage'],
        withArea: true,
      ),
    );
    final record = result.synthesis!.routeRecommendations.single;
    expect(record.targetStopIds, ['stop-a']);
    expect(record.candidateArea, isNotNull);
  });

  test('deterministically groups one route into compatible action groups', () {
    final record = RouteStopRecommendationRecord(
      routeId: 'R1',
      actions: const [
        RouteStopRecommendationAction.routeImprovement,
        RouteStopRecommendationAction.stopImprovement,
      ],
      conciseRationale: 'Review supported by evidence.',
      routeOwnedEvidenceRefs: const ['route.R1.network.trip.0'],
      candidateArea: null,
      limitations: const [],
    );
    final groups = groupRouteStopRecommendations([record]);
    expect(groups.map((group) => group.action), [
      RouteStopRecommendationAction.routeImprovement,
      RouteStopRecommendationAction.stopImprovement,
    ]);
    expect(groups.every((group) => group.routeIds.single == 'R1'), isTrue);
  });

  for (final action in [RouteStopRecommendationAction.maintainCurrentConfiguration, RouteStopRecommendationAction.insufficientEvidence]) {
    test('supports exclusive ${action.name}', () async {
      final result = await generateResponse(response(['R1'], actions: [action.name], limitations: action == RouteStopRecommendationAction.insufficientEvidence ? ['More evidence required.'] : const []));
      expect(result.failure, isNull);
      expect(result.synthesis!.routeRecommendations.single.actions.single.name, action.name);
    });
  }

  test('insufficient evidence requires at least one valid limitation', () async {
    final omitted = response(
      ['R1'],
      actions: const ['insufficientEvidence'],
    );
    (omitted['routeRecommendations'] as List<dynamic>).single.remove(
      'limitations',
    );
    final empty = response(
      ['R1'],
      actions: const ['insufficientEvidence'],
      limitations: const [],
    );
    final valid = response(
      ['R1'],
      actions: const ['insufficientEvidence'],
      limitations: const ['More evidence is required.'],
    );

    for (final invalid in [omitted, empty]) {
      final result = await generateResponse(invalid);
      expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
      expect(result.failure, RouteStopRecommendationFailure.invalidResponse);
    }
    expect((await generateResponse(valid)).failure, isNull);
  });

  test('invalid field values remain rejected', () async {
    final emptyReferences = response(['R1']);
    (emptyReferences['routeRecommendations'] as List<dynamic>)
        .single['routeOwnedEvidenceRefs'] = <String>[];
    final longRationale = response(['R1']);
    (longRationale['routeRecommendations'] as List<dynamic>)
        .single['conciseRationale'] = 'sensitive-value-' * 20;
    final longLimitation = response(['R1']);
    (longLimitation['routeRecommendations'] as List<dynamic>)
        .single['limitations'] = ['sensitive-value-' * 20];

    for (final value in [emptyReferences, longRationale, longLimitation]) {
      final result = await generateResponse(value);
      expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
      expect(result.failure, RouteStopRecommendationFailure.invalidResponse);
    }
  });

  test('rejects duplicate, omitted, unknown and empty route records', () async {
    for (final value in [response(['R1', 'R1']), response(['R1']), response(['R1', 'X']), response(['R1'], actions: const [])]) {
      final result = await repository(FakeGeminiDataSource(response: value)).generate(evidence: [evidence(routeId: 'R1'), evidence(routeId: 'R2')], startUtc: periodStart, endExclusiveUtc: periodEnd);
      expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
    }
  });

  test('rejects duplicate actions and incompatible exclusive actions', () async {
    for (final actions in [['routeImprovement', 'routeImprovement'], ['maintainCurrentConfiguration', 'routeImprovement'], ['insufficientEvidence', 'stopImprovement']]) {
      final result = await generateResponse(response(['R1'], actions: actions, withArea: actions.contains('additionalStopCoverage')));
      expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
    }
  });

  test('validates references and candidate pair', () async {
    final valid = await generateResponse(response(['R1'], actions: ['additionalStopCoverage'], withArea: true));
    expect(valid.failure, isNull);
    for (final invalid in [response(['R1'], actions: ['additionalStopCoverage'], withArea: true, fromStopId: 'stop-b', toStopId: 'stop-a'), response(['R1'], actions: ['additionalStopCoverage'], withArea: true, toStopId: 'unknown')]) {
      expect((await generateResponse(invalid)).status, RouteStopRecommendationStatus.invalidAiResponse);
    }
  });

  test('accepts namespaced trip reference and rejects its local form', () async {
    final valid = await generateResponse(response(['R1']));
    expect(valid.failure, isNull);

    final local = response(['R1']);
    (local['routeRecommendations'] as List<dynamic>).single['routeOwnedEvidenceRefs'] = [
      'network.trip.0',
    ];
    final invalid = await generateResponse(local);
    expect(invalid.status, RouteStopRecommendationStatus.invalidAiResponse);
    expect(
      invalid.failure,
      RouteStopRecommendationFailure.unknownEvidenceReference,
    );
  });

  test('rejects a trip reference owned by another route', () async {
    final value = response(['R1', 'R2']);
    (value['routeRecommendations'] as List<dynamic>).first['routeOwnedEvidenceRefs'] = [
      'route.R2.network.trip.0',
    ];
    final result = await repository(FakeGeminiDataSource(response: value)).generate(
      evidence: [evidence(routeId: 'R1'), evidence(routeId: 'R2')],
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );
    expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
    expect(
      result.failure,
      RouteStopRecommendationFailure.unknownEvidenceReference,
    );
  });

  test('rejects duplicate evidence references and unknown properties', () async {
    final duplicate = response(['R1']); (duplicate['routeRecommendations'] as List)[0]['routeOwnedEvidenceRefs'] = ['route.R1.network.trip.0', 'route.R1.network.trip.0'];
    final result = await generateResponse(duplicate);
    expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
    expect(result.failure, RouteStopRecommendationFailure.invalidResponse);
    final unknown = response(['R1'])..['unexpected'] = true;
    expect((await generateResponse(unknown)).failure, RouteStopRecommendationFailure.invalidResponse);
  });

  test('maps malformed and transport failures', () async {
    final malformed = await repository(FakeGeminiDataSource(failure: GeminiTransportFailure.invalidStructuredJson)).generate(evidence: [evidence(routeId: 'R1')], startUtc: periodStart, endExclusiveUtc: periodEnd);
    expect(malformed.status, RouteStopRecommendationStatus.invalidAiResponse);
    expect(malformed.failure, RouteStopRecommendationFailure.malformedResponse);
    for (final mapping in [(GeminiTransportFailure.timeout, RouteStopRecommendationFailure.timeout), (GeminiTransportFailure.rateLimited, RouteStopRecommendationFailure.rateLimited), (GeminiTransportFailure.authentication, RouteStopRecommendationFailure.authentication), (GeminiTransportFailure.network, RouteStopRecommendationFailure.network), (GeminiTransportFailure.http, RouteStopRecommendationFailure.http), (GeminiTransportFailure.notConfigured, RouteStopRecommendationFailure.geminiNotConfigured)]) {
      final result = await repository(FakeGeminiDataSource(failure: mapping.$1, statusCode: mapping.$1 == GeminiTransportFailure.http ? 503 : null)).generate(evidence: [evidence(routeId: 'R1')], startUtc: periodStart, endExclusiveUtc: periodEnd);
      expect(result.failure, mapping.$2);
    }
  });

  test('zero feedback remains eligible and retained evidence is not reloaded', () async {
    final source = CountingEvidenceRepository(); final retained = evidence(routeId: 'R1'); final gemini = FakeGeminiDataSource(response: response(['R1']));
    final result = await DefaultRouteStopRecommendationRepository(evidenceRepository: source, geminiDataSource: gemini).generate(evidence: [retained], startUtc: periodStart, endExclusiveUtc: periodEnd);
    expect(result.status, RouteStopRecommendationStatus.available); expect(source.calls, 0); expect(gemini.callCount, 1);
  });

  test('conflicting retained stop metadata fails before Gemini', () async {
    final gemini = FakeGeminiDataSource(response: response(['R1'])); final result = await repository(gemini).generate(evidence: [evidence(routeId: 'R1', conflictingMembership: true)], startUtc: periodStart, endExclusiveUtc: periodEnd);
    expect(result.failure, RouteStopRecommendationFailure.evidenceUnavailable); expect(gemini.callCount, 0);
  });

  test('candidate pair spanning separate patterns is rejected', () {
    final payload = featurePayloadWithPatterns([['stop-a', 'stop-b'], ['stop-c', 'stop-d']]);
    expect(() => parseRouteStopRecommendationSynthesis(response(['R1'], actions: ['additionalStopCoverage'], withArea: true, toStopId: 'stop-d'), payload: payload), throwsA(isA<RouteStopRecommendationValidationException>()));
  });
}

Future<RouteStopRecommendationResult> generateResponse(Map<String, dynamic> value) => repository(FakeGeminiDataSource(response: value)).generate(evidence: [evidence(routeId: 'R1')], startUtc: periodStart, endExclusiveUtc: periodEnd);

Map<String, dynamic> featurePayloadWithPatterns(
  List<List<String>> patterns,
) => {
  'eligible_route_ids': ['R1'],
  'ordered_stop_field_order':
      RouteStopGeminiPayloadBuilder.orderedStopFieldOrder,
  'shared_stop_catalog': {
    for (final id in patterns.expand((items) => items).toSet())
      id: {
        'stop_name': 'Stop ${id.substring(id.length - 1).toUpperCase()}',
        'latitude': null,
        'longitude': null,
        'district_membership': 'unverifiable',
      },
  },
  'routes': [
    {
      'route': {'route_id': 'R1'},
      'evidence_references': ['route.R1.network.trip.0'],
      'network': {
        'served_stop_ids': patterns.expand((items) => items).toSet().toList(),
        'trip_patterns': [
          for (final pattern in patterns)
            {
              'ordered_stops': [
                for (var index = 0; index < pattern.length; index++)
                  [pattern[index], index + 1, null, null, 1, null, null, 1],
              ],
            },
        ],
      },
    },
  ],
};

Map<String, dynamic> _twoRouteTargetPayload() => {
  'eligible_route_ids': ['R1', 'R2'],
  'shared_stop_catalog': {
    'stop-a': {
      'stop_name': 'Stop A',
      'latitude': 1.0,
      'longitude': 103.0,
    },
    'stop-b': {
      'stop_name': 'Stop B',
      'latitude': 1.1,
      'longitude': 103.1,
    },
  },
  'routes': [
    {
      'route': {'route_id': 'R1'},
      'evidence_references': ['route.R1.network.trip.0'],
      'network': {
        'served_stop_ids': ['stop-a'],
      },
    },
    {
      'route': {'route_id': 'R2'},
      'evidence_references': ['route.R2.network.trip.0'],
      'network': {
        'served_stop_ids': ['stop-b'],
      },
    },
  ],
};

DefaultRouteStopRecommendationRepository repository(
  FakeGeminiDataSource gemini,
) => DefaultRouteStopRecommendationRepository(geminiDataSource: gemini);
Map<String, dynamic> response(
  List<String> routes, {
  List<String>? actions,
  bool withArea = false,
  List<String> limitations = const ['Limited operations.'],
  String fromStopId = 'stop-a',
  String toStopId = 'stop-b',
  List<String>? targetStopIds,
  bool includeTargetStopIds = true,
}) => {
  'overallSummary': 'Cross-route summary',
  'routeRecommendations': [
    for (final id in routes)
      {
        'routeId': id,
        'actions': actions ?? const ['routeImprovement'],
        'conciseRationale': 'Evidence supports review.',
        'routeOwnedEvidenceRefs': [
          'route.${Uri.encodeComponent(id)}.network.trip.0',
        ],
        if (((actions ?? const ['routeImprovement']).contains(
                  'stopImprovement',
                ) &&
                includeTargetStopIds) ||
            targetStopIds != null)
          'targetStopIds': targetStopIds ?? const ['stop-a'],
        if (withArea)
          'candidateArea': {
            'fromStopId': fromStopId,
            'toStopId': toStopId,
          },
        if (limitations.isNotEmpty) 'limitations': limitations,
      },
  ],
};
final periodStart = DateTime.utc(2026, 7, 1);
final periodEnd = DateTime.utc(2026, 8, 1);
DistrictRouteStopEvidence evidence({
  String routeId = 'J15',
  int stopCount = 2,
  bool conflictingMembership = false,
}) {
  final route = RoutePerformanceRoute(
    routeId: routeId,
    shortName: routeId,
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
    if (stopCount > 2)
      const AiRouteStopEvidence(
        stopId: 'stop-c',
        stopName: 'Stop C',
        stopSequence: 3,
        coordinate: MapCoordinate(1.51, 103.76),
        scheduledArrivalSeconds: 22800,
        scheduledDepartureSeconds: 22830,
      ),
    if (conflictingMembership)
      const AiRouteStopEvidence(
        stopId: 'stop-a',
        stopName: 'Stop A',
        stopSequence: 3,
        coordinate: MapCoordinate(1.49, 103.74),
        scheduledArrivalSeconds: 22800,
        scheduledDepartureSeconds: 22830,
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
      routeId: routeId,
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
    routeId: routeId,
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
                membership: conflictingMembership && stop.stopSequence == 3
                    ? DistrictStopMembership.insideJohorBahruDistrict
                    : DistrictStopMembership.unverifiable,
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

class CountingEvidenceRepository
    implements DistrictRouteStopEvidenceRepository {
  int calls = 0;

  @override
  Future<DistrictRouteStopEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    calls++;
    return evidence(routeId: routeId);
  }
}