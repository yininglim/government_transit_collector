import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';

class RealtimeFeedSnapshot {
  const RealtimeFeedSnapshot({
    required this.vehicles,
    required this.feedTimestampSeconds,
  });

  final List<RealtimeVehiclePosition> vehicles;
  final int? feedTimestampSeconds;

  DateTime? get feedTimestamp => feedTimestampSeconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          feedTimestampSeconds! * 1000,
          isUtc: true,
        );
}

abstract interface class RealtimeFeedDecoder {
  RealtimeFeedSnapshot decode(List<int> bytes);
}

class GtfsRealtimeFeedDecoder implements RealtimeFeedDecoder {
  const GtfsRealtimeFeedDecoder();

  @override
  RealtimeFeedSnapshot decode(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const RealtimeFeedDecodeException(
        'The realtime response was empty.',
      );
    }
    try {
      final feed = FeedMessage.fromBuffer(bytes);
      final vehicles = <RealtimeVehiclePosition>[];
      for (final entity in feed.entity) {
        if (!entity.hasVehicle()) continue;
        final vehicle = entity.vehicle;
        final trip = vehicle.hasTrip() ? vehicle.trip : null;
        final descriptor = vehicle.hasVehicle() ? vehicle.vehicle : null;
        final position = vehicle.hasPosition() ? vehicle.position : null;
        vehicles.add(
          RealtimeVehiclePosition(
            entityId: entity.hasId() ? entity.id : null,
            vehicleId: descriptor?.hasId() == true
                ? descriptor!.id
                : descriptor?.hasLabel() == true
                ? descriptor!.label
                : null,
            tripId: trip?.hasTripId() == true ? trip!.tripId : null,
            routeId: trip?.hasRouteId() == true ? trip!.routeId : null,
            latitude: position?.hasLatitude() == true
                ? position!.latitude
                : null,
            longitude: position?.hasLongitude() == true
                ? position!.longitude
                : null,
            timestampSeconds: vehicle.hasTimestamp()
                ? vehicle.timestamp.toInt()
                : null,
          ),
        );
      }
      return RealtimeFeedSnapshot(
        vehicles: vehicles,
        feedTimestampSeconds: feed.hasHeader() && feed.header.hasTimestamp()
            ? feed.header.timestamp.toInt()
            : null,
      );
    } on RealtimeFeedDecodeException {
      rethrow;
    } on Object {
      throw const RealtimeFeedDecodeException(
        'The realtime response could not be decoded.',
      );
    }
  }
}

class RealtimeFeedDecodeException implements Exception {
  const RealtimeFeedDecodeException(this.message);
  final String message;

  @override
  String toString() => message;
}
