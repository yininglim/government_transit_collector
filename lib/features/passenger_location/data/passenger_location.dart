class PassengerLocation {
  const PassengerLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;
}

enum PassengerLocationStatus {
  notRequested,
  loading,
  available,
  permissionDenied,
  permissionDeniedForever,
  servicesDisabled,
  positionTimeout,
  noLastKnownPosition,
  providerUnavailable,
  platformError,
  unknownError,
}

class PassengerLocationResult {
  const PassengerLocationResult._(
    this.status, {
    this.location,
    this.isLastKnown = false,
  });

  const PassengerLocationResult.notRequested()
    : this._(PassengerLocationStatus.notRequested);

  const PassengerLocationResult.loading([PassengerLocation? previousLocation])
    : this._(PassengerLocationStatus.loading, location: previousLocation);

  const PassengerLocationResult.available(
    PassengerLocation location, {
    bool isLastKnown = false,
  }) : this._(
         PassengerLocationStatus.available,
         location: location,
         isLastKnown: isLastKnown,
       );

  const PassengerLocationResult.permissionDenied()
    : this._(PassengerLocationStatus.permissionDenied);

  const PassengerLocationResult.permissionDeniedForever()
    : this._(PassengerLocationStatus.permissionDeniedForever);

  const PassengerLocationResult.servicesDisabled()
    : this._(PassengerLocationStatus.servicesDisabled);

  const PassengerLocationResult.positionTimeout()
    : this._(PassengerLocationStatus.positionTimeout);

  const PassengerLocationResult.noLastKnownPosition()
    : this._(PassengerLocationStatus.noLastKnownPosition);

  const PassengerLocationResult.providerUnavailable()
    : this._(PassengerLocationStatus.providerUnavailable);

  const PassengerLocationResult.platformError()
    : this._(PassengerLocationStatus.platformError);

  const PassengerLocationResult.unknownError()
    : this._(PassengerLocationStatus.unknownError);

  final PassengerLocationStatus status;
  final PassengerLocation? location;
  final bool isLastKnown;
}
