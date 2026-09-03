import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/admin_feedback_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_evidence_payloads.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/johor_bahru_boundary_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

void main() {
  group('bus frequency payload', () {
    test('retains factual summaries, coverage, counts, and stable refs', () {
      final payload = const BusFrequencyGeminiPayloadBuilder()
          .build(busFrequencyEvidence())
          .toJson();

      expect(payload['route'], containsPair('route_id', 'J15'));
      expect(payload['analysis_period'], {
        'start_utc': '2026-08-20T00:00:00.000Z',
        'end_exclusive_utc': '2026-08-27T00:00:00.000Z',
      });
      final scheduled = payload['scheduled_service'] as Map<String, dynamic>;
      final directions = scheduled['direction_groups'] as List<dynamic>;
      expect(directions.map((item) => item['direction_id']), [0, 1]);
      expect(directions.first['departure_count'], 2);
      expect(directions.first['median_headway_seconds'], 600.0);
      expect(scheduled['status'], 'incomplete');
      expect(scheduled['has_complete_direction_data'], isFalse);
      final operational = payload['operational'] as Map<String, dynamic>;
      expect(operational['peak_operation']['has_limited_coverage'], isTrue);
      expect(operational['route_performance']['delay_frequency_percent'], 50.0);
      final counts = _counts(payload['feedback'] as Map<String, dynamic>);
      expect(counts, {
        'Bus was late': 2,
        'Bus overcrowded': 1,
        'Bus did not arrive': 1,
      });
      expect(payload['evidence_references'], contains('scheduled.direction.0'));
      expect(payload['evidence_references'], contains('feedback.bus_was_late'));
      expect(
        payload['known_limitations'],
        contains('limited_peak_operation_coverage'),
      );
      _expectNoProhibitedKeys(payload);
    });

    test('serialization is deterministic and comments are excluded', () {
      final evidence = busFrequencyEvidence(longComment: 'x' * 50000);
      final first = const BusFrequencyGeminiPayloadBuilder()
          .build(evidence)
          .toJson();
      final second = const BusFrequencyGeminiPayloadBuilder()
          .build(evidence)
          .toJson();

      expect(jsonEncode(first), jsonEncode(second));
      expect(jsonEncode(first), isNot(contains('x' * 100)));
      expect(first['feedback'], containsPair('comments_included', false));
      expect(jsonDecode(jsonEncode(first)), isA<Map<String, dynamic>>());
      _expectNoConfigurationKeys(first);
    });
  });

  group('route and stop payload', () {
    test(
      'retains variants, stops, membership, spacing, and feedback counts',
      () {
        final payload = const RouteStopGeminiPayloadBuilder()
            .build(districtEvidence())
            .toJson();
        final boundary = payload['district_boundary'] as Map<String, dynamic>;
        final network = payload['network'] as Map<String, dynamic>;
        final patterns = network['trip_patterns'] as List<dynamic>;
        final catalog = network['stop_catalog'] as List<dynamic>;
        expect(boundary['status'], 'available');
        expect(boundary['polygon_included'], isFalse);
        expect(boundary['stop_occurrence_counts'], {
          'inside_johor_bahru_district': 2,
          'outside_johor_bahru_district': 1,
          'unverifiable': 1,
          'total': 4,
        });
        expect(patterns, hasLength(2));
        expect(
          patterns.expand((item) => item['trip_ids'] as List<dynamic>),
          containsAll(['trip-a', 'trip-b']),
        );
        expect(
          patterns.map((item) => item['shape_id']),
          containsAll(['shape-a', 'shape-b']),
        );
        expect(
          patterns.every((item) => item['shape_coordinates_included'] == false),
          isTrue,
        );
        expect(catalog, hasLength(3));
        final stopA = catalog.singleWhere(
          (item) => item['stop_id'] == 'stop-a',
        );
        expect(stopA['district_membership'], 'insideJohorBahruDistrict');
        final stopB = catalog.singleWhere(
          (item) => item['stop_id'] == 'stop-b',
        );
        expect(stopB['district_membership'], 'unverifiable');
        expect(stopB['latitude'], isNull);
        expect(stopB['longitude'], isNull);
        expect(_allKeys(payload), isNot(contains('coordinate_available')));
        final tripA = patterns.singleWhere(
          (item) => (item['trip_ids'] as List<dynamic>).contains('trip-a'),
        );
        final firstStops = tripA['ordered_stops'] as List<dynamic>;
        expect(firstStops.map((item) => item['stop_id']), ['stop-a', 'stop-b']);
        expect(
          tripA['consecutive_spacing_meters'],
          hasLength(firstStops.length - 1),
        );
        expect(
          (tripA['consecutive_spacing_meters'] as List<dynamic>).single,
          850.25,
        );
        final counts = _counts(payload['feedback'] as Map<String, dynamic>);
        expect(counts, {
          'Missing bus stop': 2,
          'Long walking distance': 1,
          'Incorrect route information': 1,
        });
        expect(payload['evidence_references'], contains('stop.stop-a'));
        expect(_allKeys(payload), isNot(contains('shape_points')));
        expect(_allKeys(payload), isNot(contains('polygons')));
        _expectNoProhibitedKeys(payload);
      },
    );

    test('trip and stop payloads are bounded with explicit omissions', () {
      final trips = List.generate(
        maxPayloadTripVariants + 3,
        (tripIndex) => routeTrip(
          'trip-$tripIndex',
          List.generate(
            maxPayloadStopsPerTrip + 2,
            (stopIndex) => routeStop('s-$tripIndex-$stopIndex', stopIndex),
          ),
        ),
      );
      final payload = const RouteStopGeminiPayloadBuilder()
          .build(districtEvidence(trips: trips, longComment: 'y' * 50000))
          .toJson();
      final network = payload['network'] as Map<String, dynamic>;
      final included = network['trip_patterns'] as List<dynamic>;

      expect(included, hasLength(maxPayloadTripVariants));
      expect(network['omitted_trip_variant_count'], 3);
      expect(
        included.first['ordered_stops'],
        hasLength(maxPayloadStopsPerTrip),
      );
      expect(included.first['omitted_stop_count'], 2);
      expect(jsonEncode(payload), isNot(contains('y' * 100)));
    });

    test('groups identical patterns and summarises schedules exactly', () {
      final trips = [
        routeTrip(
          'trip-1',
          [
            routeStop('a', 1, const MapCoordinate(1, 103), null, 100),
            routeStop('b', 2, const MapCoordinate(2, 104), null, null, 220),
          ],
          shapeId: 'shared-shape',
          distance: 900,
        ),
        routeTrip(
          'trip-2',
          [
            routeStop('a', 1, const MapCoordinate(1, 103), null, 300),
            routeStop('b', 2, const MapCoordinate(2, 104), null, null, 420),
          ],
          shapeId: 'shared-shape',
          distance: 900,
        ),
      ];
      final payload = const RouteStopGeminiPayloadBuilder()
          .build(districtEvidence(trips: trips, spacingByTrip: const []))
          .toJson();
      final network = payload['network'] as Map<String, dynamic>;
      final pattern = (network['trip_patterns'] as List<dynamic>).single;
      final stops = pattern['ordered_stops'] as List<dynamic>;

      expect(network['unique_trip_pattern_count'], 1);
      expect(network['stop_catalog'], hasLength(2));
      expect(pattern['trip_ids'], ['trip-1', 'trip-2']);
      expect(pattern['evidence_refs'], ['network.trip.0', 'network.trip.1']);
      expect(pattern['occurrence_count'], 2);
      expect(stops.first['arrival_seconds_min_max_missing'], [100, 300, 0]);
      expect(stops.last['departure_seconds_min_max_missing'], [220, 420, 0]);
      expect(stops.last['arrival_seconds_min_max_missing'], [null, null, 2]);
      expect(pattern['consecutive_spacing_meters'], [null]);
      expect(
        payload['evidence_references'],
        containsAll(['network.trip.0', 'network.trip.1', 'stop.a', 'stop.b']),
      );
    });

    test('keeps every materially different pattern distinct', () {
      final standardStops = [
        routeStop('a', 1, const MapCoordinate(1, 103)),
        routeStop('b', 2, const MapCoordinate(2, 104)),
      ];
      final trips = [
        routeTrip('base', standardStops, shapeId: 'shape', distance: 900),
        routeTrip(
          'ordered',
          [standardStops.first, routeStop('c', 2)],
          shapeId: 'shape',
          distance: 900,
        ),
        routeTrip(
          'reversed',
          [routeStop('b', 2, const MapCoordinate(2, 104)), standardStops.first],
          shapeId: 'shape',
          distance: 900,
        ),
        routeTrip(
          'sequence',
          [standardStops.first, routeStop('b', 3, const MapCoordinate(2, 104))],
          shapeId: 'shape',
          distance: 900,
        ),
        routeTrip('shape', standardStops, shapeId: 'other', distance: 900),
        routeTrip('distance', standardStops, shapeId: 'shape', distance: 901),
        routeTrip(
          'geometry',
          standardStops,
          shapeId: 'shape',
          distance: 900,
          shapeCoordinateCount: 2,
        ),
      ];
      final payload = const RouteStopGeminiPayloadBuilder()
          .build(districtEvidence(trips: trips, spacingByTrip: const []))
          .toJson();
      final network = payload['network'] as Map<String, dynamic>;

      expect(network['unique_trip_pattern_count'], trips.length);
    });

    test('keeps different spacing patterns distinct and deterministic', () {
      final stops = [routeStop('a', 1), routeStop('b', 2)];
      final trips = [
        routeTrip('trip-1', stops, shapeId: 'shape', distance: 900),
        routeTrip('trip-2', stops, shapeId: 'shape', distance: 900),
      ];
      final evidence = districtEvidence(
        trips: trips,
        spacingByTrip: const [
          TripStopSpacingEvidence(
            tripId: 'trip-1',
            consecutiveStops: [
              ConsecutiveStopSpacingEvidence(
                fromStopId: 'a',
                fromStopSequence: 1,
                toStopId: 'b',
                toStopSequence: 2,
                distanceMeters: 100,
              ),
            ],
          ),
          TripStopSpacingEvidence(
            tripId: 'trip-2',
            consecutiveStops: [
              ConsecutiveStopSpacingEvidence(
                fromStopId: 'a',
                fromStopSequence: 1,
                toStopId: 'b',
                toStopSequence: 2,
                distanceMeters: null,
              ),
            ],
          ),
        ],
      );
      final first = const RouteStopGeminiPayloadBuilder()
          .build(evidence)
          .toJson();
      final second = const RouteStopGeminiPayloadBuilder()
          .build(evidence)
          .toJson();
      final network = first['network'] as Map<String, dynamic>;

      expect(network['unique_trip_pattern_count'], 2);
      expect(
        (network['trip_patterns'] as List<dynamic>).map(
          (pattern) => pattern['consecutive_spacing_meters'],
        ),
        containsAll([
          [100.0],
          [null],
        ]),
      );
      expect(jsonEncode(first), jsonEncode(second));
    });

    test('catalog and pattern ordering is stable across trip input order', () {
      final firstTrip = routeTrip('first', [
        routeStop('z', 1),
        routeStop('b', 2),
      ], shapeId: 'shape-z');
      final secondTrip = routeTrip('second', [
        routeStop('a', 1),
        routeStop('c', 2),
      ], shapeId: 'shape-a');
      final first =
          const RouteStopGeminiPayloadBuilder()
                  .build(
                    districtEvidence(
                      trips: [firstTrip, secondTrip],
                      spacingByTrip: const [],
                    ),
                  )
                  .toJson()['network']
              as Map<String, dynamic>;
      final reversed =
          const RouteStopGeminiPayloadBuilder()
                  .build(
                    districtEvidence(
                      trips: [secondTrip, firstTrip],
                      spacingByTrip: const [],
                    ),
                  )
                  .toJson()['network']
              as Map<String, dynamic>;

      expect(
        (first['stop_catalog'] as List<dynamic>).map((stop) => stop['stop_id']),
        (reversed['stop_catalog'] as List<dynamic>).map(
          (stop) => stop['stop_id'],
        ),
      );
      expect(
        (first['trip_patterns'] as List<dynamic>).map(
          (pattern) => pattern['shape_id'],
        ),
        (reversed['trip_patterns'] as List<dynamic>).map(
          (pattern) => pattern['shape_id'],
        ),
      );
    });

    test('rejects conflicting metadata for the same stop ID', () {
      final trips = [
        routeTrip('one', [routeStop('a', 1, null, 'First'), routeStop('b', 2)]),
        routeTrip('two', [
          routeStop('a', 1, null, 'Second'),
          routeStop('c', 2),
        ]),
      ];

      expect(
        () => const RouteStopGeminiPayloadBuilder().build(
          districtEvidence(trips: trips),
        ),
        throwsA(isA<RouteStopGeminiPayloadBuildException>()),
      );
    });

    test('preserves repeated stop IDs in ordered loop topology', () {
      final payload = const RouteStopGeminiPayloadBuilder()
          .build(
            districtEvidence(
              trips: [
                routeTrip('loop', [
                  routeStop('a', 1),
                  routeStop('b', 2),
                  routeStop('a', 3),
                ]),
              ],
              spacingByTrip: const [],
            ),
          )
          .toJson();
      final network = payload['network'] as Map<String, dynamic>;
      final pattern = (network['trip_patterns'] as List<dynamic>).single;

      expect(network['stop_catalog'], hasLength(2));
      expect(
        (pattern['ordered_stops'] as List<dynamic>).map(
          (item) => item['stop_id'],
        ),
        ['a', 'b', 'a'],
      );
      expect(pattern['consecutive_spacing_meters'], [null, null]);
    });

    test('compacts repeated-pattern stress evidence', () {
      final trips = List.generate(
        maxPayloadTripVariants,
        (tripIndex) => routeTrip(
          'trip-$tripIndex',
          List.generate(
            50,
            (stopIndex) => routeStop(
              'shared-$stopIndex',
              stopIndex + 1,
              null,
              null,
              21600 + tripIndex * 1800 + stopIndex * 120,
              21630 + tripIndex * 1800 + stopIndex * 120,
            ),
          ),
          shapeId: 'shared-shape',
          distance: 25000,
          shapeCoordinateCount: 100,
        ),
      );
      final payload = const RouteStopGeminiPayloadBuilder()
          .build(districtEvidence(trips: trips, spacingByTrip: const []))
          .toJson();
      final network = payload['network'] as Map<String, dynamic>;
      final size = utf8.encode(jsonEncode(payload)).length;

      expect(network['trip_variant_count'], maxPayloadTripVariants);
      expect(network['unique_trip_pattern_count'], 1);
      expect(network['stop_catalog'], hasLength(50));
      expect(size, lessThan(30000));
    });
  });

  group('cost payload', () {
    test('retains exact Part 5B values and official provenance', () {
      final payload = const CostGeminiPayloadBuilder()
          .build(costEvidence())
          .toJson();
      final price = payload['diesel_price'] as Map<String, dynamic>;
      final estimate = payload['fuel_estimate'] as Map<String, dynamic>;
      final benchmark =
          payload['fuel_consumption_benchmark'] as Map<String, dynamic>;

      expect(payload['route'], containsPair('route_id', 'J15'));
      expect(payload['reference_date'], '2026-08-27');
      expect(price['rm_per_litre'], 2.5);
      expect(price['effective_date'], '2026-08-20');
      expect(price['source'], {
        'platform': 'data.gov.my',
        'publisher': 'Ministry of Finance Malaysia',
        'dataset_id': 'fuelprice',
        'dataset_name': 'Petrol & Diesel Prices',
      });
      expect(benchmark['low_litres_per_kilometre'], 0.2794);
      expect(benchmark['high_litres_per_kilometre'], 0.3695);
      expect(estimate['scheduled_vehicle_kilometres'], 100.0);
      expect(estimate['low_estimated_litres'], 27.94);
      expect(estimate['high_estimated_litres'], 36.95);
      expect(estimate['low_estimated_fuel_expenditure_rm'], 69.85);
      expect(estimate['high_estimated_fuel_expenditure_rm'], 92.375);
      expect(
        payload['unavailable_cost_categories'],
        contains('driver_staff_cost'),
      );
      expect(_allKeys(payload), isNot(contains('total_cost')));
      expect(_allKeys(payload), isNot(contains('total_implementation_cost')));
      expect(payload['evidence_references'], contains('cost.fuel_range'));
      _expectNoProhibitedKeys(payload);
      _expectNoConfigurationKeys(payload);
    });

    test('missing fuel and schedule evidence remains explicit', () {
      final payload = const CostGeminiPayloadBuilder()
          .build(
            costEvidence(
              availablePrice: false,
              departureCount: 0,
              status: FuelCostCalculationStatus.noScheduledDepartures,
            ),
          )
          .toJson();
      final price = payload['diesel_price'] as Map<String, dynamic>;
      final estimate = payload['fuel_estimate'] as Map<String, dynamic>;

      expect(price['status'], 'unavailable');
      expect(price['rm_per_litre'], isNull);
      expect(estimate['low_estimated_fuel_expenditure_rm'], isNull);
      expect(payload['calculation_status'], 'noScheduledDepartures');
      expect(
        payload['known_limitations'],
        contains('diesel_price_unavailable'),
      );
      expect(payload['known_limitations'], contains('no_scheduled_departures'));
    });
  });
}

final periodStart = DateTime.utc(2026, 8, 20);
final periodEnd = DateTime.utc(2026, 8, 27);
final referenceDate = DateTime(2026, 8, 27);

const route = RoutePerformanceRoute(
  routeId: 'J15',
  shortName: 'J15',
  longName: 'Johor Bahru route',
);

BusFrequencyEvidence busFrequencyEvidence({String longComment = 'late'}) {
  final records = [
    feedback('f1', 'Bus was late', longComment),
    feedback('f2', 'Bus was late', longComment),
    feedback('f3', 'Bus overcrowded', longComment),
    feedback('f4', 'Bus did not arrive', longComment),
    feedback('f5', 'Other', longComment),
  ];
  return BusFrequencyEvidence(
    routeId: 'J15',
    periodStart: periodStart,
    periodEnd: periodEnd,
    scheduledService: scheduledEvidence(),
    operational: operationalEvidence(),
    feedback: BusFrequencyFeedbackEvidence(
      records: records,
      countByIssueType: const {
        'Bus was late': 2,
        'Bus overcrowded': 1,
        'Bus did not arrive': 1,
        'Other': 1,
      },
      frequencyRelevantRecords: records.take(4).toList(growable: false),
    ),
  );
}

ScheduledServiceEvidence scheduledEvidence() => ScheduledServiceEvidence(
  route: route,
  periodStart: periodStart,
  periodEnd: periodEnd,
  directionGroups: [direction(0, 2, 600), direction(1, 1, null)],
  incompleteTripIds: const ['trip-missing'],
  status: ScheduledServiceEvidenceStatus.incomplete,
  hasCompleteDirectionData: false,
);

ScheduledDirectionEvidence direction(
  int? directionId,
  int departureCount,
  int? headway,
) => ScheduledDirectionEvidence(
  directionId: directionId,
  departures: List.generate(
    departureCount,
    (index) => ScheduledDepartureEvidence(
      tripId: 'trip-$directionId-$index',
      serviceDate: periodStart,
      departureSeconds: 21600 + index * 600,
      scheduledAt: periodStart.add(Duration(hours: 6, minutes: index * 10)),
      referenceStopId: 'stop-a',
      referenceStopSequence: 1,
    ),
  ),
  headwaysSeconds: headway == null ? const [] : [headway],
  hourlyBuckets: [
    ScheduledServiceHourBucket(
      serviceDate: periodStart,
      startMinute: 360,
      scheduledDepartureCount: departureCount,
      scheduledTripsPerHour: departureCount.toDouble(),
    ),
  ],
  averageHeadwaySeconds: headway?.toDouble(),
  medianHeadwaySeconds: headway?.toDouble(),
  minimumHeadwaySeconds: headway,
  maximumHeadwaySeconds: headway,
);

AiOperationalEvidence operationalEvidence() => AiOperationalEvidence(
  route: route,
  periodStart: periodStart,
  periodEnd: periodEnd,
  peakOperationSummary: PeakOperationSummary(
    routeId: 'J15',
    periodStart: periodStart,
    periodEnd: periodEnd,
    observationCount: 12,
    distinctTripOccurrences: 4,
    observedDayCount: 2,
    routesRepresented: 1,
    bucketBreakdown: const [],
    peakBuckets: const [
      OperationTimeBucket(
        startMinute: 480,
        averageActiveTrips: 2,
        level: ActivityLevel.high,
      ),
    ],
    averageActivity: 1.5,
    activityDifferencePercent: 25,
    dailyActivity: const [],
    routeActivity: const [],
    observedWindowStart: null,
    observedWindowEnd: null,
    hasReliablePeak: false,
    hasLimitedCoverage: true,
  ),
  routePerformanceSummary: const RoutePerformanceSummary(
    trips: [],
    totalObservations: 12,
    averageTravelTime: Duration(minutes: 42),
    delayedTripCount: 2,
    delayFrequencyPercent: 50,
    scheduleAdherencePercent: 75,
  ),
);

DistrictRouteStopEvidence districtEvidence({
  List<AiRouteTripEvidence>? trips,
  List<TripStopSpacingEvidence>? spacingByTrip,
  String longComment = 'feedback',
}) {
  final networkTrips =
      trips ??
      [
        routeTrip(
          'trip-a',
          [
            routeStop('stop-a', 1, const MapCoordinate(1.5, 103.7)),
            routeStop('stop-b', 2, null),
          ],
          shapeId: 'shape-a',
          distance: 12000,
        ),
        routeTrip(
          'trip-b',
          [
            routeStop('stop-a', 1, const MapCoordinate(1.5, 103.7)),
            routeStop('stop-c', 2, const MapCoordinate(1.6, 103.8)),
          ],
          shapeId: 'shape-b',
          distance: 14000,
        ),
      ];
  final records = [
    feedback('r1', 'Missing bus stop', longComment),
    feedback('r2', 'Missing bus stop', longComment),
    feedback('r3', 'Long walking distance', longComment),
    feedback('r4', 'Incorrect route information', longComment),
  ];
  final routeEvidence = RouteStopEvidence(
    routeId: 'J15',
    periodStart: periodStart,
    periodEnd: periodEnd,
    network: AiRouteNetworkEvidence(route: route, trips: networkTrips),
    operational: operationalEvidence(),
    feedback: RouteStopFeedbackEvidence(
      records: records,
      countByIssueType: const {
        'Missing bus stop': 2,
        'Long walking distance': 1,
        'Incorrect route information': 1,
      },
      routeStopRelevantRecords: records,
    ),
    stopSpacingByTrip:
        spacingByTrip ??
        const [
          TripStopSpacingEvidence(
            tripId: 'trip-a',
            consecutiveStops: [
              ConsecutiveStopSpacingEvidence(
                fromStopId: 'stop-a',
                fromStopSequence: 1,
                toStopId: 'stop-b',
                toStopSequence: 2,
                distanceMeters: 850.25,
              ),
            ],
          ),
        ],
  );
  final membership = networkTrips
      .map(
        (trip) => TripDistrictStopEvidence(
          tripId: trip.tripId,
          stops: trip.stops
              .map(
                (stop) => DistrictStopEvidence(
                  stopId: stop.stopId,
                  stopSequence: stop.stopSequence,
                  membership: stop.coordinate == null
                      ? DistrictStopMembership.unverifiable
                      : stop.stopId == 'stop-c'
                      ? DistrictStopMembership.outsideJohorBahruDistrict
                      : DistrictStopMembership.insideJohorBahruDistrict,
                ),
              )
              .toList(growable: false),
        ),
      )
      .toList(growable: false);
  return DistrictRouteStopEvidence(
    routeStopEvidence: routeEvidence,
    boundary: const DistrictBoundaryEvidence(
      status: DistrictBoundaryStatus.available,
      geometry: DistrictBoundaryGeometry(polygons: []),
      source: johorBahruDistrictBoundarySource,
    ),
    tripStopMembership: membership,
    stopOccurrenceCounts: const DistrictMembershipCounts(
      insideJohorBahruDistrict: 2,
      outsideJohorBahruDistrict: 1,
      unverifiable: 1,
    ),
    uniqueStopCounts: const DistrictMembershipCounts(
      insideJohorBahruDistrict: 1,
      outsideJohorBahruDistrict: 1,
      unverifiable: 1,
    ),
  );
}

AiRouteTripEvidence routeTrip(
  String tripId,
  List<AiRouteStopEvidence> stops, {
  String? shapeId,
  double? distance,
  int shapeCoordinateCount = 1,
}) => AiRouteTripEvidence(
  tripId: tripId,
  shapeId: shapeId ?? '$tripId-shape',
  stops: stops,
  shapePoints: List.generate(
    shapeCoordinateCount,
    (index) => ShapePoint(
      sequence: index + 1,
      coordinate: MapCoordinate(9 + index / 100, 99 + index / 100),
    ),
  ),
  routeDistanceMeters: distance,
);

AiRouteStopEvidence routeStop(
  String stopId,
  int sequence, [
  MapCoordinate? coordinate,
  String? stopName,
  int? arrival,
  int? departure,
]) => AiRouteStopEvidence(
  stopId: stopId,
  stopName: stopName ?? 'Name $stopId',
  stopSequence: sequence,
  coordinate: coordinate,
  scheduledArrivalSeconds: arrival,
  scheduledDepartureSeconds: departure,
);

FuelCostCalculationEvidence costEvidence({
  bool availablePrice = true,
  int departureCount = 2,
  FuelCostCalculationStatus status = FuelCostCalculationStatus.available,
}) {
  final departures = List.generate(
    departureCount,
    (index) => ScheduledDepartureFuelEvidence(
      departure: ScheduledDepartureEvidence(
        tripId: 'trip-$index',
        serviceDate: periodStart,
        departureSeconds: 21600 + index * 600,
        scheduledAt: periodStart.add(Duration(minutes: index * 10)),
        referenceStopId: 'stop-a',
        referenceStopSequence: 1,
      ),
      distanceStatus: ScheduledDepartureDistanceStatus.costable,
      tripDistanceMetres: 50000,
      vehicleKilometres: 50,
    ),
  );
  return FuelCostCalculationEvidence(
    route: route,
    periodStart: periodStart,
    periodEnd: periodEnd,
    referenceDate: referenceDate,
    dieselPrice: DieselPriceEvidence(
      status: availablePrice
          ? DieselPriceEvidenceStatus.available
          : DieselPriceEvidenceStatus.unavailable,
      source: fuelPriceSource,
      effectiveDate: availablePrice ? DateTime(2026, 8, 20) : null,
      rmPerLitre: availablePrice ? 2.5 : null,
    ),
    benchmark: malaysianUrbanBusFuelConsumptionBenchmark,
    directionGroups: [
      DirectionFuelCalculationEvidence(directionId: 0, departures: departures),
    ],
    totalScheduledDepartureCount: departureCount,
    costableScheduledDepartureCount: departureCount,
    uncostableDepartures: const [],
    scheduledVehicleKilometres: departureCount == 0 ? 0 : 100,
    lowEstimatedLitres: departureCount == 0 ? null : 27.94,
    highEstimatedLitres: departureCount == 0 ? null : 36.95,
    lowEstimatedFuelCostRm: departureCount == 0 || !availablePrice
        ? null
        : 69.85,
    highEstimatedFuelCostRm: departureCount == 0 || !availablePrice
        ? null
        : 92.375,
    status: status,
    scheduledServiceStatus: departureCount == 0
        ? ScheduledServiceEvidenceStatus.noDepartures
        : ScheduledServiceEvidenceStatus.available,
    incompleteTripIds: const [],
    hasCompleteDirectionData: true,
  );
}

AdminFeedbackRecord feedback(String id, String issueType, String comment) =>
    AdminFeedbackRecord(
      feedbackId: id,
      routeId: 'J15',
      tripId: null,
      stopId: 'stop-a',
      issueType: issueType,
      comment: comment,
      createdAt: periodStart,
    );

Map<String, int> _counts(Map<String, dynamic> feedbackPayload) => {
  for (final item in feedbackPayload['counts'] as List<dynamic>)
    item['issue_type'] as String: item['record_count'] as int,
};

Set<String> _allKeys(Object? value) {
  final keys = <String>{};
  if (value is Map<String, dynamic>) {
    for (final entry in value.entries) {
      keys.add(entry.key);
      keys.addAll(_allKeys(entry.value));
    }
  } else if (value is List<dynamic>) {
    for (final item in value) {
      keys.addAll(_allKeys(item));
    }
  }
  return keys;
}

void _expectNoProhibitedKeys(Map<String, dynamic> payload) {
  final keys = _allKeys(payload);
  for (final prohibited in [
    'passenger_demand',
    'occupancy',
    'capacity',
    'required_buses',
    'recommended_headway',
    'recommended_frequency',
    'proposed_stop',
    'suitability_score',
    'final_recommendation',
  ]) {
    expect(keys, isNot(contains(prohibited)));
  }
}

void _expectNoConfigurationKeys(Map<String, dynamic> payload) {
  final keys = _allKeys(payload).map((key) => key.toLowerCase()).toSet();
  expect(keys, isNot(contains('gemini_api_key')));
  expect(keys, isNot(contains('api_key')));
  expect(keys, isNot(contains('environment')));
  expect(keys, isNot(contains('headers')));
}
