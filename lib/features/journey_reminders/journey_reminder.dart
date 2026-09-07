import 'dart:convert';
import 'package:timezone/timezone.dart' as tz;
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';

const reminderOffsets = [5, 10, 15, 30];

class ReminderException implements Exception {
  const ReminderException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ReminderJourney {
  ReminderJourney(this.data);
  final Map<String, dynamic> data;

  factory ReminderJourney.fromRecommendation(
    JourneyRecommendation journey,
    DateTime serviceDate,
    String originName,
    String destinationName,
  ) {
    String label(String id, String? name) =>
        name?.trim().isNotEmpty == true ? name!.trim() : id;
    final direct = journey is DirectJourneyRecommendation ? journey : null;
    final transfer = journey is TransferJourneyRecommendation ? journey : null;
    final routes = direct != null
        ? [direct.routeId]
        : [transfer!.firstRouteId, transfer.secondRouteId];
    final trips = direct != null
        ? [direct.tripId]
        : [transfer!.firstTripId, transfer.secondTripId];
    final sequences = direct != null
        ? [direct.originStopSequence, direct.destinationStopSequence]
        : [
            transfer!.originStopSequence,
            transfer.firstTransferStopSequence,
            transfer.secondTransferStopSequence,
            transfer.destinationStopSequence,
          ];
    final date =
        '${serviceDate.year.toString().padLeft(4, '0')}-${serviceDate.month.toString().padLeft(2, '0')}-${serviceDate.day.toString().padLeft(2, '0')}';
    final origin = direct?.originStopId ?? transfer!.originStopId;
    final destination =
        direct?.destinationStopId ?? transfer!.destinationStopId;
    final departure = tz.TZDateTime(
      transitServiceLocation,
      serviceDate.year,
      serviceDate.month,
      serviceDate.day,
    ).add(Duration(seconds: journey.departureSeconds));
    return ReminderJourney({
      'journey_key': jsonEncode([
        routes,
        trips,
        sequences,
        origin,
        destination,
        date,
        journey.departureSeconds,
        transfer?.secondDepartureSeconds,
      ]),
      'route_label': direct != null
          ? label(direct.routeId, direct.routeShortName)
          : '${label(transfer!.firstRouteId, transfer.firstRouteShortName)} → ${label(transfer.secondRouteId, transfer.secondRouteShortName)}',
      'route_ids': routes,
      'trip_ids': trips,
      'origin_stop_id': origin,
      'origin_stop_name': originName,
      'destination_stop_id': destination,
      'destination_stop_name': destinationName,
      'service_date': date,
      'scheduled_departure_seconds': journey.departureSeconds,
      'scheduled_departure_at': departure.toUtc().toIso8601String(),
    });
  }

  String get key => data['journey_key'] as String;
  String get route => data['route_label'] as String;
  String get origin => data['origin_stop_name'] as String;
  String get destination => data['destination_stop_name'] as String;
  DateTime get departure =>
      DateTime.parse(data['scheduled_departure_at'] as String);
  DateTime reminderTime(int offset, DateTime now) {
    if (!departure.isAfter(now)) {
      throw const ReminderException('This departure has already passed.');
    }
    if (!reminderOffsets.contains(offset)) {
      throw const ReminderException('Choose a reminder option.');
    }
    if (!departure.subtract(const Duration(minutes: 5)).isAfter(now)) {
      throw const ReminderException(
        'This departure is too soon for a reminder.',
      );
    }
    final time = departure.subtract(Duration(minutes: offset));
    if (!time.isAfter(now)) {
      throw const ReminderException(
        'This reminder time has already passed. Choose a later reminder option.',
      );
    }
    return time;
  }
}

class JourneyReminder {
  JourneyReminder(this.data);
  final Map<String, dynamic> data;
  int get id => (data['reminder_id'] as num).toInt();
  String get owner => data['user_id'] as String;
  ReminderJourney get journey => ReminderJourney(data);
  DateTime get reminderAt => DateTime.parse(data['reminder_at'] as String);
}

String reminderDisplayTime(DateTime instant) {
  final local = transitServiceDateTime(instant);
  return '${local.day}/${local.month}/${local.year}, ${formatServiceDaySeconds(local.hour * 3600 + local.minute * 60)}';
}
