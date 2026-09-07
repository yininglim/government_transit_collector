import 'package:supabase_flutter/supabase_flutter.dart';

class DepartureStop {
  const DepartureStop({required this.id, required this.name});

  final String id;
  final String name;
}

abstract interface class DepartureStopRepository {
  Future<List<DepartureStop>> searchStops(String query);
  Future<DepartureStop?> getStopById(String id);
}

typedef DepartureStopQuery =
    Future<List<DepartureStop>> Function(String normalizedQuery, int limit);

class SupabaseDepartureStopRepository implements DepartureStopRepository {
  factory SupabaseDepartureStopRepository({
    SupabaseClient? client,
    DepartureStopQuery? query,
  }) => SupabaseDepartureStopRepository._(client, query);

  SupabaseDepartureStopRepository._(this._client, this._query);

  static const int resultLimit = 50;

  final SupabaseClient? _client;
  final DepartureStopQuery? _query;
  final Map<String, List<DepartureStop>> _cache = {};

  @override
  Future<List<DepartureStop>> searchStops(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    final cached = _cache[normalizedQuery];
    if (cached != null) return cached;

    try {
      final injectedQuery = _query;
      if (injectedQuery != null) {
        final stops = await injectedQuery(normalizedQuery, resultLimit);
        _cache[normalizedQuery] = stops;
        return stops;
      }
      var request = (_client ?? Supabase.instance.client)
          .from('gtfs_stops')
          .select('stop_id, stop_name');
      if (normalizedQuery.isNotEmpty) {
        request = request.ilike(
          'stop_name',
          '%${_escapeLikePattern(normalizedQuery)}%',
        );
      }
      final data = await request.order('stop_name').limit(resultLimit);
      final stops = data
          .map(
            (row) => DepartureStop(
              id: row['stop_id'] as String,
              name: row['stop_name'] as String,
            ),
          )
          .toList(growable: false);
      _cache[normalizedQuery] = stops;
      return stops;
    } on PostgrestException catch (error) {
      throw DepartureStopReadException(
        error.message.isEmpty ? 'Unable to load stops.' : error.message,
      );
    } on Object {
      throw const DepartureStopReadException('Unable to load stops.');
    }
  }

  @override
  Future<DepartureStop?> getStopById(String id) async {
    if (id.trim().isEmpty) return null;
    try {
      final row = await (_client ?? Supabase.instance.client)
          .from('gtfs_stops')
          .select('stop_id, stop_name')
          .eq('stop_id', id)
          .maybeSingle();
      return row == null
          ? null
          : DepartureStop(
              id: row['stop_id'] as String,
              name: row['stop_name'] as String,
            );
    } on Object {
      throw const DepartureStopReadException(
        'Unable to load the previous stops. Please try again.',
      );
    }
  }

  String _escapeLikePattern(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}

class DepartureStopReadException implements Exception {
  const DepartureStopReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
