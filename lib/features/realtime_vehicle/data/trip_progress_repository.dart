import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/shape_segment.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TripStopTimeRecord {
  const TripStopTimeRecord({
    required this.stopId,
    required this.stopSequence,
    required this.arrivalSeconds,
    required this.departureSeconds,
  });

  final String stopId;
  final int stopSequence;
  final int? arrivalSeconds;
  final int? departureSeconds;
}

abstract interface class TripProgressStopTimeDataSource {
  Future<List<TripStopTimeRecord>> loadStopTimes(String tripId);
}

abstract interface class TripProgressRepository {
  Future<TripProgressData> loadTrip(String exactTripId);
}

class GtfsTripProgressRepository implements TripProgressRepository {
  GtfsTripProgressRepository({
    JourneyMapDataSource? mapDataSource,
    TripProgressStopTimeDataSource? stopTimeDataSource,
  }) : _mapDataSource = mapDataSource ?? SupabaseJourneyMapDataSource(),
       _stopTimeDataSource =
           stopTimeDataSource ?? SupabaseTripProgressStopTimeDataSource();

  final JourneyMapDataSource _mapDataSource;
  final TripProgressStopTimeDataSource _stopTimeDataSource;

  @override
  Future<TripProgressData> loadTrip(String exactTripId) async {
    final results = await Future.wait([
      _mapDataSource.loadTripShapes([exactTripId]),
      _stopTimeDataSource.loadStopTimes(exactTripId),
    ]);
    final references = results[0] as List<TripShapeReference>;
    final stopTimes = [...results[1] as List<TripStopTimeRecord>];
    stopTimes.sort((a, b) => a.stopSequence.compareTo(b.stopSequence));

    final stopIds = stopTimes.map((record) => record.stopId).toSet().toList();
    final stopRecords = stopIds.isEmpty
        ? const <MapStopRecord>[]
        : await _mapDataSource.loadStops(stopIds);
    final stopsById = {for (final stop in stopRecords) stop.stopId: stop};

    final shapeId = references
        .where((reference) => reference.tripId == exactTripId)
        .map((reference) => reference.shapeId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .firstOrNull;
    final shapePoints = shapeId == null
        ? const <String, List<ShapePoint>>{}
        : await _mapDataSource.loadShapePoints([shapeId]);
    final orderedShapePoints =
        shapeId == null
              ? const <ShapePoint>[]
              : [...shapePoints[shapeId] ?? const <ShapePoint>[]]
          ..sort((left, right) => left.sequence.compareTo(right.sequence));

    return TripProgressData(
      tripId: exactTripId,
      shapePoints: orderedShapePoints
          .map((point) => point.coordinate)
          .toList(growable: false),
      stops: [
        for (final stopTime in stopTimes)
          TrackedTripStop(
            stopId: stopTime.stopId,
            stopName: stopsById[stopTime.stopId]?.name ?? 'Unknown stop',
            stopSequence: stopTime.stopSequence,
            coordinate: stopsById[stopTime.stopId]?.coordinate,
            scheduledArrivalSeconds: stopTime.arrivalSeconds,
            scheduledDepartureSeconds: stopTime.departureSeconds,
          ),
      ],
    );
  }
}

class SupabaseTripProgressStopTimeDataSource
    implements TripProgressStopTimeDataSource {
  SupabaseTripProgressStopTimeDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _pageSize = 1000;

  @override
  Future<List<TripStopTimeRecord>> loadStopTimes(String tripId) async {
    final records = <TripStopTimeRecord>[];
    var start = 0;
    while (true) {
      final rows = await _client
          .from('gtfs_stop_times')
          .select('stop_id, stop_sequence, arrival_seconds, departure_seconds')
          .eq('trip_id', tripId)
          .order('stop_sequence')
          .range(start, start + _pageSize - 1);
      records.addAll(
        rows.map(
          (row) => TripStopTimeRecord(
            stopId: row['stop_id'] as String,
            stopSequence: (row['stop_sequence'] as num).toInt(),
            arrivalSeconds: (row['arrival_seconds'] as num?)?.toInt(),
            departureSeconds: (row['departure_seconds'] as num?)?.toInt(),
          ),
        ),
      );
      if (rows.length < _pageSize) break;
      start += _pageSize;
    }
    return records;
  }
}
