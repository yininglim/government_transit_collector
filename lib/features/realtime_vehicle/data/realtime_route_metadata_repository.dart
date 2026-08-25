import 'package:supabase_flutter/supabase_flutter.dart';

class RealtimeRouteMetadata {
  const RealtimeRouteMetadata({
    required this.routeId,
    this.shortName,
    this.longName,
  });

  final String routeId;
  final String? shortName;
  final String? longName;

  String get passengerShortName => _nonBlank(shortName) ?? routeId;
  String? get passengerLongName => _nonBlank(longName);

  static String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed?.isNotEmpty == true ? trimmed : null;
  }
}

abstract interface class RealtimeRouteMetadataRepository {
  Future<Map<String, RealtimeRouteMetadata>> loadRoutes(
    Iterable<String> routeIds,
  );
}

class SupabaseRealtimeRouteMetadataRepository
    implements RealtimeRouteMetadataRepository {
  SupabaseRealtimeRouteMetadataRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<Map<String, RealtimeRouteMetadata>> loadRoutes(
    Iterable<String> routeIds,
  ) async {
    final ids = routeIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const {};
    final rows = await _client
        .from('gtfs_routes')
        .select('route_id, route_short_name, route_long_name')
        .inFilter('route_id', ids);
    return {
      for (final row in rows)
        row['route_id'] as String: RealtimeRouteMetadata(
          routeId: row['route_id'] as String,
          shortName: row['route_short_name'] as String?,
          longName: row['route_long_name'] as String?,
        ),
    };
  }
}
