import 'package:supabase_flutter/supabase_flutter.dart';

class FeedbackRoute {
  const FeedbackRoute({
    required this.id,
    required this.shortName,
    required this.longName,
  });

  final String id;
  final String? shortName;
  final String? longName;

  String get displayName {
    final short =
    shortName?.trim();

    final long =
    longName?.trim();

    if (short != null &&
        short.isNotEmpty &&
        long != null &&
        long.isNotEmpty) {
      return '$short - $long';
    }

    if (short != null &&
        short.isNotEmpty) {
      return short;
    }

    if (long != null &&
        long.isNotEmpty) {
      return long;
    }

    return id;
  }
}

class FeedbackStop {
  const FeedbackStop({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

abstract interface class
FeedbackReferenceRepository {
  Future<List<FeedbackRoute>>
  searchRoutes(
      String query,
      );

  Future<List<FeedbackStop>>
  searchStops({
    required String routeId,
    required String query,
    String? tripId,
  });

  Future<bool> stopBelongsToSelection({
    required String routeId,
    required String stopId,
    String? tripId,
  });
}

class SupabaseFeedbackReferenceRepository
    implements
        FeedbackReferenceRepository {
  SupabaseFeedbackReferenceRepository({
    SupabaseClient? client,
  }) : _client =
      client ??
          Supabase.instance.client;

  static const int resultLimit = 50;

  static const int _batchSize = 100;

  final SupabaseClient _client;

  @override
  Future<List<FeedbackRoute>>
  searchRoutes(
      String query,
      ) async {
    final normalized =
    query.trim();

    if (normalized.isEmpty) {
      return const [];
    }

    try {
      final safe =
      _escapeLikePattern(
        normalized,
      );

      final data = await _client
          .from('gtfs_routes')
          .select(
        'route_id, route_short_name, route_long_name',
      )
          .or(
        'route_short_name.ilike.%$safe%,route_long_name.ilike.%$safe%,route_id.ilike.%$safe%',
      )
          .order(
        'route_short_name',
      )
          .limit(
        resultLimit,
      );

      return data
          .map(
            (row) => FeedbackRoute(
          id:
          row['route_id']
          as String,
          shortName:
          row['route_short_name']
          as String?,
          longName:
          row['route_long_name']
          as String?,
        ),
      )
          .toList(
        growable: false,
      );
    } on PostgrestException catch (error) {
      throw FeedbackReferenceException(
        error.message.isEmpty
            ? 'Unable to search routes.'
            : error.message,
      );
    } on Object {
      throw const FeedbackReferenceException(
        'Unable to search routes.',
      );
    }
  }

  @override
  Future<List<FeedbackStop>>
  searchStops({
    required String routeId,
    required String query,
    String? tripId,
  }) async {
    final normalized =
    query.trim();

    if (normalized.isEmpty) {
      return const [];
    }

    try {
      final validTripIds =
      tripId != null
          ? [tripId]
          : await _loadTripIdsForRoute(
        routeId,
      );

      if (validTripIds.isEmpty) {
        return const [];
      }

      final stopIds =
      await _loadStopIdsForTrips(
        validTripIds,
      );

      if (stopIds.isEmpty) {
        return const [];
      }

      final safe =
      _escapeLikePattern(
        normalized,
      );

      final results =
      <FeedbackStop>[];

      final stopIdList =
      stopIds.toList();

      for (
      var start = 0;
      start < stopIdList.length;
      start += _batchSize
      ) {
        final end =
        (start + _batchSize)
            .clamp(
          0,
          stopIdList.length,
        );

        final batch =
        stopIdList.sublist(
          start,
          end,
        );

        final data = await _client
            .from('gtfs_stops')
            .select(
          'stop_id, stop_name',
        )
            .inFilter(
          'stop_id',
          batch,
        )
            .ilike(
          'stop_name',
          '%$safe%',
        )
            .order(
          'stop_name',
        )
            .limit(
          resultLimit,
        );

        results.addAll(
          data.map(
                (row) => FeedbackStop(
              id:
              row['stop_id']
              as String,
              name:
              row['stop_name']
              as String,
            ),
          ),
        );

        if (results.length >=
            resultLimit) {
          break;
        }
      }

      final unique =
      <String, FeedbackStop>{};

      for (final stop in results) {
        unique[stop.id] = stop;
      }

      final sorted =
      unique.values.toList();

      sorted.sort(
            (left, right) =>
            left.name
                .toLowerCase()
                .compareTo(
              right.name
                  .toLowerCase(),
            ),
      );

      return sorted
          .take(
        resultLimit,
      )
          .toList(
        growable: false,
      );
    } on FeedbackReferenceException {
      rethrow;
    } on PostgrestException catch (error) {
      throw FeedbackReferenceException(
        error.message.isEmpty
            ? 'Unable to search stops.'
            : error.message,
      );
    } on Object {
      throw const FeedbackReferenceException(
        'Unable to search stops.',
      );
    }
  }

  @override
  Future<bool> stopBelongsToSelection({
    required String routeId,
    required String stopId,
    String? tripId,
  }) async {
    try {
      if (tripId != null) {
        final tripRows = await _client
            .from('gtfs_trips')
            .select(
          'trip_id',
        )
            .eq(
          'trip_id',
          tripId,
        )
            .eq(
          'route_id',
          routeId,
        )
            .limit(1);

        if (tripRows.isEmpty) {
          return false;
        }

        final stopRows = await _client
            .from('gtfs_stop_times')
            .select(
          'trip_id',
        )
            .eq(
          'trip_id',
          tripId,
        )
            .eq(
          'stop_id',
          stopId,
        )
            .limit(1);

        return stopRows.isNotEmpty;
      }

      final tripIds =
      await _loadTripIdsForRoute(
        routeId,
      );

      if (tripIds.isEmpty) {
        return false;
      }

      for (
      var start = 0;
      start < tripIds.length;
      start += _batchSize
      ) {
        final end =
        (start + _batchSize)
            .clamp(
          0,
          tripIds.length,
        );

        final batch =
        tripIds.sublist(
          start,
          end,
        );

        final data = await _client
            .from('gtfs_stop_times')
            .select(
          'stop_id',
        )
            .eq(
          'stop_id',
          stopId,
        )
            .inFilter(
          'trip_id',
          batch,
        )
            .limit(1);

        if (data.isNotEmpty) {
          return true;
        }
      }

      return false;
    } on PostgrestException catch (error) {
      throw FeedbackReferenceException(
        error.message.isEmpty
            ? 'Unable to validate the selected stop.'
            : error.message,
      );
    } on Object {
      throw const FeedbackReferenceException(
        'Unable to validate the selected stop.',
      );
    }
  }

  Future<List<String>>
  _loadTripIdsForRoute(
      String routeId,
      ) async {
    final data = await _client
        .from('gtfs_trips')
        .select(
      'trip_id',
    )
        .eq(
      'route_id',
      routeId,
    );

    return data
        .map(
          (row) =>
      row['trip_id']
      as String,
    )
        .toList(
      growable: false,
    );
  }

  Future<Set<String>>
  _loadStopIdsForTrips(
      List<String> tripIds,
      ) async {
    final stopIds =
    <String>{};

    for (
    var start = 0;
    start < tripIds.length;
    start += _batchSize
    ) {
      final end =
      (start + _batchSize)
          .clamp(
        0,
        tripIds.length,
      );

      final batch =
      tripIds.sublist(
        start,
        end,
      );

      var rangeStart = 0;

      while (true) {
        final data = await _client
            .from('gtfs_stop_times')
            .select(
          'stop_id',
        )
            .inFilter(
          'trip_id',
          batch,
        )
            .range(
          rangeStart,
          rangeStart + 999,
        );

        for (final row in data) {
          stopIds.add(
            row['stop_id']
            as String,
          );
        }

        if (data.length < 1000) {
          break;
        }

        rangeStart += 1000;
      }
    }

    return stopIds;
  }

  String _escapeLikePattern(
      String value,
      ) {
    return value
        .replaceAll(
      r'\',
      r'\\',
    )
        .replaceAll(
      '%',
      r'\%',
    )
        .replaceAll(
      '_',
      r'\_',
    );
  }
}

class FeedbackReferenceException
    implements Exception {
  const FeedbackReferenceException(
      this.message,
      );

  final String message;

  @override
  String toString() => message;
}