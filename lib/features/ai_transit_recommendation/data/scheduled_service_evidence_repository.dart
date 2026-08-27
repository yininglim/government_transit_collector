import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as timezone;

class ScheduledTripMetadata {
  const ScheduledTripMetadata({
    required this.tripId,
    required this.serviceId,
    required this.directionId,
  });

  final String tripId;
  final String serviceId;
  final int? directionId;
}

abstract interface class ScheduledServiceDataSource {
  Future<List<ScheduledTripMetadata>> loadTripMetadata(List<String> tripIds);
  Future<List<GtfsServiceCalendar>> loadCalendars(List<String> serviceIds);
}

abstract interface class ScheduledServiceEvidenceRepository {
  Future<ScheduledServiceEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  });
}

class DefaultScheduledServiceEvidenceRepository
    implements ScheduledServiceEvidenceRepository {
  DefaultScheduledServiceEvidenceRepository({
    RouteNetworkEvidenceRepository? routeNetworkRepository,
    ScheduledServiceDataSource? dataSource,
  }) : _routeNetworkRepository =
           routeNetworkRepository ?? DefaultRouteNetworkEvidenceRepository(),
       _dataSource = dataSource ?? SupabaseScheduledServiceDataSource();

  final RouteNetworkEvidenceRepository _routeNetworkRepository;
  final ScheduledServiceDataSource _dataSource;

  @override
  Future<ScheduledServiceEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    if (!endExclusiveUtc.isAfter(startUtc)) {
      throw const ScheduledServiceEvidenceReadException(
        'The analysis period is invalid.',
      );
    }
    try {
      final network = await _routeNetworkRepository.loadRoute(routeId);
      final tripIds = network.trips
          .map((trip) => trip.tripId)
          .toList(growable: false);
      final metadata = tripIds.isEmpty
          ? const <ScheduledTripMetadata>[]
          : await _dataSource.loadTripMetadata(tripIds);
      final metadataByTrip = {for (final trip in metadata) trip.tripId: trip};
      final serviceIds = metadata
          .map((trip) => trip.serviceId)
          .toSet()
          .toList(growable: false);
      final calendars = serviceIds.isEmpty
          ? const <GtfsServiceCalendar>[]
          : await _dataSource.loadCalendars(serviceIds);
      final calendarsByService = {
        for (final calendar in calendars) calendar.serviceId: calendar,
      };
      final incompleteTripIds = <String>{};
      final departuresByDirection = <int?, List<ScheduledDepartureEvidence>>{};
      var hasCompleteDirectionData = true;
      for (final trip in network.trips) {
        final tripMetadata = metadataByTrip[trip.tripId];
        if (tripMetadata == null) {
          incompleteTripIds.add(trip.tripId);
          continue;
        }
        if (tripMetadata.directionId == null) hasCompleteDirectionData = false;
        final calendar = calendarsByService[tripMetadata.serviceId];
        final reference = _departureReference(trip);
        if (calendar == null || reference == null) {
          incompleteTripIds.add(trip.tripId);
          continue;
        }
        final departureSeconds =
            reference.scheduledDepartureSeconds ??
            reference.scheduledArrivalSeconds;
        if (departureSeconds == null) {
          incompleteTripIds.add(trip.tripId);
          continue;
        }
        for (final serviceDate in _serviceDates(
          startUtc,
          endExclusiveUtc,
          departureSeconds,
        )) {
          if (!calendar.operatesOn(serviceDate)) continue;
          final scheduledAt = timezone.TZDateTime(
            transitServiceLocation,
            serviceDate.year,
            serviceDate.month,
            serviceDate.day,
          ).add(Duration(seconds: departureSeconds));
          final instant = scheduledAt.toUtc();
          if (instant.isBefore(startUtc) ||
              !instant.isBefore(endExclusiveUtc)) {
            continue;
          }
          departuresByDirection
              .putIfAbsent(tripMetadata.directionId, () => [])
              .add(
                ScheduledDepartureEvidence(
                  tripId: trip.tripId,
                  serviceDate: serviceDate,
                  departureSeconds: departureSeconds,
                  scheduledAt: instant,
                  referenceStopId: reference.stopId,
                  referenceStopSequence: reference.stopSequence,
                ),
              );
        }
      }
      final directionGroups =
          departuresByDirection.entries
              .map((entry) => _directionEvidence(entry.key, entry.value))
              .toList()
            ..sort((left, right) {
              final leftId = left.directionId;
              final rightId = right.directionId;
              if (leftId == null) return rightId == null ? 0 : 1;
              if (rightId == null) return -1;
              return leftId.compareTo(rightId);
            });
      final departureCount = directionGroups.fold<int>(
        0,
        (total, group) => total + group.departures.length,
      );
      final headwayCount = directionGroups.fold<int>(
        0,
        (total, group) => total + group.headwaysSeconds.length,
      );
      final status = incompleteTripIds.isNotEmpty
          ? ScheduledServiceEvidenceStatus.incomplete
          : departureCount == 0
          ? ScheduledServiceEvidenceStatus.noDepartures
          : headwayCount == 0
          ? ScheduledServiceEvidenceStatus.insufficientForHeadway
          : ScheduledServiceEvidenceStatus.available;
      return ScheduledServiceEvidence(
        route: network.route,
        periodStart: startUtc,
        periodEnd: endExclusiveUtc,
        directionGroups: directionGroups,
        incompleteTripIds: incompleteTripIds.toList()..sort(),
        status: status,
        hasCompleteDirectionData: hasCompleteDirectionData,
      );
    } on ScheduledServiceEvidenceReadException {
      rethrow;
    } on Object {
      throw const ScheduledServiceEvidenceReadException(
        'Unable to load scheduled service evidence.',
      );
    }
  }

  AiRouteStopEvidence? _departureReference(AiRouteTripEvidence trip) {
    if (trip.stops.isEmpty) return null;
    return trip.stops.reduce(
      (current, stop) =>
          stop.stopSequence < current.stopSequence ? stop : current,
    );
  }

  Iterable<DateTime> _serviceDates(
    DateTime startUtc,
    DateTime endExclusiveUtc,
    int departureSeconds,
  ) sync* {
    final localStart = transitServiceDateTime(startUtc);
    final localEnd = transitServiceDateTime(
      endExclusiveUtc.subtract(const Duration(microseconds: 1)),
    );
    final precedingDays = departureSeconds ~/ Duration.secondsPerDay;
    var date = DateTime(
      localStart.year,
      localStart.month,
      localStart.day - precedingDays,
    );
    final last = DateTime(localEnd.year, localEnd.month, localEnd.day);
    while (!date.isAfter(last)) {
      yield date;
      date = DateTime(date.year, date.month, date.day + 1);
    }
  }

  ScheduledDirectionEvidence _directionEvidence(
    int? directionId,
    List<ScheduledDepartureEvidence> source,
  ) {
    final departures = [...source]
      ..sort((left, right) => left.scheduledAt.compareTo(right.scheduledAt));
    final byServiceDate = <DateTime, List<ScheduledDepartureEvidence>>{};
    for (final departure in departures) {
      byServiceDate.putIfAbsent(departure.serviceDate, () => []).add(departure);
    }
    final headways = <int>[];
    final bucketCounts = <(DateTime, int), int>{};
    for (final entry in byServiceDate.entries) {
      final daily = entry.value
        ..sort(
          (left, right) =>
              left.departureSeconds.compareTo(right.departureSeconds),
        );
      for (var index = 1; index < daily.length; index++) {
        headways.add(
          daily[index].departureSeconds - daily[index - 1].departureSeconds,
        );
      }
      for (final departure in daily) {
        final startMinute = departure.departureSeconds ~/ 3600 * 60;
        final key = (entry.key, startMinute);
        bucketCounts[key] = (bucketCounts[key] ?? 0) + 1;
      }
    }
    headways.sort();
    final average = headways.isEmpty
        ? null
        : headways.fold<int>(0, (sum, value) => sum + value) / headways.length;
    final median = headways.isEmpty
        ? null
        : headways.length.isOdd
        ? headways[headways.length ~/ 2].toDouble()
        : (headways[headways.length ~/ 2 - 1] +
                  headways[headways.length ~/ 2]) /
              2;
    final buckets =
        bucketCounts.entries
            .map(
              (entry) => ScheduledServiceHourBucket(
                serviceDate: entry.key.$1,
                startMinute: entry.key.$2,
                scheduledDepartureCount: entry.value,
                scheduledTripsPerHour: entry.value.toDouble(),
              ),
            )
            .toList()
          ..sort((left, right) {
            final byDate = left.serviceDate.compareTo(right.serviceDate);
            return byDate != 0
                ? byDate
                : left.startMinute.compareTo(right.startMinute);
          });
    return ScheduledDirectionEvidence(
      directionId: directionId,
      departures: departures,
      headwaysSeconds: headways,
      hourlyBuckets: buckets,
      averageHeadwaySeconds: average,
      medianHeadwaySeconds: median,
      minimumHeadwaySeconds: headways.isEmpty ? null : headways.first,
      maximumHeadwaySeconds: headways.isEmpty ? null : headways.last,
    );
  }
}

class SupabaseScheduledServiceDataSource implements ScheduledServiceDataSource {
  SupabaseScheduledServiceDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const batchSize = 100;

  final SupabaseClient _client;

  @override
  Future<List<ScheduledTripMetadata>> loadTripMetadata(
    List<String> tripIds,
  ) async {
    final result = <ScheduledTripMetadata>[];
    for (final batch in _batches(tripIds)) {
      final rows = await _client
          .from('gtfs_trips')
          .select('trip_id, service_id, direction_id')
          .inFilter('trip_id', batch);
      result.addAll(
        rows.map(
          (row) => ScheduledTripMetadata(
            tripId: row['trip_id'] as String,
            serviceId: row['service_id'] as String,
            directionId: row['direction_id'] as int?,
          ),
        ),
      );
    }
    return result;
  }

  @override
  Future<List<GtfsServiceCalendar>> loadCalendars(
    List<String> serviceIds,
  ) async {
    final result = <GtfsServiceCalendar>[];
    for (final batch in _batches(serviceIds)) {
      final rows = await _client
          .from('gtfs_calendar')
          .select(
            'service_id, start_date, end_date, monday, tuesday, '
            'wednesday, thursday, friday, saturday, sunday',
          )
          .inFilter('service_id', batch);
      result.addAll(
        rows.map(
          (row) => GtfsServiceCalendar(
            serviceId: row['service_id'] as String,
            startDate: DateTime.parse(row['start_date'] as String),
            endDate: DateTime.parse(row['end_date'] as String),
            weekdays: [
              row['monday'] as bool,
              row['tuesday'] as bool,
              row['wednesday'] as bool,
              row['thursday'] as bool,
              row['friday'] as bool,
              row['saturday'] as bool,
              row['sunday'] as bool,
            ],
          ),
        ),
      );
    }
    return result;
  }

  Iterable<List<String>> _batches(List<String> values) sync* {
    for (var start = 0; start < values.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, values.length);
      yield values.sublist(start, end);
    }
  }
}

class ScheduledServiceEvidenceReadException implements Exception {
  const ScheduledServiceEvidenceReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
