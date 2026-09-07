import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';

class SavedJourney {
  const SavedJourney({
    required this.id,
    required this.name,
    required this.origin,
    required this.destination,
  });
  final String id;
  final String name;
  final DepartureStop? origin;
  final DepartureStop? destination;
  bool get usable =>
      origin != null && destination != null && origin!.id != destination!.id;
}

abstract interface class SavedJourneyRepository {
  Future<void> save(
    String name,
    DepartureStop origin,
    DepartureStop destination,
  );
  Future<List<SavedJourney>> load();
  Future<void> delete(String id);
}

class SupabaseSavedJourneyRepository implements SavedJourneyRepository {
  SupabaseSavedJourneyRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  String get _owner =>
      _client.auth.currentUser?.id ??
      (throw const SavedJourneyException('Please sign in again.'));
  @override
  Future<void> save(
    String name,
    DepartureStop origin,
    DepartureStop destination,
  ) async {
    final owner = _owner;
    if (name.trim().isEmpty ||
        name.trim().length > 80 ||
        origin.id == destination.id) {
      throw const SavedJourneyException(
        'Enter a journey name (1–80 characters) and two different stops.',
      );
    }
    try {
      await _client.from('journey_searches').insert({
        'user_id': owner,
        'origin_stop_id': origin.id,
        'origin_text': origin.name,
        'destination_stop_id': destination.id,
        'destination_text': destination.name,
        'requested_departure_at': DateTime.now().toUtc().toIso8601String(),
        'is_saved': true,
        'saved_name': name.trim(),
      });
    } on Object {
      throw const SavedJourneyException(
        'Unable to save journey. Please try again.',
      );
    }
  }

  @override
  Future<List<SavedJourney>> load() async {
    final owner = _owner;
    try {
      final result = <SavedJourney>[];
      for (var offset = 0; ; offset += 500) {
        final rows = await _client
            .from('journey_searches')
            .select(
              'search_id, saved_name, origin:gtfs_stops!origin_stop_id(stop_id, stop_name), destination:gtfs_stops!destination_stop_id(stop_id, stop_name)',
            )
            .eq('user_id', owner)
            .eq('is_saved', true)
            .order('created_at', ascending: false)
            .order('search_id')
            .range(offset, offset + 499);
        DepartureStop? stop(dynamic row) =>
            row is Map && row['stop_id'] is String && row['stop_name'] is String
            ? DepartureStop(
                id: row['stop_id'] as String,
                name: row['stop_name'] as String,
              )
            : null;
        result.addAll(
          rows.map(
            (row) => SavedJourney(
              id: row['search_id'] as String,
              name: row['saved_name'] as String? ?? 'Saved journey',
              origin: stop(row['origin']),
              destination: stop(row['destination']),
            ),
          ),
        );
        if (rows.length < 500) break;
      }
      if (_owner != owner) {
        throw const SavedJourneyException(
          'Account changed. Please reopen your profile.',
        );
      }
      return result;
    } on SavedJourneyException {
      rethrow;
    } on Object {
      throw const SavedJourneyException(
        'Unable to load saved journeys. Please try again.',
      );
    }
  }

  @override
  Future<void> delete(String id) async {
    final owner = _owner;
    try {
      await _client
          .from('journey_searches')
          .delete()
          .eq('search_id', id)
          .eq('user_id', owner)
          .eq('is_saved', true);
    } on Object {
      throw const SavedJourneyException(
        'Unable to delete journey. Please try again.',
      );
    }
  }
}

class SavedJourneyException implements Exception {
  const SavedJourneyException(this.message);
  final String message;
  @override
  String toString() => message;
}
