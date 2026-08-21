import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/direct_trip_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/transfer_journey_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const int defaultMinimumTransferSeconds = 5 * 60;
const int defaultRecommendationLimit = 5;

int timeOfDayToServiceSeconds(TimeOfDay time) =>
    time.hour * 3600 + time.minute * 60;

String formatServiceDaySeconds(int seconds) {
  final normalizedSeconds = seconds % Duration.secondsPerDay;
  final hour24 = normalizedSeconds ~/ 3600;
  final minute = (normalizedSeconds % 3600) ~/ 60;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $period';
}

String formatDurationMinutes(int seconds) {
  final minutes = (seconds / 60).ceil();
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
}

class GtfsServiceCalendar {
  const GtfsServiceCalendar({
    required this.serviceId,
    required this.startDate,
    required this.endDate,
    required this.weekdays,
  });

  final String serviceId;
  final DateTime startDate;
  final DateTime endDate;
  final List<bool> weekdays;

  bool operatesOn(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !day.isBefore(start) &&
        !day.isAfter(end) &&
        weekdays[day.weekday - 1];
  }
}

class GtfsTripService {
  const GtfsTripService({required this.tripId, required this.serviceId});

  final String tripId;
  final String serviceId;
}

class GtfsStopTimeValue {
  const GtfsStopTimeValue({
    required this.tripId,
    required this.stopId,
    required this.stopSequence,
    required this.arrivalSeconds,
    required this.departureSeconds,
  });

  final String tripId;
  final String stopId;
  final int stopSequence;
  final int arrivalSeconds;
  final int departureSeconds;
}

sealed class JourneyRecommendation {
  const JourneyRecommendation({
    required this.departureSeconds,
    required this.arrivalSeconds,
  });

  final int departureSeconds;
  final int arrivalSeconds;
  int get durationSeconds => arrivalSeconds - departureSeconds;
  int get transferCount;
}

class DirectJourneyRecommendation extends JourneyRecommendation {
  const DirectJourneyRecommendation({
    required this.tripId,
    required this.routeId,
    required this.routeShortName,
    required this.originStopId,
    required this.destinationStopId,
    required this.serviceId,
    required this.originStopSequence,
    required this.destinationStopSequence,
    required super.departureSeconds,
    required super.arrivalSeconds,
  });

  final String tripId;
  final String routeId;
  final String? routeShortName;
  final String originStopId;
  final String destinationStopId;
  final String serviceId;
  final int originStopSequence;
  final int destinationStopSequence;

  @override
  int get transferCount => 0;
}

class TransferJourneyRecommendation extends JourneyRecommendation {
  const TransferJourneyRecommendation({
    required this.firstTripId,
    required this.secondTripId,
    required this.firstRouteId,
    required this.firstRouteShortName,
    required this.secondRouteId,
    required this.secondRouteShortName,
    required this.originStopId,
    required this.transferStopId,
    required this.transferStopName,
    required this.destinationStopId,
    required this.firstServiceId,
    required this.secondServiceId,
    required this.originStopSequence,
    required this.firstTransferStopSequence,
    required this.secondTransferStopSequence,
    required this.destinationStopSequence,
    required this.transferArrivalSeconds,
    required this.secondDepartureSeconds,
    required super.departureSeconds,
    required super.arrivalSeconds,
  });

  final String firstTripId;
  final String secondTripId;
  final String firstRouteId;
  final String? firstRouteShortName;
  final String secondRouteId;
  final String? secondRouteShortName;
  final String originStopId;
  final String transferStopId;
  final String transferStopName;
  final String destinationStopId;
  final String firstServiceId;
  final String secondServiceId;
  final int originStopSequence;
  final int firstTransferStopSequence;
  final int secondTransferStopSequence;
  final int destinationStopSequence;
  final int transferArrivalSeconds;
  final int secondDepartureSeconds;

  int get transferWaitSeconds =>
      secondDepartureSeconds - transferArrivalSeconds;

  @override
  int get transferCount => 1;
}

abstract interface class TimetableRecommendationRepository {
  Future<List<JourneyRecommendation>> findRecommendations({
    required String originStopId,
    required String destinationStopId,
    required DateTime travelDate,
    required int travelTimeSeconds,
    required List<DirectRouteResult> directRoutes,
    required List<OneTransferJourneyResult> transferJourneys,
  });
}

List<JourneyRecommendation> buildTimetableRecommendations({
  required String originStopId,
  required String destinationStopId,
  required DateTime travelDate,
  required int travelTimeSeconds,
  required List<DirectRouteResult> directRoutes,
  required List<OneTransferJourneyResult> transferJourneys,
  required List<GtfsTripService> tripServices,
  required List<GtfsServiceCalendar> calendars,
  required List<GtfsStopTimeValue> stopTimes,
  int minimumTransferSeconds = defaultMinimumTransferSeconds,
  int limit = defaultRecommendationLimit,
}) {
  final serviceByTrip = {
    for (final trip in tripServices) trip.tripId: trip.serviceId,
  };
  final activeServices = calendars
      .where((calendar) => calendar.operatesOn(travelDate))
      .map((calendar) => calendar.serviceId)
      .toSet();
  final timesByTrip = <String, List<GtfsStopTimeValue>>{};
  for (final time in stopTimes) {
    timesByTrip.putIfAbsent(time.tripId, () => []).add(time);
  }
  final recommendations = <JourneyRecommendation>[];

  for (final route in directRoutes) {
    for (final tripId in route.matchingTripIds) {
      final serviceId = serviceByTrip[tripId];
      if (serviceId == null || !activeServices.contains(serviceId)) continue;
      final times = timesByTrip[tripId] ?? const [];
      DirectJourneyRecommendation? best;
      for (final origin in times.where((time) => time.stopId == originStopId)) {
        if (origin.departureSeconds < travelTimeSeconds) continue;
        for (final destination in times.where(
          (time) => time.stopId == destinationStopId,
        )) {
          if (origin.stopSequence >= destination.stopSequence ||
              destination.arrivalSeconds < origin.departureSeconds) {
            continue;
          }
          final candidate = DirectJourneyRecommendation(
            tripId: tripId,
            routeId: route.routeId,
            routeShortName: route.routeShortName,
            originStopId: originStopId,
            destinationStopId: destinationStopId,
            serviceId: serviceId,
            originStopSequence: origin.stopSequence,
            destinationStopSequence: destination.stopSequence,
            departureSeconds: origin.departureSeconds,
            arrivalSeconds: destination.arrivalSeconds,
          );
          if (best == null || candidate.arrivalSeconds < best.arrivalSeconds) {
            best = candidate;
          }
        }
      }
      if (best != null) recommendations.add(best);
    }
  }

  for (final journey in transferJourneys) {
    for (final pair in journey.matchingTripPairs) {
      final firstServiceId = serviceByTrip[pair.firstTripId];
      final secondServiceId = serviceByTrip[pair.secondTripId];
      if (firstServiceId == null ||
          secondServiceId == null ||
          !activeServices.contains(firstServiceId) ||
          !activeServices.contains(secondServiceId)) {
        continue;
      }
      final firstTimes = timesByTrip[pair.firstTripId] ?? const [];
      final secondTimes = timesByTrip[pair.secondTripId] ?? const [];
      TransferJourneyRecommendation? best;
      for (final origin in firstTimes.where(
        (time) => time.stopId == originStopId,
      )) {
        if (origin.departureSeconds < travelTimeSeconds) continue;
        for (final firstTransfer in firstTimes.where(
          (time) => time.stopId == journey.transferStopId,
        )) {
          if (origin.stopSequence >= firstTransfer.stopSequence ||
              firstTransfer.arrivalSeconds < origin.departureSeconds) {
            continue;
          }
          for (final secondTransfer in secondTimes.where(
            (time) => time.stopId == journey.transferStopId,
          )) {
            if (secondTransfer.departureSeconds <
                firstTransfer.arrivalSeconds + minimumTransferSeconds) {
              continue;
            }
            for (final destination in secondTimes.where(
              (time) => time.stopId == destinationStopId,
            )) {
              if (secondTransfer.stopSequence >= destination.stopSequence ||
                  destination.arrivalSeconds <
                      secondTransfer.departureSeconds) {
                continue;
              }
              final candidate = TransferJourneyRecommendation(
                firstTripId: pair.firstTripId,
                secondTripId: pair.secondTripId,
                firstRouteId: journey.firstLeg.routeId,
                firstRouteShortName: journey.firstLeg.routeShortName,
                secondRouteId: journey.secondLeg.routeId,
                secondRouteShortName: journey.secondLeg.routeShortName,
                originStopId: originStopId,
                transferStopId: journey.transferStopId,
                transferStopName: journey.transferStopName,
                destinationStopId: destinationStopId,
                firstServiceId: firstServiceId,
                secondServiceId: secondServiceId,
                originStopSequence: origin.stopSequence,
                firstTransferStopSequence: firstTransfer.stopSequence,
                secondTransferStopSequence: secondTransfer.stopSequence,
                destinationStopSequence: destination.stopSequence,
                departureSeconds: origin.departureSeconds,
                transferArrivalSeconds: firstTransfer.arrivalSeconds,
                secondDepartureSeconds: secondTransfer.departureSeconds,
                arrivalSeconds: destination.arrivalSeconds,
              );
              if (best == null ||
                  candidate.arrivalSeconds < best.arrivalSeconds) {
                best = candidate;
              }
            }
          }
        }
      }
      if (best != null) recommendations.add(best);
    }
  }

  final pruned = pruneEquivalentRecommendations(recommendations);
  pruned.sort((left, right) {
    final byArrival = left.arrivalSeconds.compareTo(right.arrivalSeconds);
    if (byArrival != 0) return byArrival;
    final byTransfers = left.transferCount.compareTo(right.transferCount);
    if (byTransfers != 0) return byTransfers;
    return left.departureSeconds.compareTo(right.departureSeconds);
  });
  return pruned.take(limit).toList(growable: false);
}

List<JourneyRecommendation> pruneEquivalentRecommendations(
  List<JourneyRecommendation> recommendations,
) {
  final retained = <Object, JourneyRecommendation>{};
  for (final recommendation in recommendations) {
    final key = switch (recommendation) {
      DirectJourneyRecommendation direct => (
        'direct',
        direct.originStopId,
        direct.destinationStopId,
        direct.routeId,
        direct.departureSeconds,
      ),
      TransferJourneyRecommendation transfer => (
        'transfer',
        transfer.originStopId,
        transfer.destinationStopId,
        transfer.firstRouteId,
        transfer.transferStopId,
        transfer.secondRouteId,
        transfer.departureSeconds,
      ),
    };
    final current = retained[key];
    if (current == null || _compareEquivalent(recommendation, current) < 0) {
      retained[key] = recommendation;
    }
  }
  return retained.values.toList(growable: false);
}

int _compareEquivalent(
  JourneyRecommendation left,
  JourneyRecommendation right,
) {
  final byArrival = left.arrivalSeconds.compareTo(right.arrivalSeconds);
  if (byArrival != 0) return byArrival;
  if (left case TransferJourneyRecommendation leftTransfer) {
    final rightTransfer = right as TransferJourneyRecommendation;
    final byWait = leftTransfer.transferWaitSeconds.compareTo(
      rightTransfer.transferWaitSeconds,
    );
    if (byWait != 0) return byWait;
    final byFirstTrip = leftTransfer.firstTripId.compareTo(
      rightTransfer.firstTripId,
    );
    if (byFirstTrip != 0) return byFirstTrip;
    return leftTransfer.secondTripId.compareTo(rightTransfer.secondTripId);
  }
  return (left as DirectJourneyRecommendation).tripId.compareTo(
    (right as DirectJourneyRecommendation).tripId,
  );
}

class SupabaseTimetableRecommendationRepository
    implements TimetableRecommendationRepository {
  SupabaseTimetableRecommendationRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const int _batchSize = 100;
  static const int _pageSize = 1000;

  final SupabaseClient _client;

  @override
  Future<List<JourneyRecommendation>> findRecommendations({
    required String originStopId,
    required String destinationStopId,
    required DateTime travelDate,
    required int travelTimeSeconds,
    required List<DirectRouteResult> directRoutes,
    required List<OneTransferJourneyResult> transferJourneys,
  }) async {
    try {
      final tripIds = <String>{
        for (final route in directRoutes) ...route.matchingTripIds,
        for (final journey in transferJourneys)
          for (final pair in journey.matchingTripPairs) ...[
            pair.firstTripId,
            pair.secondTripId,
          ],
      }.toList(growable: false);
      if (tripIds.isEmpty) return const [];

      final tripServices = await _loadTripServices(tripIds);
      final serviceIds = tripServices
          .map((trip) => trip.serviceId)
          .toSet()
          .toList();
      final transferStopIds = transferJourneys
          .map((journey) => journey.transferStopId)
          .toSet();
      final stopIds = {
        originStopId,
        destinationStopId,
        ...transferStopIds,
      }.toList();
      final responses = await Future.wait([
        _loadCalendars(serviceIds),
        _loadStopTimes(tripIds, stopIds),
      ]);
      return buildTimetableRecommendations(
        originStopId: originStopId,
        destinationStopId: destinationStopId,
        travelDate: travelDate,
        travelTimeSeconds: travelTimeSeconds,
        directRoutes: directRoutes,
        transferJourneys: transferJourneys,
        tripServices: tripServices,
        calendars: responses[0] as List<GtfsServiceCalendar>,
        stopTimes: responses[1] as List<GtfsStopTimeValue>,
      );
    } on PostgrestException catch (error) {
      throw TimetableReadException(
        error.message.isEmpty
            ? 'Unable to load scheduled departures.'
            : error.message,
      );
    } on Object {
      throw const TimetableReadException(
        'Unable to load scheduled departures.',
      );
    }
  }

  Future<List<GtfsTripService>> _loadTripServices(List<String> tripIds) async {
    final results = <GtfsTripService>[];
    for (final batch in _batches(tripIds)) {
      final data = await _client
          .from('gtfs_trips')
          .select('trip_id, service_id')
          .inFilter('trip_id', batch);
      results.addAll(
        data.map(
          (row) => GtfsTripService(
            tripId: row['trip_id'] as String,
            serviceId: row['service_id'] as String,
          ),
        ),
      );
    }
    return results;
  }

  Future<List<GtfsServiceCalendar>> _loadCalendars(
    List<String> serviceIds,
  ) async {
    final results = <GtfsServiceCalendar>[];
    for (final batch in _batches(serviceIds)) {
      final data = await _client
          .from('gtfs_calendar')
          .select(
            'service_id, start_date, end_date, monday, tuesday, '
            'wednesday, thursday, friday, saturday, sunday',
          )
          .inFilter('service_id', batch);
      results.addAll(data.map(_calendarFromSupabase));
    }
    return results;
  }

  Future<List<GtfsStopTimeValue>> _loadStopTimes(
    List<String> tripIds,
    List<String> stopIds,
  ) async {
    final results = <GtfsStopTimeValue>[];
    for (final batch in _batches(tripIds)) {
      var start = 0;
      while (true) {
        final data = await _client
            .from('gtfs_stop_times')
            .select(
              'trip_id, stop_id, stop_sequence, arrival_seconds, departure_seconds',
            )
            .inFilter('trip_id', batch)
            .inFilter('stop_id', stopIds)
            .order('trip_id')
            .order('stop_sequence')
            .range(start, start + _pageSize - 1);
        results.addAll(
          data.map(
            (row) => GtfsStopTimeValue(
              tripId: row['trip_id'] as String,
              stopId: row['stop_id'] as String,
              stopSequence: row['stop_sequence'] as int,
              arrivalSeconds: row['arrival_seconds'] as int,
              departureSeconds: row['departure_seconds'] as int,
            ),
          ),
        );
        if (data.length < _pageSize) break;
        start += _pageSize;
      }
    }
    return results;
  }

  Iterable<List<String>> _batches(List<String> values) sync* {
    for (var start = 0; start < values.length; start += _batchSize) {
      final end = (start + _batchSize).clamp(0, values.length);
      yield values.sublist(start, end);
    }
  }

  GtfsServiceCalendar _calendarFromSupabase(Map<String, dynamic> row) {
    return GtfsServiceCalendar(
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
    );
  }
}

class TimetableReadException implements Exception {
  const TimetableReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
