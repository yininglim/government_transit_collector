import 'package:supabase_flutter/supabase_flutter.dart';

class DepartureStop {
  const DepartureStop({required this.id, required this.name});

  final String id;
  final String name;
}

abstract interface class DepartureStopRepository {
  Future<List<DepartureStop>> searchStops(String query);
}

class SupabaseDepartureStopRepository implements DepartureStopRepository {
  SupabaseDepartureStopRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const int resultLimit = 50;

  final SupabaseClient _client;
  final Map<String, List<DepartureStop>> _cache = {};

  @override
  Future<List<DepartureStop>> searchStops(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    final cached = _cache[normalizedQuery];
    if (cached != null) return cached;

    try {
      var request = _client.from('gtfs_stops').select('stop_id, stop_name');
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
