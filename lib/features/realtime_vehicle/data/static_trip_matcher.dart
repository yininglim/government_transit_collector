import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class StaticTripMatcher {
  Future<Set<String>> findKnownTripIds(Iterable<String> realtimeTripIds);
}

abstract interface class StaticTripDataSource {
  Future<Set<String>> findKnownTripIds(List<String> tripIds);
}

class SupabaseStaticTripMatcher implements StaticTripMatcher {
  SupabaseStaticTripMatcher({
    SupabaseClient? client,
    StaticTripDataSource? dataSource,
    this.batchSize = 200,
  }) : _dataSource =
           dataSource ??
           SupabaseStaticTripDataSource(client ?? Supabase.instance.client);

  final StaticTripDataSource _dataSource;
  final int batchSize;

  @override
  Future<Set<String>> findKnownTripIds(Iterable<String> realtimeTripIds) async {
    final distinctIds = realtimeTripIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (distinctIds.isEmpty) return {};

    final matches = <String>{};
    try {
      for (var start = 0; start < distinctIds.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, distinctIds.length);
        final batch = distinctIds.sublist(start, end);
        matches.addAll(await _dataSource.findKnownTripIds(batch));
      }
      return matches;
    } on Object {
      throw const StaticTripMatchException(
        'GTFS Static trip matching is temporarily unavailable.',
      );
    }
  }
}

class SupabaseStaticTripDataSource implements StaticTripDataSource {
  SupabaseStaticTripDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Set<String>> findKnownTripIds(List<String> tripIds) async {
    final rows = await _client
        .from('gtfs_trips')
        .select('trip_id')
        .inFilter('trip_id', tripIds);
    return rows.map((row) => row['trip_id'] as String).toSet();
  }
}

class StaticTripMatchException implements Exception {
  const StaticTripMatchException(this.message);
  final String message;

  @override
  String toString() => message;
}
