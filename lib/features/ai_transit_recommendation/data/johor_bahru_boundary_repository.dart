import 'dart:async';
import 'dart:convert';

import 'package:government_transit_collector/features/ai_transit_recommendation/data/johor_bahru_boundary_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:http/http.dart' as http;

const johorBahruDistrictBoundaryEndpoint =
    'https://mygos.mygeoportal.gov.my/gisserver/rest/services/'
    'MyGeomap/Msia_Coverage/MapServer/2/query';

abstract interface class DistrictBoundaryDataSource {
  Future<DistrictBoundaryGeometry> fetchJohorBahruDistrict();
}

abstract interface class DistrictBoundaryRepository {
  Future<DistrictBoundaryEvidence> loadBoundary();
}

class DefaultDistrictBoundaryRepository implements DistrictBoundaryRepository {
  DefaultDistrictBoundaryRepository({DistrictBoundaryDataSource? dataSource})
    : _dataSource = dataSource ?? MyGeoportalDistrictBoundaryDataSource();

  final DistrictBoundaryDataSource _dataSource;

  @override
  Future<DistrictBoundaryEvidence> loadBoundary() async {
    try {
      final geometry = await _dataSource.fetchJohorBahruDistrict();
      return DistrictBoundaryEvidence(
        status: DistrictBoundaryStatus.available,
        geometry: geometry,
        source: johorBahruDistrictBoundarySource,
      );
    } on DistrictBoundaryFormatException {
      return const DistrictBoundaryEvidence(
        status: DistrictBoundaryStatus.unusable,
        geometry: null,
        source: johorBahruDistrictBoundarySource,
      );
    } on Object {
      return const DistrictBoundaryEvidence(
        status: DistrictBoundaryStatus.unavailable,
        geometry: null,
        source: johorBahruDistrictBoundarySource,
      );
    }
  }
}

class MyGeoportalDistrictBoundaryDataSource
    implements DistrictBoundaryDataSource {
  MyGeoportalDistrictBoundaryDataSource({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration requestTimeout;

  @override
  Future<DistrictBoundaryGeometry> fetchJohorBahruDistrict() async {
    try {
      final uri = Uri.parse(johorBahruDistrictBoundaryEndpoint).replace(
        queryParameters: const {
          'where':
              "NAM = 'JOHOR BAHRU' AND KOD_NEGERI = '01' AND KOD_DAERAH = '02'",
          'outFields': 'NAM,KOD_NEGERI,KOD_DAERAH,Sumber,Tahun_Kemaskini',
          'returnGeometry': 'true',
          'outSR': '4326',
          'f': 'geojson',
        },
      );
      final response = await _client.get(uri).timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DistrictBoundaryReadException(
          'Boundary service returned HTTP ${response.statusCode}.',
        );
      }
      return parseDistrictBoundaryGeoJson(response.body);
    } on DistrictBoundaryFormatException {
      rethrow;
    } on DistrictBoundaryReadException {
      rethrow;
    } on TimeoutException {
      throw const DistrictBoundaryReadException(
        'The district boundary request timed out.',
      );
    } on Object {
      throw const DistrictBoundaryReadException(
        'Unable to retrieve the district boundary.',
      );
    }
  }
}

DistrictBoundaryGeometry parseDistrictBoundaryGeoJson(String body) {
  try {
    final root = jsonDecode(body) as Map<String, dynamic>;
    final features = root['features'] as List<dynamic>;
    final feature = features.cast<Map<String, dynamic>>().where((item) {
      final properties = item['properties'] as Map<String, dynamic>?;
      return properties?['NAM'] == 'JOHOR BAHRU' &&
          properties?['KOD_NEGERI']?.toString() == '01' &&
          properties?['KOD_DAERAH']?.toString() == '02';
    }).firstOrNull;
    if (feature == null) throw const FormatException();
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final type = geometry['type'] as String;
    final coordinates = geometry['coordinates'] as List<dynamic>;
    final polygons = switch (type) {
      'Polygon' => [_parsePolygon(coordinates)],
      'MultiPolygon' =>
        coordinates
            .map((polygon) => _parsePolygon(polygon as List<dynamic>))
            .toList(growable: false),
      _ => throw const FormatException(),
    };
    if (polygons.isEmpty) throw const FormatException();
    return DistrictBoundaryGeometry(polygons: polygons);
  } on DistrictBoundaryFormatException {
    rethrow;
  } on Object {
    throw const DistrictBoundaryFormatException(
      'The district boundary response is unusable.',
    );
  }
}

DistrictBoundaryPolygon _parsePolygon(List<dynamic> rings) {
  if (rings.isEmpty) throw const FormatException();
  final parsed = rings
      .map((ring) {
        final points = (ring as List<dynamic>)
            .map((position) {
              final values = position as List<dynamic>;
              if (values.length < 2) throw const FormatException();
              final longitude = (values[0] as num).toDouble();
              final latitude = (values[1] as num).toDouble();
              if (!longitude.isFinite ||
                  !latitude.isFinite ||
                  longitude < -180 ||
                  longitude > 180 ||
                  latitude < -90 ||
                  latitude > 90) {
                throw const FormatException();
              }
              return MapCoordinate(latitude, longitude);
            })
            .toList(growable: false);
        if (points.length < 4) throw const FormatException();
        return points;
      })
      .toList(growable: false);
  return DistrictBoundaryPolygon(
    exterior: parsed.first,
    holes: parsed.skip(1).toList(growable: false),
  );
}

class DistrictBoundaryReadException implements Exception {
  const DistrictBoundaryReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DistrictBoundaryFormatException implements Exception {
  const DistrictBoundaryFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
