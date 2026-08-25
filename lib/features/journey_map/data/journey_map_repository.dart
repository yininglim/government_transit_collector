import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TripShapeReference {
  const TripShapeReference({required this.tripId, required this.shapeId});

  final String tripId;
  final String? shapeId;
}

class MapStopRecord {
  const MapStopRecord({
    required this.stopId,
    required this.name,
    required this.coordinate,
  });

  final String stopId;
  final String name;
  final MapCoordinate? coordinate;
}

abstract interface class JourneyMapDataSource {
  Future<List<TripShapeReference>> loadTripShapes(List<String> tripIds);
  Future<List<MapStopRecord>> loadStops(List<String> stopIds);
  Future<Map<String, List<ShapePoint>>> loadShapePoints(List<String> shapeIds);
}

abstract interface class JourneyMapRepository {
  Future<JourneyMapData> loadJourney(JourneyRecommendation recommendation);
}

class GtfsJourneyMapRepository implements JourneyMapRepository {
  GtfsJourneyMapRepository({this.dataSource});

  final JourneyMapDataSource? dataSource;

  @override
  Future<JourneyMapData> loadJourney(
    JourneyRecommendation recommendation,
  ) async {
    final source = dataSource ?? SupabaseJourneyMapDataSource();
    final specification = _JourneySpecification.from(recommendation);
    final results = await Future.wait([
      source.loadTripShapes(specification.tripIds),
      source.loadStops(specification.stopIds),
    ]);
    final tripShapes = results[0] as List<TripShapeReference>;
    final stopRecords = results[1] as List<MapStopRecord>;
    final stopsById = {for (final stop in stopRecords) stop.stopId: stop};
    final shapeByTrip = {
      for (final trip in tripShapes) trip.tripId: trip.shapeId,
    };
    final shapeIds = shapeByTrip.values
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final pointsByShape = shapeIds.isEmpty
        ? <String, List<ShapePoint>>{}
        : await source.loadShapePoints(shapeIds);

    final mapStops = <JourneyMapStop>[];
    for (final stopSpec in specification.stops) {
      final stop = stopsById[stopSpec.stopId];
      if (stop?.coordinate != null) {
        mapStops.add(
          JourneyMapStop(
            stopId: stop!.stopId,
            name: stop.name,
            coordinate: stop.coordinate!,
            role: stopSpec.role,
          ),
        );
      }
    }

    final legs = <JourneyMapLeg>[];
    for (final leg in specification.legs) {
      final from = stopsById[leg.fromStopId]?.coordinate;
      final to = stopsById[leg.toStopId]?.coordinate;
      final shapeId = shapeByTrip[leg.tripId];
      final fullPoints =
          shapeId == null
                ? const <ShapePoint>[]
                : [...pointsByShape[shapeId] ?? const <ShapePoint>[]]
            ..sort((left, right) => left.sequence.compareTo(right.sequence));
      final segment = from == null || to == null
          ? const ShapeSegment(points: [], usedFullShapeFallback: false)
          : segmentShape(
              shapePoints: fullPoints,
              boarding: from,
              alighting: to,
            );
      legs.add(
        JourneyMapLeg(
          tripId: leg.tripId,
          routeLabel: leg.routeLabel,
          points: segment.points,
          usedFullShapeFallback: segment.usedFullShapeFallback,
        ),
      );
    }
    return JourneyMapData(stops: mapStops, legs: legs);
  }
}

class SupabaseJourneyMapDataSource implements JourneyMapDataSource {
  SupabaseJourneyMapDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _pageSize = 1000;

  @override
  Future<List<TripShapeReference>> loadTripShapes(List<String> tripIds) async {
    final rows = await _client
        .from('gtfs_trips')
        .select('trip_id, shape_id')
        .inFilter('trip_id', tripIds);
    return rows
        .map(
          (row) => TripShapeReference(
            tripId: row['trip_id'] as String,
            shapeId: row['shape_id'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<List<MapStopRecord>> loadStops(List<String> stopIds) async {
    final rows = await _client
        .from('gtfs_stops')
        .select('stop_id, stop_name, stop_lat, stop_lon')
        .inFilter('stop_id', stopIds);
    return rows.map((row) {
      final latitude = (row['stop_lat'] as num?)?.toDouble();
      final longitude = (row['stop_lon'] as num?)?.toDouble();
      return MapStopRecord(
        stopId: row['stop_id'] as String,
        name: row['stop_name'] as String,
        coordinate: latitude == null || longitude == null
            ? null
            : MapCoordinate(latitude, longitude),
      );
    }).toList();
  }

  @override
  Future<Map<String, List<ShapePoint>>> loadShapePoints(
    List<String> shapeIds,
  ) async {
    final pointsByShape = <String, List<ShapePoint>>{};
    var start = 0;
    while (true) {
      final rows = await _client
          .from('gtfs_shapes')
          .select('shape_id, shape_pt_sequence, shape_pt_lat, shape_pt_lon')
          .inFilter('shape_id', shapeIds)
          .order('shape_id', ascending: true)
          .order('shape_pt_sequence', ascending: true)
          .range(start, start + _pageSize - 1);
      for (final row in rows) {
        final point = ShapePoint(
          sequence: (row['shape_pt_sequence'] as num).toInt(),
          coordinate: MapCoordinate(
            (row['shape_pt_lat'] as num).toDouble(),
            (row['shape_pt_lon'] as num).toDouble(),
          ),
        );
        pointsByShape
            .putIfAbsent(row['shape_id'] as String, () => [])
            .add(point);
      }
      if (rows.length < _pageSize) break;
      start += _pageSize;
    }
    for (final points in pointsByShape.values) {
      points.sort((left, right) => left.sequence.compareTo(right.sequence));
    }
    return pointsByShape;
  }
}

class _JourneySpecification {
  const _JourneySpecification({required this.stops, required this.legs});

  factory _JourneySpecification.from(JourneyRecommendation recommendation) {
    String label(String routeId, String? shortName) =>
        shortName?.trim().isNotEmpty == true ? shortName!.trim() : routeId;
    return switch (recommendation) {
      DirectJourneyRecommendation direct => _JourneySpecification(
        stops: [
          _StopSpecification(direct.originStopId, JourneyStopRole.origin),
          _StopSpecification(
            direct.destinationStopId,
            JourneyStopRole.destination,
          ),
        ],
        legs: [
          _LegSpecification(
            tripId: direct.tripId,
            routeLabel: label(direct.routeId, direct.routeShortName),
            fromStopId: direct.originStopId,
            toStopId: direct.destinationStopId,
          ),
        ],
      ),
      TransferJourneyRecommendation transfer => _JourneySpecification(
        stops: [
          _StopSpecification(transfer.originStopId, JourneyStopRole.origin),
          _StopSpecification(transfer.transferStopId, JourneyStopRole.transfer),
          _StopSpecification(
            transfer.destinationStopId,
            JourneyStopRole.destination,
          ),
        ],
        legs: [
          _LegSpecification(
            tripId: transfer.firstTripId,
            routeLabel: label(
              transfer.firstRouteId,
              transfer.firstRouteShortName,
            ),
            fromStopId: transfer.originStopId,
            toStopId: transfer.transferStopId,
          ),
          _LegSpecification(
            tripId: transfer.secondTripId,
            routeLabel: label(
              transfer.secondRouteId,
              transfer.secondRouteShortName,
            ),
            fromStopId: transfer.transferStopId,
            toStopId: transfer.destinationStopId,
          ),
        ],
      ),
    };
  }

  final List<_StopSpecification> stops;
  final List<_LegSpecification> legs;
  List<String> get tripIds => legs.map((leg) => leg.tripId).toList();
  List<String> get stopIds => stops.map((stop) => stop.stopId).toList();
}

class _StopSpecification {
  const _StopSpecification(this.stopId, this.role);
  final String stopId;
  final JourneyStopRole role;
}

class _LegSpecification {
  const _LegSpecification({
    required this.tripId,
    required this.routeLabel,
    required this.fromStopId,
    required this.toStopId,
  });
  final String tripId;
  final String routeLabel;
  final String fromStopId;
  final String toStopId;
}
