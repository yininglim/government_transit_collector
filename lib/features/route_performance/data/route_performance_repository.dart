import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RouteScheduleStopRecord {
  const RouteScheduleStopRecord({
    required this.tripId,
    required this.stopSequence,
    required this.arrivalSeconds,
    required this.departureSeconds,
    required this.latitude,
    required this.longitude,
  });

  final String tripId;
  final int stopSequence;
  final int? arrivalSeconds;
  final int? departureSeconds;
  final double latitude;
  final double longitude;
}

abstract interface class RoutePerformanceDataSource {
  Future<List<RoutePerformanceRoute>> fetchRoutes();
  Future<List<String>> fetchObservedRouteIds({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required int offset,
    required int limit,
  });
  Future<List<HistoricalVehicleObservation>> fetchObservations({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required int offset,
    required int limit,
  });
  Future<List<RouteScheduleStopRecord>> fetchScheduleStops({
    required List<String> tripIds,
    required int offset,
    required int limit,
  });
}

abstract interface class PeriodHistoricalObservationDataSource {
  Future<List<HistoricalVehicleObservation>> fetchPeriodObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required int offset,
    required int limit,
  });
}

abstract interface class RoutePerformanceRepository {
  Future<List<RoutePerformanceRoute>> loadRoutes();
  Future<RoutePerformanceData> loadRoutePerformance({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  });
}

abstract interface class PeriodRoutePerformanceRepository {
  Future<List<RoutePerformanceRoute>> loadRoutesWithObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  });
}

class DefaultRoutePerformanceRepository
    implements RoutePerformanceRepository, PeriodRoutePerformanceRepository {
  DefaultRoutePerformanceRepository({RoutePerformanceDataSource? dataSource})
    : _dataSource = dataSource ?? SupabaseRoutePerformanceDataSource();

  static const pageSize = 1000;
  static const tripLookupBatchSize = 100;
  final RoutePerformanceDataSource _dataSource;

  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() => _dataSource.fetchRoutes();

  @override
  Future<List<RoutePerformanceRoute>> loadRoutesWithObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    try {
      final observedRouteIds = <String>{};
      for (var offset = 0; ; offset += pageSize) {
        final page = await _dataSource.fetchObservedRouteIds(
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
          offset: offset,
          limit: pageSize,
        );
        observedRouteIds.addAll(page);
        if (page.length < pageSize) break;
      }
      if (observedRouteIds.isEmpty) return const [];
      final routes = await _dataSource.fetchRoutes();
      return routes
          .where((route) => observedRouteIds.contains(route.routeId))
          .toList(growable: false);
    } on RoutePerformanceReadException {
      rethrow;
    } on Object {
      throw const RoutePerformanceReadException(
        'Unable to load routes with historical observations.',
      );
    }
  }

  @override
  Future<RoutePerformanceData> loadRoutePerformance({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    try {
      final observations = <HistoricalVehicleObservation>[];
      for (var offset = 0; ; offset += pageSize) {
        final page = await _dataSource.fetchObservations(
          routeId: routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
          offset: offset,
          limit: pageSize,
        );
        observations.addAll(page.where((item) => item.routeId == routeId));
        if (page.length < pageSize) break;
      }

      final tripIds = observations.map((item) => item.tripId).toSet().toList();
      final scheduleRows = <RouteScheduleStopRecord>[];
      for (
        var batchStart = 0;
        batchStart < tripIds.length;
        batchStart += tripLookupBatchSize
      ) {
        final batchEnd = batchStart + tripLookupBatchSize < tripIds.length
            ? batchStart + tripLookupBatchSize
            : tripIds.length;
        final batch = tripIds.sublist(batchStart, batchEnd);
        for (var offset = 0; ; offset += pageSize) {
          final page = await _dataSource.fetchScheduleStops(
            tripIds: batch,
            offset: offset,
            limit: pageSize,
          );
          scheduleRows.addAll(page);
          if (page.length < pageSize) break;
        }
      }
      return RoutePerformanceData(
        observations: observations,
        schedulesByTripId: _buildSchedules(scheduleRows),
      );
    } on RoutePerformanceReadException {
      rethrow;
    } on Object {
      throw const RoutePerformanceReadException(
        'Unable to load route performance data.',
      );
    }
  }

  static Map<String, ScheduledTripReference> _buildSchedules(
    List<RouteScheduleStopRecord> rows,
  ) {
    final grouped = <String, List<RouteScheduleStopRecord>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.tripId, () => []).add(row);
    }
    final schedules = <String, ScheduledTripReference>{};
    for (final entry in grouped.entries) {
      entry.value.sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
      final first = entry.value.first;
      final last = entry.value.last;
      final start = first.departureSeconds ?? first.arrivalSeconds;
      final end = last.arrivalSeconds ?? last.departureSeconds;
      if (start == null || end == null || end <= start) continue;
      schedules[entry.key] = ScheduledTripReference(
        tripId: entry.key,
        startSeconds: start,
        endSeconds: end,
        startLatitude: first.latitude,
        startLongitude: first.longitude,
        endLatitude: last.latitude,
        endLongitude: last.longitude,
      );
    }
    return schedules;
  }
}

class ScreeningRoutePerformanceRepository
    implements RoutePerformanceRepository {
  ScreeningRoutePerformanceRepository({
    required RoutePerformanceDataSource dataSource,
    required PeriodHistoricalObservationDataSource observationDataSource,
    required this.startUtc,
    required this.endExclusiveUtc,
  }) {
    _dataSource = dataSource;
    _observationDataSource = observationDataSource;
  }

  static const _pageSize = 1000;
  static const _tripLookupBatchSize = 100;

  late final RoutePerformanceDataSource _dataSource;
  late final PeriodHistoricalObservationDataSource _observationDataSource;
  final DateTime startUtc;
  final DateTime endExclusiveUtc;
  Future<List<RoutePerformanceRoute>>? _routesFuture;
  Future<Map<String, List<HistoricalVehicleObservation>>>? _observationsFuture;

  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() =>
      _routesFuture ??= _dataSource.fetchRoutes();

  @override
  Future<RoutePerformanceData> loadRoutePerformance({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    if (startUtc != this.startUtc || endExclusiveUtc != this.endExclusiveUtc) {
      throw const RoutePerformanceReadException(
        'The screening period does not match the historical context.',
      );
    }
    try {
      final grouped = await (_observationsFuture ??= _loadObservations());
      final observations = grouped[routeId] ?? const [];
      final tripIds = observations.map((item) => item.tripId).toSet().toList();
      final scheduleRows = <RouteScheduleStopRecord>[];
      for (
        var batchStart = 0;
        batchStart < tripIds.length;
        batchStart += _tripLookupBatchSize
      ) {
        final batchEnd = (batchStart + _tripLookupBatchSize).clamp(
          0,
          tripIds.length,
        );
        final batch = tripIds.sublist(batchStart, batchEnd);
        for (var offset = 0; ; offset += _pageSize) {
          final page = await _dataSource.fetchScheduleStops(
            tripIds: batch,
            offset: offset,
            limit: _pageSize,
          );
          scheduleRows.addAll(page);
          if (page.length < _pageSize) break;
        }
      }
      return RoutePerformanceData(
        observations: observations,
        schedulesByTripId: DefaultRoutePerformanceRepository._buildSchedules(
          scheduleRows,
        ),
      );
    } on RoutePerformanceReadException {
      rethrow;
    } on Object {
      throw const RoutePerformanceReadException(
        'Unable to load route performance data.',
      );
    }
  }

  Future<Map<String, List<HistoricalVehicleObservation>>>
  _loadObservations() async {
    final grouped = <String, List<HistoricalVehicleObservation>>{};
    for (var offset = 0; ; offset += _pageSize) {
      final page = await _observationDataSource.fetchPeriodObservations(
        startUtc: startUtc,
        endExclusiveUtc: endExclusiveUtc,
        offset: offset,
        limit: _pageSize,
      );
      for (final observation in page) {
        grouped.putIfAbsent(observation.routeId, () => []).add(observation);
      }
      if (page.length < _pageSize) break;
    }
    return grouped;
  }
}

class SupabaseRoutePerformanceDataSource
    implements
        RoutePerformanceDataSource,
        PeriodHistoricalObservationDataSource {
  SupabaseRoutePerformanceDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<RoutePerformanceRoute>> fetchRoutes() async {
    try {
      final rows = await _client
          .from('gtfs_routes')
          .select('route_id, route_short_name, route_long_name')
          .order('route_short_name')
          .order('route_long_name');
      return rows
          .map(
            (row) => RoutePerformanceRoute(
              routeId: row['route_id'] as String,
              shortName: row['route_short_name'] as String?,
              longName: row['route_long_name'] as String?,
            ),
          )
          .toList(growable: false);
    } on Object {
      throw const RoutePerformanceReadException('Unable to load routes.');
    }
  }

  @override
  Future<List<String>> fetchObservedRouteIds({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required int offset,
    required int limit,
  }) async {
    try {
      final rows = await _client
          .from('vehicle_positions')
          .select('route_id, position_id')
          .gte('recorded_at', startUtc.toUtc().toIso8601String())
          .lt('recorded_at', endExclusiveUtc.toUtc().toIso8601String())
          .order('route_id')
          .order('position_id')
          .range(offset, offset + limit - 1);
      return rows
          .map((row) => row['route_id'] as String)
          .toList(growable: false);
    } on Object {
      throw const RoutePerformanceReadException(
        'Unable to load routes with historical observations.',
      );
    }
  }

  @override
  Future<List<HistoricalVehicleObservation>> fetchObservations({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required int offset,
    required int limit,
  }) async {
    try {
      final rows = await _client
          .from('vehicle_positions')
          .select(
            'route_id, trip_id, vehicle_id, recorded_at, latitude, longitude',
          )
          .eq('route_id', routeId)
          .gte('recorded_at', startUtc.toUtc().toIso8601String())
          .lt('recorded_at', endExclusiveUtc.toUtc().toIso8601String())
          .order('recorded_at')
          .range(offset, offset + limit - 1);
      return rows
          .map(
            (row) => HistoricalVehicleObservation(
              routeId: row['route_id'] as String,
              tripId: row['trip_id'] as String,
              vehicleId: row['vehicle_id'] as String,
              recordedAt: DateTime.parse(row['recorded_at'] as String).toUtc(),
              latitude: (row['latitude'] as num).toDouble(),
              longitude: (row['longitude'] as num).toDouble(),
            ),
          )
          .toList(growable: false);
    } on Object {
      throw const RoutePerformanceReadException(
        'Unable to load historical observations.',
      );
    }
  }

  @override
  Future<List<HistoricalVehicleObservation>> fetchPeriodObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required int offset,
    required int limit,
  }) async {
    try {
      final rows = await _client
          .from('vehicle_positions')
          .select(
            'route_id, trip_id, vehicle_id, recorded_at, latitude, longitude',
          )
          .gte('recorded_at', startUtc.toUtc().toIso8601String())
          .lt('recorded_at', endExclusiveUtc.toUtc().toIso8601String())
          .order('recorded_at')
          .range(offset, offset + limit - 1);
      return rows
          .map(
            (row) => HistoricalVehicleObservation(
              routeId: row['route_id'] as String,
              tripId: row['trip_id'] as String,
              vehicleId: row['vehicle_id'] as String,
              recordedAt: DateTime.parse(row['recorded_at'] as String).toUtc(),
              latitude: (row['latitude'] as num).toDouble(),
              longitude: (row['longitude'] as num).toDouble(),
            ),
          )
          .toList(growable: false);
    } on Object {
      throw const RoutePerformanceReadException(
        'Unable to load historical observations.',
      );
    }
  }

  @override
  Future<List<RouteScheduleStopRecord>> fetchScheduleStops({
    required List<String> tripIds,
    required int offset,
    required int limit,
  }) async {
    if (tripIds.isEmpty) return const [];
    try {
      final rows = await _client
          .from('gtfs_stop_times')
          .select(
            'trip_id, stop_sequence, arrival_seconds, departure_seconds, '
            'gtfs_stops!inner(stop_lat, stop_lon)',
          )
          .inFilter('trip_id', tripIds)
          .order('trip_id')
          .order('stop_sequence')
          .range(offset, offset + limit - 1);
      return rows
          .map((row) {
            final stop = row['gtfs_stops'] as Map<String, dynamic>;
            return RouteScheduleStopRecord(
              tripId: row['trip_id'] as String,
              stopSequence: (row['stop_sequence'] as num).toInt(),
              arrivalSeconds: (row['arrival_seconds'] as num?)?.toInt(),
              departureSeconds: (row['departure_seconds'] as num?)?.toInt(),
              latitude: (stop['stop_lat'] as num).toDouble(),
              longitude: (stop['stop_lon'] as num).toDouble(),
            );
          })
          .toList(growable: false);
    } on Object {
      throw const RoutePerformanceReadException(
        'Unable to load GTFS schedules.',
      );
    }
  }
}

class RoutePerformanceReadException implements Exception {
  const RoutePerformanceReadException(this.message);
  final String message;

  @override
  String toString() => message;
}
