import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class PeakOperationDataSource {
  Future<List<PeakOperationRoute>> fetchRoutes();
  Future<List<PeakOperationObservation>> fetchObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required String? routeId,
    required int offset,
    required int limit,
  });
}

abstract interface class PeakOperationRepository {
  Future<List<PeakOperationRoute>> loadRoutes();
  Future<List<PeakOperationObservation>> loadObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    String? routeId,
  });
}

class DefaultPeakOperationRepository implements PeakOperationRepository {
  DefaultPeakOperationRepository({PeakOperationDataSource? dataSource})
    : _dataSource = dataSource ?? SupabasePeakOperationDataSource();
  static const pageSize = 1000;
  final PeakOperationDataSource _dataSource;

  @override
  Future<List<PeakOperationRoute>> loadRoutes() => _dataSource.fetchRoutes();

  @override
  Future<List<PeakOperationObservation>> loadObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    String? routeId,
  }) async {
    try {
      final result = <PeakOperationObservation>[];
      for (var offset = 0; ; offset += pageSize) {
        final page = await _dataSource.fetchObservations(
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
          routeId: routeId,
          offset: offset,
          limit: pageSize,
        );
        result.addAll(
          page.where((row) => routeId == null || row.routeId == routeId),
        );
        if (page.length < pageSize) break;
      }
      return result;
    } on PeakOperationReadException {
      rethrow;
    } on Object {
      throw const PeakOperationReadException(
        'Unable to load peak operation data.',
      );
    }
  }
}

class SupabasePeakOperationDataSource implements PeakOperationDataSource {
  SupabasePeakOperationDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<List<PeakOperationRoute>> fetchRoutes() async {
    try {
      final rows = await _client
          .from('gtfs_routes')
          .select('route_id, route_short_name, route_long_name')
          .order('route_short_name')
          .order('route_long_name');
      return rows
          .map(
            (row) => PeakOperationRoute(
              routeId: row['route_id'] as String,
              shortName: row['route_short_name'] as String?,
              longName: row['route_long_name'] as String?,
            ),
          )
          .toList(growable: false);
    } on Object {
      throw const PeakOperationReadException('Unable to load routes.');
    }
  }

  @override
  Future<List<PeakOperationObservation>> fetchObservations({
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required String? routeId,
    required int offset,
    required int limit,
  }) async {
    try {
      var query = _client
          .from('vehicle_positions')
          .select('route_id, trip_id, vehicle_id, recorded_at')
          .gte('recorded_at', startUtc.toUtc().toIso8601String())
          .lt('recorded_at', endExclusiveUtc.toUtc().toIso8601String());
      if (routeId != null) query = query.eq('route_id', routeId);
      final rows = await query
          .order('recorded_at')
          .range(offset, offset + limit - 1);
      return rows
          .map(
            (row) => PeakOperationObservation(
              routeId: row['route_id'] as String,
              tripId: row['trip_id'] as String,
              vehicleId: row['vehicle_id'] as String,
              recordedAt: DateTime.parse(row['recorded_at'] as String).toUtc(),
            ),
          )
          .toList(growable: false);
    } on Object {
      throw const PeakOperationReadException(
        'Unable to load historical observations.',
      );
    }
  }
}

class PeakOperationReadException implements Exception {
  const PeakOperationReadException(this.message);
  final String message;
  @override
  String toString() => message;
}
