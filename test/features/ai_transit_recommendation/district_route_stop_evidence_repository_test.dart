import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/johor_bahru_boundary_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/johor_bahru_boundary_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'official request filters the district and asks for EPSG 4326',
    () async {
      late Uri requested;
      final source = MyGeoportalDistrictBoundaryDataSource(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(polygonGeoJson, 200);
        }),
      );

      await source.fetchJohorBahruDistrict();

      expect(
        requested.toString(),
        startsWith(johorBahruDistrictBoundaryEndpoint),
      );
      expect(
        requested.queryParameters['where'],
        contains("NAM = 'JOHOR BAHRU'"),
      );
      expect(requested.queryParameters['where'], contains("KOD_NEGERI = '01'"));
      expect(requested.queryParameters['where'], contains("KOD_DAERAH = '02'"));
      expect(requested.queryParameters['outSR'], '4326');
      expect(requested.queryParameters['f'], 'geojson');
    },
  );

  test('classifies inside outside boundary and missing coordinates', () async {
    final original = evidence(
      trips: [
        trip('trip-a', [
          stop('inside', 1, const MapCoordinate(1, 1)),
          stop('outside', 2, const MapCoordinate(3, 3)),
          stop('boundary', 3, const MapCoordinate(1, 0)),
          stop('missing', 4, null),
        ]),
      ],
    );
    final result = await repository(original: original).loadEvidence(
      routeId: 'J15',
      startUtc: periodStart,
      endExclusiveUtc: periodEnd,
    );
    final memberships = result.tripStopMembership.single.stops;

    expect(memberships.map((item) => item.membership), [
      DistrictStopMembership.insideJohorBahruDistrict,
      DistrictStopMembership.outsideJohorBahruDistrict,
      DistrictStopMembership.insideJohorBahruDistrict,
      DistrictStopMembership.unverifiable,
    ]);
    expect(result.stopOccurrenceCounts.insideJohorBahruDistrict, 2);
    expect(result.stopOccurrenceCounts.outsideJohorBahruDistrict, 1);
    expect(result.stopOccurrenceCounts.unverifiable, 1);
  });

  test(
    'unavailable boundary preserves evidence and makes all unverifiable',
    () async {
      final original = evidence(
        trips: [
          trip('trip-a', [stop('a', 1, const MapCoordinate(1, 1))]),
        ],
      );
      final result =
          await repository(
            original: original,
            boundary: const DistrictBoundaryEvidence(
              status: DistrictBoundaryStatus.unavailable,
              geometry: null,
              source: johorBahruDistrictBoundarySource,
            ),
          ).loadEvidence(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );

      expect(result.routeStopEvidence, same(original));
      expect(result.boundary.status, DistrictBoundaryStatus.unavailable);
      expect(result.stopOccurrenceCounts.unverifiable, 1);
    },
  );

  test('malformed response becomes unusable boundary evidence', () async {
    final repository = DefaultDistrictBoundaryRepository(
      dataSource: MalformedBoundaryDataSource(),
    );

    final result = await repository.loadBoundary();

    expect(result.status, DistrictBoundaryStatus.unusable);
    expect(result.geometry, isNull);
    expect(result.source.custodian, 'JUPEM');
    expect(result.source.referenceDate, 'August 2019');
  });

  test('boundary API failure becomes unavailable evidence', () async {
    final repository = DefaultDistrictBoundaryRepository(
      dataSource: UnavailableBoundaryDataSource(),
    );

    final result = await repository.loadBoundary();

    expect(result.status, DistrictBoundaryStatus.unavailable);
    expect(result.geometry, isNull);
  });

  test(
    'cross-boundary route and multiple shape variants remain complete',
    () async {
      final original = evidence(
        trips: [
          trip('trip-a', [
            stop('inside', 1, const MapCoordinate(1, 1)),
            stop('outside', 2, const MapCoordinate(3, 3)),
          ], shapeId: 'shape-a'),
          trip('trip-b', [
            stop('inside', 1, const MapCoordinate(1, 1)),
          ], shapeId: 'shape-b'),
        ],
      );

      final result = await repository(original: original).loadEvidence(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      expect(result.routeStopEvidence, same(original));
      expect(result.routeStopEvidence.network.trips, hasLength(2));
      expect(
        result.routeStopEvidence.network.trips.map((item) => item.shapeId),
        ['shape-a', 'shape-b'],
      );
      expect(result.tripStopMembership.first.stops, hasLength(2));
      expect(result.tripStopMembership.last.stops, hasLength(1));
      expect(result.stopOccurrenceCounts.total, 3);
      expect(result.uniqueStopCounts.total, 2);
      expect(result.stopOccurrenceCounts.insideJohorBahruDistrict, 2);
      expect(result.uniqueStopCounts.insideJohorBahruDistrict, 1);
    },
  );

  test(
    'conflicting repeated stop evidence is unverifiable only when unique',
    () async {
      final original = evidence(
        trips: [
          trip('trip-a', [stop('same', 1, const MapCoordinate(1, 1))]),
          trip('trip-b', [stop('same', 1, const MapCoordinate(3, 3))]),
        ],
      );
      final result = await repository(original: original).loadEvidence(
        routeId: 'J15',
        startUtc: periodStart,
        endExclusiveUtc: periodEnd,
      );

      expect(result.stopOccurrenceCounts.insideJohorBahruDistrict, 1);
      expect(result.stopOccurrenceCounts.outsideJohorBahruDistrict, 1);
      expect(result.uniqueStopCounts.unverifiable, 1);
    },
  );

  test('parses polygon holes and multipolygon geometry', () {
    final polygon = parseDistrictBoundaryGeoJson(polygonWithHoleGeoJson);
    final multiPolygon = parseDistrictBoundaryGeoJson(multiPolygonGeoJson);

    expect(polygon.polygons, hasLength(1));
    expect(polygon.polygons.single.holes, hasLength(1));
    expect(multiPolygon.polygons, hasLength(2));
    expect(multiPolygon.polygons.first.exterior.first.latitude, 0);
    expect(multiPolygon.polygons.last.exterior.first.longitude, 10);
  });

  test(
    'point inside polygon hole is outside while hole edge is inside',
    () async {
      final geometry = parseDistrictBoundaryGeoJson(polygonWithHoleGeoJson);
      final original = evidence(
        trips: [
          trip('trip-a', [
            stop('hole', 1, const MapCoordinate(1, 1)),
            stop('hole-edge', 2, const MapCoordinate(1, 0.5)),
          ]),
        ],
      );
      final result =
          await repository(
            original: original,
            boundary: availableBoundary(geometry),
          ).loadEvidence(
            routeId: 'J15',
            startUtc: periodStart,
            endExclusiveUtc: periodEnd,
          );

      expect(
        result.tripStopMembership.single.stops.map((item) => item.membership),
        [
          DistrictStopMembership.outsideJohorBahruDistrict,
          DistrictStopMembership.insideJohorBahruDistrict,
        ],
      );
    },
  );
}

const polygonGeoJson = '''
{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"NAM":"JOHOR BAHRU","KOD_NEGERI":"01","KOD_DAERAH":"02","Sumber":"JUPEM","Tahun_Kemaskini":"OGOS 2019"},"geometry":{"type":"Polygon","coordinates":[[[0,0],[2,0],[2,2],[0,2],[0,0]]]}}]}
''';

const polygonWithHoleGeoJson = '''
{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"NAM":"JOHOR BAHRU","KOD_NEGERI":"01","KOD_DAERAH":"02"},"geometry":{"type":"Polygon","coordinates":[[[0,0],[2,0],[2,2],[0,2],[0,0]],[[0.5,0.5],[1.5,0.5],[1.5,1.5],[0.5,1.5],[0.5,0.5]]]}}]}
''';

const multiPolygonGeoJson = '''
{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"NAM":"JOHOR BAHRU","KOD_NEGERI":"01","KOD_DAERAH":"02"},"geometry":{"type":"MultiPolygon","coordinates":[[[[0,0],[2,0],[2,2],[0,2],[0,0]]],[[[10,10],[12,10],[12,12],[10,12],[10,10]]]]}}]}
''';

final periodStart = DateTime.utc(2026, 8, 20);
final periodEnd = DateTime.utc(2026, 8, 27);

DefaultDistrictRouteStopEvidenceRepository repository({
  required RouteStopEvidence original,
  DistrictBoundaryEvidence? boundary,
}) {
  return DefaultDistrictRouteStopEvidenceRepository(
    routeStopRepository: FakeRouteStopRepository(original),
    boundaryRepository: FakeBoundaryRepository(
      boundary ??
          availableBoundary(parseDistrictBoundaryGeoJson(polygonGeoJson)),
    ),
  );
}

DistrictBoundaryEvidence availableBoundary(DistrictBoundaryGeometry geometry) {
  return DistrictBoundaryEvidence(
    status: DistrictBoundaryStatus.available,
    geometry: geometry,
    source: johorBahruDistrictBoundarySource,
  );
}

RouteStopEvidence evidence({required List<AiRouteTripEvidence> trips}) {
  final network = AiRouteNetworkEvidence(route: route, trips: trips);
  return RouteStopEvidence(
    routeId: 'J15',
    periodStart: periodStart,
    periodEnd: periodEnd,
    network: network,
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
    feedback: const RouteStopFeedbackEvidence(
      records: [],
      countByIssueType: {},
      routeStopRelevantRecords: [],
    ),
    stopSpacingByTrip: const [],
  );
}

AiRouteTripEvidence trip(
  String tripId,
  List<AiRouteStopEvidence> stops, {
  String? shapeId,
}) {
  return AiRouteTripEvidence(
    tripId: tripId,
    shapeId: shapeId,
    stops: stops,
    shapePoints: [
      ShapePoint(sequence: 1, coordinate: const MapCoordinate(1, 1)),
    ],
    routeDistanceMeters: null,
  );
}

AiRouteStopEvidence stop(
  String stopId,
  int sequence,
  MapCoordinate? coordinate,
) {
  return AiRouteStopEvidence(
    stopId: stopId,
    stopName: stopId,
    stopSequence: sequence,
    coordinate: coordinate,
    scheduledArrivalSeconds: null,
    scheduledDepartureSeconds: null,
  );
}

const route = RoutePerformanceRoute(
  routeId: 'J15',
  shortName: 'J15',
  longName: 'Johor Bahru route',
);

class FakeRouteStopRepository implements RouteStopEvidenceRepository {
  FakeRouteStopRepository(this.result);

  final RouteStopEvidence result;

  @override
  Future<RouteStopEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async => result;
}

class FakeBoundaryRepository implements DistrictBoundaryRepository {
  FakeBoundaryRepository(this.result);

  final DistrictBoundaryEvidence result;

  @override
  Future<DistrictBoundaryEvidence> loadBoundary() async => result;
}

class MalformedBoundaryDataSource implements DistrictBoundaryDataSource {
  @override
  Future<DistrictBoundaryGeometry> fetchJohorBahruDistrict() {
    throw const DistrictBoundaryFormatException('malformed');
  }
}

class UnavailableBoundaryDataSource implements DistrictBoundaryDataSource {
  @override
  Future<DistrictBoundaryGeometry> fetchJohorBahruDistrict() {
    throw const DistrictBoundaryReadException('unavailable');
  }
}
