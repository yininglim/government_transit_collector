import 'dart:math' as math;

import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:timezone/timezone.dart' as timezone;

const delayThreshold = Duration(minutes: 5);
const minimumCompleteTripObservations = 3;
const endpointCoverageRadiusMeters = 750.0;

class RoutePerformanceCalculator {
  const RoutePerformanceCalculator();

  RoutePerformanceSummary calculate(RoutePerformanceData data) {
    final grouped = <String, List<HistoricalVehicleObservation>>{};
    for (final observation in data.observations) {
      final schedule = data.schedulesByTripId[observation.tripId];
      if (schedule == null) continue;
      final serviceDate = _serviceDate(observation.recordedAt, schedule);
      final key =
          '${observation.tripId}\u0000${observation.vehicleId}\u0000'
          '${serviceDate.year}-${serviceDate.month}-${serviceDate.day}';
      grouped.putIfAbsent(key, () => []).add(observation);
    }

    final trips = <ObservedTripPerformance>[];
    for (final observations in grouped.values) {
      observations.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
      final schedule = data.schedulesByTripId[observations.first.tripId]!;
      trips.add(_classify(observations, schedule));
    }
    trips.sort((a, b) => b.firstObservedAt.compareTo(a.firstObservedAt));

    final complete = trips.where((trip) => trip.isSufficientlyCovered).toList();
    if (complete.isEmpty) {
      return RoutePerformanceSummary(
        trips: trips,
        totalObservations: data.observations.length,
        averageTravelTime: null,
        delayedTripCount: 0,
        delayFrequencyPercent: null,
        scheduleAdherencePercent: null,
      );
    }
    final observedSeconds = complete
        .map((trip) => trip.observedDuration!.inSeconds)
        .reduce((a, b) => a + b);
    final delayed = complete
        .where((trip) => trip.delay! > delayThreshold)
        .length;
    final scheduleAdherence =
        complete
            .map((trip) => trip.scheduleAdherencePercent!)
            .reduce((a, b) => a + b) /
        complete.length;
    return RoutePerformanceSummary(
      trips: trips,
      totalObservations: data.observations.length,
      averageTravelTime: Duration(
        seconds: (observedSeconds / complete.length).round(),
      ),
      delayedTripCount: delayed,
      delayFrequencyPercent: delayed / complete.length * 100,
      scheduleAdherencePercent: scheduleAdherence,
    );
  }

  ObservedTripPerformance _classify(
    List<HistoricalVehicleObservation> observations,
    ScheduledTripReference schedule,
  ) {
    final serviceDate = _serviceDate(observations.first.recordedAt, schedule);
    if (observations.length < minimumCompleteTripObservations) {
      return _result(
        observations,
        schedule,
        serviceDate,
        TripCoverageStatus.insufficient,
        'Too few samples',
      );
    }
    HistoricalVehicleObservation? start;
    HistoricalVehicleObservation? end;
    for (final observation in observations) {
      if (start == null &&
          _distanceMeters(
                observation.latitude,
                observation.longitude,
                schedule.startLatitude,
                schedule.startLongitude,
              ) <=
              endpointCoverageRadiusMeters) {
        start = observation;
      }
      if (start != null &&
          observation.recordedAt.isAfter(start.recordedAt) &&
          _distanceMeters(
                observation.latitude,
                observation.longitude,
                schedule.endLatitude,
                schedule.endLongitude,
              ) <=
              endpointCoverageRadiusMeters) {
        end = observation;
      }
    }
    if (start == null) {
      return _result(
        observations,
        schedule,
        serviceDate,
        TripCoverageStatus.partial,
        'Start not observed',
      );
    }
    if (end == null) {
      return _result(
        observations,
        schedule,
        serviceDate,
        TripCoverageStatus.partial,
        'End not observed',
      );
    }
    return _result(
      observations,
      schedule,
      serviceDate,
      TripCoverageStatus.sufficientlyCovered,
      'Start and end observed near scheduled endpoints',
      observedDuration: end.recordedAt.difference(start.recordedAt),
    );
  }

  ObservedTripPerformance _result(
    List<HistoricalVehicleObservation> observations,
    ScheduledTripReference schedule,
    DateTime serviceDate,
    TripCoverageStatus status,
    String reason, {
    Duration? observedDuration,
  }) => ObservedTripPerformance(
    routeId: observations.first.routeId,
    tripId: observations.first.tripId,
    vehicleId: observations.first.vehicleId,
    serviceDate: serviceDate,
    scheduledDuration: schedule.scheduledDuration,
    firstObservedAt: observations.first.recordedAt,
    lastObservedAt: observations.last.recordedAt,
    observationCount: observations.length,
    coverageStatus: status,
    coverageReason: reason,
    observedDuration: observedDuration,
  );

  DateTime _serviceDate(DateTime instant, ScheduledTripReference schedule) {
    final local = transitServiceDateTime(instant);
    final midnight = timezone.TZDateTime(
      transitServiceLocation,
      local.year,
      local.month,
      local.day,
    );
    final candidates = [
      midnight.subtract(const Duration(days: 1)),
      midnight,
      midnight.add(const Duration(days: 1)),
    ];
    candidates.sort((a, b) {
      final aDifference = local
          .difference(a.add(Duration(seconds: schedule.startSeconds)))
          .abs();
      final bDifference = local
          .difference(b.add(Duration(seconds: schedule.startSeconds)))
          .abs();
      return aDifference.compareTo(bDifference);
    });
    final selected = candidates.first;
    return DateTime(selected.year, selected.month, selected.day);
  }
}

double _distanceMeters(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const earthRadius = 6371000.0;
  final latitudeDelta = _radians(latitudeB - latitudeA);
  final longitudeDelta = _radians(longitudeB - longitudeA);
  final a =
      math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(_radians(latitudeA)) *
          math.cos(_radians(latitudeB)) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _radians(double degrees) => degrees * math.pi / 180;
