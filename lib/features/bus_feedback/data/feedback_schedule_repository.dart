import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';

import 'feedback_reference_repository.dart';

class FeedbackDeparture {
  const FeedbackDeparture({required this.tripId, required this.seconds});
  final String tripId;
  final int seconds;
}

String feedbackServiceDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String feedbackDepartureLabel(int seconds) {
  final days = seconds ~/ Duration.secondsPerDay;
  final remainder = seconds % 60;
  final clock = formatServiceDaySeconds(seconds);
  final precise = remainder == 0
      ? clock
      : clock.replaceFirst(' ', ':${remainder.toString().padLeft(2, '0')} ');
  return '$precise${days == 0 ? '' : ' (+$days day${days == 1 ? '' : 's'})'}';
}

abstract interface class FeedbackScheduleRepository {
  Future<List<FeedbackStop>> loadRouteStops(String routeId, {String? tripId});
  Future<List<FeedbackDeparture>> loadDepartures({
    required String routeId,
    required String stopId,
    required DateTime serviceDate,
    String? tripId,
  });
}

class SupabaseFeedbackScheduleRepository implements FeedbackScheduleRepository {
  SupabaseFeedbackScheduleRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  static const _pageSize = 500;

  Future<List<Map<String, dynamic>>> _trips(
    String routeId,
    String? tripId,
  ) async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += _pageSize) {
      var query = _client
          .from('gtfs_trips')
          .select(
            'trip_id, source_import_id, calendar:gtfs_calendar(service_id, source_import_id, start_date, end_date, monday, tuesday, wednesday, thursday, friday, saturday, sunday)',
          )
          .eq('route_id', routeId);
      if (tripId != null) query = query.eq('trip_id', tripId);
      final page = await query
          .order('trip_id')
          .range(offset, offset + _pageSize - 1);
      rows.addAll(page);
      if (page.length < _pageSize) return rows;
    }
  }

  Future<List<Map<String, dynamic>>> _times(
    List<Map<String, dynamic>> trips, {
    String? stopId,
  }) async {
    final rows = <Map<String, dynamic>>[];
    for (var start = 0; start < trips.length; start += 100) {
      final batch = trips.sublist(start, (start + 100).clamp(0, trips.length));
      final sources = {
        for (final trip in batch) trip['trip_id']: trip['source_import_id'],
      };
      for (var offset = 0; ; offset += _pageSize) {
        var query = _client
            .from('gtfs_stop_times')
            .select(
              'trip_id, source_import_id, stop_id, stop_sequence, departure_seconds, stop:gtfs_stops(stop_id, stop_name)',
            )
            .inFilter('trip_id', sources.keys.toList());
        if (stopId != null) query = query.eq('stop_id', stopId);
        final page = await query
            .order('trip_id')
            .order('stop_sequence')
            .range(offset, offset + _pageSize - 1);
        rows.addAll(
          page.where(
            (row) =>
                row['source_import_id'] != null &&
                row['source_import_id'] == sources[row['trip_id']],
          ),
        );
        if (page.length < _pageSize) break;
      }
    }
    return rows;
  }

  @override
  Future<List<FeedbackStop>> loadRouteStops(
    String routeId, {
    String? tripId,
  }) async {
    try {
      final trips = await _trips(routeId, tripId);
      final times = await _times(trips);
      times.sort((a, b) {
        final trip = (a['trip_id'] as String).compareTo(b['trip_id'] as String);
        return trip != 0
            ? trip
            : (a['stop_sequence'] as int).compareTo(b['stop_sequence'] as int);
      });
      final unique = <String, FeedbackStop>{};
      for (final row in times) {
        final stop = row['stop'];
        if (stop is Map && stop['stop_name'] is String) {
          final id = row['stop_id'] as String;
          unique.putIfAbsent(
            id,
            () => FeedbackStop(id: id, name: stop['stop_name'] as String),
          );
        }
      }
      return unique.values.toList();
    } on Object {
      throw const FeedbackReferenceException(
        'Unable to load related stops. Please try again.',
      );
    }
  }

  @override
  Future<List<FeedbackDeparture>> loadDepartures({
    required String routeId,
    required String stopId,
    required DateTime serviceDate,
    String? tripId,
  }) async {
    try {
      final trips = await _trips(routeId, tripId);
      final active = <Map<String, dynamic>>[];
      for (final trip in trips) {
        final row = trip['calendar'];
        if (row is! Map<String, dynamic> ||
            trip['source_import_id'] == null ||
            row['source_import_id'] != trip['source_import_id']) {
          continue;
        }
        final calendar = GtfsServiceCalendar(
          serviceId: row['service_id'] as String,
          startDate: DateTime.parse(row['start_date'] as String),
          endDate: DateTime.parse(row['end_date'] as String),
          weekdays: [
            for (final day in [
              'monday',
              'tuesday',
              'wednesday',
              'thursday',
              'friday',
              'saturday',
              'sunday',
            ])
              row[day] as bool,
          ],
        );
        if (calendar.operatesOn(serviceDate)) {
          active.add(trip);
        }
      }
      final times = await _times(active, stopId: stopId);
      final departures = <int, FeedbackDeparture>{};
      for (final row in times) {
        final seconds = row['departure_seconds'] as int;
        departures.putIfAbsent(
          seconds,
          () => FeedbackDeparture(
            tripId: row['trip_id'] as String,
            seconds: seconds,
          ),
        );
      }
      return departures.values.toList()
        ..sort((a, b) => a.seconds.compareTo(b.seconds));
    } on Object {
      throw const FeedbackReferenceException(
        'Unable to load scheduled departures. Please try again.',
      );
    }
  }
}
