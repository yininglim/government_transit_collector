import 'dart:convert';

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
  test(
    'one request includes all eligible routes and compact allow-lists',
    () async {
      final gemini = FakeGeminiDataSource(response: response(['R1', 'R2']));
      final result = await repository(gemini).generate(
        evidence: [
          evidence(routeId: 'R1'),
          evidence(routeId: 'R2'),
        ],
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );
      expect(gemini.callCount, 1);
      expect(result.synthesis?.recommendationGroups.single.routeIds, [
        'R1',
        'R2',
      ]);
      final payload = jsonDecode(gemini.request!.input) as Map<String, dynamic>;
      expect(payload['eligible_route_ids'], ['R1', 'R2']);
      expect((payload['routes'] as List), hasLength(2));
    },
  );

  test('zero routes make zero requests', () async {
    final gemini = FakeGeminiDataSource(response: response(['R1']));
    final repo = repository(gemini);
    expect(
      (await repo.generate(
        evidence: const [],
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      )).status,
      RouteStopRecommendationStatus.insufficientEvidence,
    );
    expect(gemini.callCount, 0);
  });

  test('21 eligible routes use one complete compact request', () async {
    final routeIds = List.generate(21, (index) => 'R${index + 1}');
    final gemini = FakeGeminiDataSource(response: response(routeIds));
    final result = await repository(gemini).generate(
      evidence: [for (final routeId in routeIds) evidence(routeId: routeId)],
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );
    expect(gemini.callCount, 1);
    expect(result.status, RouteStopRecommendationStatus.available);
    expect(result.synthesis?.recommendationGroups.single.routeIds, routeIds);
    final payload = jsonDecode(gemini.request!.input) as Map<String, dynamic>;
    expect(payload['eligible_route_ids'], routeIds);
    expect(
      (payload['routes'] as List<dynamic>)
          .map(
            (route) =>
                ((route as Map<String, dynamic>)['route']
                    as Map<String, dynamic>)['route_id'],
          )
          .toList(),
      routeIds,
    );
  });

  test('21-route response must reconcile route 21 exactly', () async {
    final routeIds = List.generate(21, (index) => 'R${index + 1}');
    final retained = [
      for (final routeId in routeIds) evidence(routeId: routeId),
    ];
    final omitted =
        await repository(
          FakeGeminiDataSource(response: response(routeIds.take(20).toList())),
        ).generate(
          evidence: retained,
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );
    final fabricatedIds = [...routeIds.take(20), 'R22'];
    final fabricated =
        await repository(
          FakeGeminiDataSource(response: response(fabricatedIds)),
        ).generate(
          evidence: retained,
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );
    expect(omitted.failure, RouteStopRecommendationFailure.invalidResponse);
    expect(fabricated.status, RouteStopRecommendationStatus.invalidAiResponse);
    expect(fabricated.synthesis, isNull);
  });

  test(
    'rejects duplicate actions, routes, omitted and fabricated routes',
    () async {
      for (final groups in [
        [
          group(['R1']),
          group(['R2']),
        ],
        [
          group(['R1', 'R1']),
        ],
        [
          group(['R1']),
        ],
        [
          group(['R1', 'X']),
        ],
      ]) {
        final result =
            await repository(
              FakeGeminiDataSource(
                response: {
                  'overallSummary': 'Summary',
                  'recommendationGroups': groups,
                },
              ),
            ).generate(
              evidence: [
                evidence(routeId: 'R1'),
                evidence(routeId: 'R2'),
              ],
              startUtc: periodStart,
              endExclusiveUtc: periodEnd,
            );
        expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
      }
    },
  );

  test('separates needs more evidence and supports maintain', () async {
    final result =
        await repository(
          FakeGeminiDataSource(
            response: {
              'overallSummary': 'Summary',
              'recommendationGroups': [
                group(['R1'], action: 'maintainCurrentConfiguration'),
                group(
                  ['R2'],
                  action: 'insufficientEvidence',
                  limitations: ['More evidence required.'],
                ),
              ],
            },
          ),
        ).generate(
          evidence: [
            evidence(routeId: 'R1'),
            evidence(routeId: 'R2'),
          ],
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );
    expect(
      result.synthesis?.recommendationGroups.single.action,
      RouteStopRecommendationAction.maintainCurrentConfiguration,
    );
    expect(result.synthesis?.needsMoreEvidence?.routeIds, ['R2']);
  });

  test(
    'validates route-scoped references and directed candidate pairs',
    () async {
      final valid =
          await repository(
            FakeGeminiDataSource(
              response: {
                'overallSummary': 'Summary',
                'recommendationGroups': [
                  group(
                    ['R1'],
                    action: 'additionalStopCoverage',
                    areas: [area('R1')],
                  ),
                ],
              },
            ),
          ).generate(
            evidence: [evidence(routeId: 'R1')],
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );
      expect(valid.status, RouteStopRecommendationStatus.available);
      for (final changed in [
        area('R1')..['toStopId'] = 'unknown',
        area('R1')..addAll({'latitude': 1.5}),
        area('R1')
          ..['fromStopId'] = 'stop-b'
          ..['fromStopName'] = 'Stop B'
          ..['toStopId'] = 'stop-a'
          ..['toStopName'] = 'Stop A',
      ]) {
        final result =
            await repository(
              FakeGeminiDataSource(
                response: {
                  'overallSummary': 'Summary',
                  'recommendationGroups': [
                    group(
                      ['R1'],
                      action: 'additionalStopCoverage',
                      areas: [changed],
                    ),
                  ],
                },
              ),
            ).generate(
              evidence: [evidence(routeId: 'R1')],
              startUtc: periodStart,
              endExclusiveUtc: periodEnd,
            );
        expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
      }
      final cross = group(['R1']);
      cross['evidenceReferences'] = ['route.R2.network.trip.0'];
      final rejected =
          await repository(
            FakeGeminiDataSource(
              response: {
                'overallSummary': 'Summary',
                'recommendationGroups': [
                  cross,
                  group(['R2'], action: 'stopImprovement'),
                ],
              },
            ),
          ).generate(
            evidence: [
              evidence(routeId: 'R1'),
              evidence(routeId: 'R2'),
            ],
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );
      expect(
        rejected.failure,
        RouteStopRecommendationFailure.unknownEvidenceReference,
      );
    },
  );

  test('feature failure is atomic', () async {
    final result =
        await repository(
          FakeGeminiDataSource(
            response: {
              'overallSummary': 'Summary',
              'recommendationGroups': [
                group(['R1']),
                group(
                  ['R2'],
                  action: 'additionalStopCoverage',
                  areas: [area('R2')..['toStopId'] = 'bad'],
                ),
              ],
            },
          ),
        ).generate(
          evidence: [
            evidence(routeId: 'R1'),
            evidence(routeId: 'R2'),
          ],
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );
    expect(result.synthesis, isNull);
    expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
  });

  for (final action in RouteStopRecommendationAction.values) {
    test('accepts valid grouped ${action.name} response', () async {
      final areas =
          action == RouteStopRecommendationAction.additionalStopCoverage
          ? [area('R1')]
          : const <Map<String, dynamic>>[];
      final limitations =
          action == RouteStopRecommendationAction.insufficientEvidence
          ? ['More evidence is required.']
          : const ['Known limitation.'];
      final result =
          await repository(
            FakeGeminiDataSource(
              response: {
                'overallSummary': 'Overall summary',
                'recommendationGroups': [
                  group(
                    ['R1'],
                    action: action.name,
                    areas: areas,
                    limitations: limitations,
                  ),
                ],
              },
            ),
          ).generate(
            evidence: [evidence(routeId: 'R1')],
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );
      expect(result.failure, isNull);
      if (action == RouteStopRecommendationAction.insufficientEvidence) {
        expect(result.synthesis?.needsMoreEvidence?.routeIds, ['R1']);
      } else {
        expect(result.synthesis?.recommendationGroups.single.action, action);
      }
    });
  }

  test('rejects duplicate evidence references', () async {
    final invalid = group(['R1']);
    invalid['evidenceReferences'] = [
      'route.R1.network.trip.0',
      'route.R1.network.trip.0',
    ];
    final result = await generateResponse({
      'overallSummary': 'Summary',
      'recommendationGroups': [invalid],
    });
    expect(result.failure, RouteStopRecommendationFailure.invalidResponse);
  });

  test('rejects missing and unknown top-level properties', () async {
    for (final invalid in [
      {
        'recommendationGroups': [
          group(['R1']),
        ],
      },
      {
        'overallSummary': 'Summary',
        'recommendationGroups': [
          group(['R1']),
        ],
        'unexpected': true,
      },
    ]) {
      expect(
        (await generateResponse(invalid)).failure,
        RouteStopRecommendationFailure.invalidResponse,
      );
    }
  });

  test('rejects missing and unknown group properties', () async {
    final missing = group(['R1'])..remove('summary');
    final unknown = group(['R1'])..['geometry'] = 'invented';
    for (final invalid in [missing, unknown]) {
      expect(
        (await generateResponse({
          'overallSummary': 'Summary',
          'recommendationGroups': [invalid],
        })).failure,
        RouteStopRecommendationFailure.invalidResponse,
      );
    }
  });

  test('rejects an invalid grouped action', () async {
    final invalid = group(['R1'])..['action'] = 'extendRoute';
    expect(
      (await generateResponse({
        'overallSummary': 'Summary',
        'recommendationGroups': [invalid],
      })).failure,
      RouteStopRecommendationFailure.invalidResponse,
    );
  });

  test('maps malformed structured output safely', () async {
    final result =
        await repository(
          FakeGeminiDataSource(
            failure: GeminiTransportFailure.invalidStructuredJson,
          ),
        ).generate(
          evidence: [evidence(routeId: 'R1')],
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );
    expect(result.status, RouteStopRecommendationStatus.invalidAiResponse);
    expect(result.failure, RouteStopRecommendationFailure.malformedResponse);
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
    test('maps ${mapping.$1.name} feature failure without retry', () async {
      final gemini = FakeGeminiDataSource(
        failure: mapping.$1,
        statusCode: mapping.$1 == GeminiTransportFailure.http ? 503 : null,
      );
      final result = await repository(gemini).generate(
        evidence: [evidence(routeId: 'R1')],
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );
      expect(result.failure, mapping.$2);
      expect(
        result.httpStatusCode,
        mapping.$1 == GeminiTransportFailure.http ? 503 : isNull,
      );
      expect(gemini.callCount, 1);
    });
  }

  test('zero feedback remains eligible for feature synthesis', () async {
    final gemini = FakeGeminiDataSource(response: response(['R1']));
    final result = await repository(gemini).generate(
      evidence: [evidence(routeId: 'R1')],
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );
    expect(result.status, RouteStopRecommendationStatus.available);
    expect(gemini.callCount, 1);
  });

  test('rejects a non-consecutive known-stop pair', () async {
    final invalidArea = area('R1')
      ..['toStopId'] = 'stop-c'
      ..['toStopName'] = 'Stop C';
    final result =
        await repository(
          FakeGeminiDataSource(
            response: {
              'overallSummary': 'Summary',
              'recommendationGroups': [
                group(
                  ['R1'],
                  action: 'additionalStopCoverage',
                  areas: [invalidArea],
                ),
              ],
            },
          ),
        ).generate(
          evidence: [evidence(routeId: 'R1', stopCount: 3)],
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );
    expect(result.failure, RouteStopRecommendationFailure.unknownStopReference);
  });

  test('rejects a candidate pair spanning separate submitted patterns', () {
    final payload = featurePayloadWithPatterns([
      ['stop-a', 'stop-b'],
      ['stop-c', 'stop-d'],
    ]);
    final invalidArea = area('R1')
      ..['toStopId'] = 'stop-d'
      ..['toStopName'] = 'Stop D';
    expect(
      () => parseRouteStopRecommendationSynthesis({
        'overallSummary': 'Summary',
        'recommendationGroups': [
          group(['R1'], action: 'additionalStopCoverage', areas: [invalidArea]),
        ],
      }, payload: payload),
      throwsA(
        isA<RouteStopRecommendationValidationException>().having(
          (error) => error.failure,
          'failure',
          RouteStopRecommendationFailure.unknownStopReference,
        ),
      ),
    );
  });

  test('conflicting retained stop metadata fails before Gemini', () async {
    final gemini = FakeGeminiDataSource(response: response(['R1']));
    final result = await repository(gemini).generate(
      evidence: [evidence(routeId: 'R1', conflictingMembership: true)],
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );
    expect(result.failure, RouteStopRecommendationFailure.evidenceUnavailable);
    expect(gemini.callCount, 0);
  });

  test('uses supplied retained evidence without repository reload', () async {
    final evidenceRepository = CountingEvidenceRepository();
    final retained = evidence(routeId: 'R1');
    final gemini = FakeGeminiDataSource(response: response(['R1']));
    final result =
        await DefaultRouteStopRecommendationRepository(
          evidenceRepository: evidenceRepository,
          geminiDataSource: gemini,
        ).generate(
          evidence: [retained],
          startUtc: periodStart,
          endExclusiveUtc: periodEnd,
        );
    expect(evidenceRepository.calls, 0);
    expect(result.evidence.single, same(retained));
  });
}

Future<RouteStopRecommendationResult> generateResponse(
  Map<String, dynamic> value,
) => repository(FakeGeminiDataSource(response: value)).generate(
  evidence: [evidence(routeId: 'R1')],
  startUtc: periodStart,
  endExclusiveUtc: periodEnd,
);

Map<String, dynamic> featurePayloadWithPatterns(
  List<List<String>> patterns,
) => {
  'eligible_route_ids': ['R1'],
  'routes': [
    {
      'route': {'route_id': 'R1'},
      'evidence_references': ['route.R1.network.trip.0'],
      'network': {
        'stop_catalog': [
          for (final id in patterns.expand((items) => items).toSet())
            {
              'stop_id': id,
              'stop_name': 'Stop ${id.substring(id.length - 1).toUpperCase()}',
            },
        ],
        'trip_patterns': [
          for (final pattern in patterns)
            {
              'ordered_stops': [
                for (final id in pattern) {'stop_id': id},
              ],
            },
        ],
      },
    },
  ],
};

DefaultRouteStopRecommendationRepository repository(
  FakeGeminiDataSource gemini,
) => DefaultRouteStopRecommendationRepository(geminiDataSource: gemini);
Map<String, dynamic> response(List<String> routes) => {
  'overallSummary': 'Cross-route summary',
  'recommendationGroups': [group(routes)],
};
Map<String, dynamic> group(
  List<String> routes, {
  String action = 'routeImprovement',
  List<Map<String, dynamic>> areas = const [],
  List<String> limitations = const ['Limited operations.'],
}) => {
  'action': action,
  'summary': 'Group summary',
  'rationale': ['Evidence supports review.'],
  'routeIds': routes,
  'evidenceReferences': [
    for (final id in routes) 'route.${Uri.encodeComponent(id)}.network.trip.0',
  ],
  'limitations': limitations,
  'candidateAreas': areas,
};
Map<String, dynamic> area(String routeId) => {
  'routeId': routeId,
  'fromStopId': 'stop-a',
  'fromStopName': 'Stop A',
  'toStopId': 'stop-b',
  'toStopName': 'Stop B',
  'areaDescription': 'Evaluate the submitted gap.',
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
