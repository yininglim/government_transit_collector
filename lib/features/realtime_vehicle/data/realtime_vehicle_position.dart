class RealtimeVehiclePosition {
  const RealtimeVehiclePosition({
    required this.vehicleId,
    required this.tripId,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.timestampSeconds,
  });

  /// This model is JSON-serializable for application storage/interchange.
  /// The data.gov.my response itself is protobuf and is never JSON-decoded.
  factory RealtimeVehiclePosition.fromJson(Map<String, dynamic> json) {
    return RealtimeVehiclePosition(
      vehicleId: json['vehicle_id'] as String?,
      tripId: json['trip_id'] as String?,
      routeId: json['route_id'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      timestampSeconds: (json['timestamp'] as num?)?.toInt(),
    );
  }

  final String? vehicleId;
  final String? tripId;
  final String? routeId;
  final double? latitude;
  final double? longitude;
  final int? timestampSeconds;

  Map<String, dynamic> toJson() => {
    'vehicle_id': vehicleId,
    'trip_id': tripId,
    'route_id': routeId,
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': timestampSeconds,
  };

  DateTime? get timestamp => timestampSeconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          timestampSeconds! * 1000,
          isUtc: true,
        );
}
