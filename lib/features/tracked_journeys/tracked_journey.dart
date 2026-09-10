import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import 'package:timezone/timezone.dart' as timezone;

/// Immutable GTFS snapshot; service seconds preserve departures after midnight.
class TrackedJourneySnapshot {
  const TrackedJourneySnapshot({
    required this.recommendation,
    required this.originName,
    required this.destinationName,
    required this.serviceDate,
  });
  final JourneyRecommendation recommendation;
  final String originName, destinationName;
  final DateTime serviceDate;

  DateTime at(int seconds) => timezone.TZDateTime(
    transitServiceLocation,
    serviceDate.year,
    serviceDate.month,
    serviceDate.day,
  ).add(Duration(seconds: seconds)).toUtc();
  DateTime get expectedArrival => at(recommendation.arrivalSeconds);
  SelectedJourneyTracking get tracking =>
      SelectedJourneyTracking.fromRecommendation(
        recommendation: recommendation,
        originStopName: originName,
        destinationStopName: destinationName,
        travelDate: serviceDate,
      );
  String get routeLabel =>
      tracking.legs.map((leg) => leg.routeName).join(' → ');
  RecentJourneySearch get planAgain => RecentJourneySearch(
    originStopId: tracking.originStopId,
    originStopName: originName,
    destinationStopId: tracking.destinationStopId,
    destinationStopName: destinationName,
    searchedAt: at(recommendation.departureSeconds),
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'service_date':
        '${serviceDate.year.toString().padLeft(4, '0')}-${serviceDate.month.toString().padLeft(2, '0')}-${serviceDate.day.toString().padLeft(2, '0')}',
    'origin_name': originName,
    'destination_name': destinationName,
    'recommendation': switch (recommendation) {
      DirectJourneyRecommendation j => {
        'type': 'direct',
        'originStopId': j.originStopId,
        'destinationStopId': j.destinationStopId,
        'originStopSequence': j.originStopSequence,
        'destinationStopSequence': j.destinationStopSequence,
        'departureSeconds': j.departureSeconds,
        'arrivalSeconds': j.arrivalSeconds,
        'tripId': j.tripId,
        'routeId': j.routeId,
        'routeShortName': j.routeShortName,
        'serviceId': j.serviceId,
      },
      TransferJourneyRecommendation j => {
        'type': 'transfer',
        'originStopId': j.originStopId,
        'destinationStopId': j.destinationStopId,
        'originStopSequence': j.originStopSequence,
        'destinationStopSequence': j.destinationStopSequence,
        'departureSeconds': j.departureSeconds,
        'arrivalSeconds': j.arrivalSeconds,
        'firstTripId': j.firstTripId,
        'secondTripId': j.secondTripId,
        'firstRouteId': j.firstRouteId,
        'firstRouteShortName': j.firstRouteShortName,
        'secondRouteId': j.secondRouteId,
        'secondRouteShortName': j.secondRouteShortName,
        'transferStopId': j.transferStopId,
        'transferStopName': j.transferStopName,
        'firstServiceId': j.firstServiceId,
        'secondServiceId': j.secondServiceId,
        'firstTransferStopSequence': j.firstTransferStopSequence,
        'secondTransferStopSequence': j.secondTransferStopSequence,
        'transferArrivalSeconds': j.transferArrivalSeconds,
        'secondDepartureSeconds': j.secondDepartureSeconds,
      },
    },
  };

  factory TrackedJourneySnapshot.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported journey snapshot');
    }
    final r = Map<String, dynamic>.from(json['recommendation'] as Map);
    final JourneyRecommendation recommendation = switch (r['type']) {
      'direct' => DirectJourneyRecommendation(
        originStopId: r['originStopId'] as String,
        destinationStopId: r['destinationStopId'] as String,
        originStopSequence: (r['originStopSequence'] as num).toInt(),
        destinationStopSequence: (r['destinationStopSequence'] as num).toInt(),
        departureSeconds: (r['departureSeconds'] as num).toInt(),
        arrivalSeconds: (r['arrivalSeconds'] as num).toInt(),
        tripId: r['tripId'] as String,
        routeId: r['routeId'] as String,
        routeShortName: r['routeShortName'] as String?,
        serviceId: r['serviceId'] as String,
      ),
      'transfer' => TransferJourneyRecommendation(
        originStopId: r['originStopId'] as String,
        destinationStopId: r['destinationStopId'] as String,
        originStopSequence: (r['originStopSequence'] as num).toInt(),
        destinationStopSequence: (r['destinationStopSequence'] as num).toInt(),
        departureSeconds: (r['departureSeconds'] as num).toInt(),
        arrivalSeconds: (r['arrivalSeconds'] as num).toInt(),
        firstTripId: r['firstTripId'] as String,
        secondTripId: r['secondTripId'] as String,
        firstRouteId: r['firstRouteId'] as String,
        firstRouteShortName: r['firstRouteShortName'] as String?,
        secondRouteId: r['secondRouteId'] as String,
        secondRouteShortName: r['secondRouteShortName'] as String?,
        transferStopId: r['transferStopId'] as String,
        transferStopName: r['transferStopName'] as String,
        firstServiceId: r['firstServiceId'] as String,
        secondServiceId: r['secondServiceId'] as String,
        firstTransferStopSequence: (r['firstTransferStopSequence'] as num)
            .toInt(),
        secondTransferStopSequence: (r['secondTransferStopSequence'] as num)
            .toInt(),
        transferArrivalSeconds: (r['transferArrivalSeconds'] as num).toInt(),
        secondDepartureSeconds: (r['secondDepartureSeconds'] as num).toInt(),
      ),
      _ => throw const FormatException('Unknown journey type'),
    };
    return TrackedJourneySnapshot(
      recommendation: recommendation,
      originName: json['origin_name'] as String,
      destinationName: json['destination_name'] as String,
      serviceDate: DateTime.parse(json['service_date'] as String),
    );
  }
}

class TrackedJourney {
  const TrackedJourney({
    required this.id,
    required this.userId,
    required this.snapshot,
    required this.status,
    required this.startedAt,
    this.completedAt,
  });
  final String id, userId, status;
  final TrackedJourneySnapshot snapshot;
  final DateTime startedAt;
  final DateTime? completedAt;
  bool needsConfirmation(DateTime now) =>
      status == 'active' && !now.toUtc().isBefore(snapshot.expectedArrival);
  factory TrackedJourney.fromJson(Map<String, dynamic> row) => TrackedJourney(
    id: row['tracking_session_id'] as String,
    userId: row['user_id'] as String,
    snapshot: TrackedJourneySnapshot.fromJson(
      Map<String, dynamic>.from(row['journey_snapshot'] as Map),
    ),
    status: row['status'] as String,
    startedAt: DateTime.parse(row['started_at'] as String),
    completedAt: row['completed_at'] == null
        ? null
        : DateTime.parse(row['completed_at'] as String),
  );
}
