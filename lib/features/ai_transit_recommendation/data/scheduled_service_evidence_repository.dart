import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';
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

class ScheduledStopTimeRecord {
  const ScheduledStopTimeRecord({
    required this.tripId,
    required this.stopId,
    required this.stopSequence,
    required this.arrivalSeconds,
    required this.departureSeconds,
  });

  final String tripId;
  final String stopId;
  final int stopSequence;
  final int? arrivalSeconds;
  final int? departureSeconds;
}

abstract interface class ScheduledServiceDataSource {
  Future<List<ScheduledTripMetadata>> loadTripMetadata(List<String> tripIds);
  Future<List<GtfsServiceCalendar>> loadCalendars(List<String> serviceIds);
}

abstract interface class LeanScheduledServiceDataSource {
  Future<List<ScheduledTripMetadata>> fetchRouteTripMetadata({
    required String routeId,
    required int offset,
    required int limit,
  });

  Future<List<ScheduledStopTimeRecord>> fetchStopTimes({
    required List<String> tripIds,
    required int offset,
    required int limit,
  });
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
    bool useLeanRouteLoader = false,
    RoutePerformanceRepository? routeRepository,
    LeanScheduledServiceDataSource? leanDataSource,
  }) : _routeNetworkRepository = useLeanRouteLoader
           ? routeNetworkRepository
           : routeNetworkRepository ?? DefaultRouteNetworkEvidenceRepository(),
       _leanRouteLoader = useLeanRouteLoader
           ? _LeanScheduledRouteLoader(
               routeRepository: routeRepository,
               dataSource: leanDataSource,
             )
           : null,
       _dataSource = dataSource ?? SupabaseScheduledServiceDataSource();

  final RouteNetworkEvidenceRepository? _routeNetworkRepository;
  final _LeanScheduledRouteLoader? _leanRouteLoader;
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
      final routeData = _leanRouteLoader != null
          ? await _leanRouteLoader.loadRoute(routeId)
          : _ScheduledRouteInput.fromNetwork(
              await _routeNetworkRepository!.loadRoute(routeId),
            );
      final tripIds = routeData.trips
          .map((trip) => trip.tripId)
          .toList(growable: false);
      final metadata =
          routeData.metadata ??
          (tripIds.isEmpty
              ? const <ScheduledTripMetadata>[]
              : await _dataSource.loadTripMetadata(tripIds));
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
      for (final trip in routeData.trips) {
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
        route: routeData.route,
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

  AiRouteStopEvidence? _departureReference(_ScheduledTripInput trip) {
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

class _ScheduledRouteInput {
  const _ScheduledRouteInput({
    required this.route,
    required this.trips,
    this.metadata,
  });

  factory _ScheduledRouteInput.fromNetwork(AiRouteNetworkEvidence network) {
    return _ScheduledRouteInput(
      route: network.route,
      trips: [
        for (final trip in network.trips)
          _ScheduledTripInput(tripId: trip.tripId, stops: trip.stops),
      ],
    );
  }

  final RoutePerformanceRoute route;
  final List<_ScheduledTripInput> trips;
  final List<ScheduledTripMetadata>? metadata;
}

class _ScheduledTripInput {
  const _ScheduledTripInput({required this.tripId, required this.stops});

  final String tripId;
  final List<AiRouteStopEvidence> stops;
}

class _LeanScheduledRouteLoader {
  _LeanScheduledRouteLoader({
    RoutePerformanceRepository? routeRepository,
    LeanScheduledServiceDataSource? dataSource,
  }) : _routeRepository =
           routeRepository ?? DefaultRoutePerformanceRepository(),
       _dataSource = dataSource ?? SupabaseLeanScheduledServiceDataSource();

  static const _pageSize = 1000;
  static const _tripBatchSize = 100;

  final RoutePerformanceRepository _routeRepository;
  final LeanScheduledServiceDataSource _dataSource;
  Future<List<RoutePerformanceRoute>>? _routesFuture;

  Future<_ScheduledRouteInput> loadRoute(String routeId) async {
    final results = await Future.wait([
      _loadRoutes(),
      _loadTripMetadata(routeId),
    ]);
    final routes = results[0] as List<RoutePerformanceRoute>;
    final route = routes.where((item) => item.routeId == routeId).firstOrNull;
    if (route == null) {
      throw const RouteNetworkEvidenceReadException(
        'The selected route is not available.',
      );
    }
    final metadata = results[1] as List<ScheduledTripMetadata>;
    final stopTimesByTrip = await _loadStopTimes(
      metadata.map((trip) => trip.tripId).toList(growable: false),
    );
    return _ScheduledRouteInput(
      route: route,
      metadata: metadata,
      trips: [
        for (final trip in metadata)
          _ScheduledTripInput(
            tripId: trip.tripId,
            stops: [
              for (final stopTime in stopTimesByTrip[trip.tripId] ?? const [])
                AiRouteStopEvidence(
                  stopId: stopTime.stopId,
                  stopName: null,
                  stopSequence: stopTime.stopSequence,
                  coordinate: null,
                  scheduledArrivalSeconds: stopTime.arrivalSeconds,
                  scheduledDepartureSeconds: stopTime.departureSeconds,
                ),
            ],
          ),
      ],
    );
  }

  Future<List<RoutePerformanceRoute>> _loadRoutes() {
    final existing = _routesFuture;
    if (existing != null) return existing;
    final future = _routeRepository.loadRoutes();
    _routesFuture = future;
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (identical(_routesFuture, future)) _routesFuture = null;
      },
    );
    return future;
  }

  Future<List<ScheduledTripMetadata>> _loadTripMetadata(String routeId) async {
    final trips = <ScheduledTripMetadata>[];
    for (var offset = 0; ; offset += _pageSize) {
      final page = await _dataSource.fetchRouteTripMetadata(
        routeId: routeId,
        offset: offset,
        limit: _pageSize,
      );
      trips.addAll(page);
      if (page.length < _pageSize) return trips;
    }
  }

  Future<Map<String, List<ScheduledStopTimeRecord>>> _loadStopTimes(
    List<String> tripIds,
  ) async {
    final grouped = <String, List<ScheduledStopTimeRecord>>{};
    for (var start = 0; start < tripIds.length; start += _tripBatchSize) {
      final end = (start + _tripBatchSize).clamp(0, tripIds.length);
      final batch = tripIds.sublist(start, end);
      for (var offset = 0; ; offset += _pageSize) {
        final page = await _dataSource.fetchStopTimes(
          tripIds: batch,
          offset: offset,
          limit: _pageSize,
        );
        for (final row in page) {
          grouped.putIfAbsent(row.tripId, () => []).add(row);
        }
        if (page.length < _pageSize) break;
      }
    }
    for (final rows in grouped.values) {
      rows.sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    }
    return grouped;
  }
}

class SupabaseLeanScheduledServiceDataSource
    implements LeanScheduledServiceDataSource {
  SupabaseLeanScheduledServiceDataSource({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<ScheduledTripMetadata>> fetchRouteTripMetadata({
    required String routeId,
    required int offset,
    required int limit,
  }) async {
    final rows = await _client
        .from('gtfs_trips')
        .select('trip_id, service_id, direction_id')
        .eq('route_id', routeId)
        .order('trip_id')
        .range(offset, offset + limit - 1);
    return rows
        .map(
          (row) => ScheduledTripMetadata(
            tripId: row['trip_id'] as String,
            serviceId: row['service_id'] as String,
            directionId: row['direction_id'] as int?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ScheduledStopTimeRecord>> fetchStopTimes({
    required List<String> tripIds,
    required int offset,
    required int limit,
  }) async {
    if (tripIds.isEmpty) return const [];
    final rows = await _client
        .from('gtfs_stop_times')
        .select(
          'trip_id, stop_id, stop_sequence, arrival_seconds, departure_seconds',
        )
        .inFilter('trip_id', tripIds)
        .order('trip_id')
        .order('stop_sequence')
        .range(offset, offset + limit - 1);
    return rows
        .map(
          (row) => ScheduledStopTimeRecord(
            tripId: row['trip_id'] as String,
            stopId: row['stop_id'] as String,
            stopSequence: (row['stop_sequence'] as num).toInt(),
            arrivalSeconds: (row['arrival_seconds'] as num?)?.toInt(),
            departureSeconds: (row['departure_seconds'] as num?)?.toInt(),
          ),
        )
        .toList(growable: false);
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
