import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';

enum PassengerLocationPermission { denied, deniedForever, whileInUse, always }

class PassengerPlatformPosition {
  const PassengerPlatformPosition({
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

abstract interface class PassengerLocationPlatform {
  Future<bool> isLocationServiceEnabled();
  Future<PassengerLocationPermission> checkPermission();
  Future<PassengerLocationPermission> requestPermission();
  Future<PassengerPlatformPosition> getCurrentPosition();
  Future<PassengerPlatformPosition?> getLastKnownPosition();
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

abstract interface class PassengerLocationService {
  Future<PassengerLocationResult> getCurrentLocation();
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

class ForegroundPassengerLocationService implements PassengerLocationService {
  ForegroundPassengerLocationService({
    PassengerLocationPlatform? platform,
    this.positionTimeout = const Duration(seconds: 12),
    this.operationTimeout = const Duration(seconds: 15),
  }) : _platform = platform ?? GeolocatorPassengerLocationPlatform();

  final PassengerLocationPlatform _platform;
  final Duration positionTimeout;
  final Duration operationTimeout;

  @override
  Future<PassengerLocationResult> getCurrentLocation() async {
    try {
      return await _getCurrentLocation().timeout(operationTimeout);
    } on TimeoutException {
      return const PassengerLocationResult.positionTimeout();
    } on LocationServiceDisabledException {
      return const PassengerLocationResult.servicesDisabled();
    } on PermissionDeniedException {
      return const PassengerLocationResult.permissionDenied();
    } on PositionUpdateException {
      return const PassengerLocationResult.providerUnavailable();
    } on PlatformException {
      return const PassengerLocationResult.platformError();
    } on Object {
      return const PassengerLocationResult.unknownError();
    }
  }

  Future<PassengerLocationResult> _getCurrentLocation() async {
    final serviceEnabled = await _platform.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const PassengerLocationResult.servicesDisabled();
    }
    var permission = await _platform.checkPermission();
    if (permission == PassengerLocationPermission.denied) {
      permission = await _platform.requestPermission();
    }
    if (permission == PassengerLocationPermission.denied) {
      return const PassengerLocationResult.permissionDenied();
    }
    if (permission == PassengerLocationPermission.deniedForever) {
      return const PassengerLocationResult.permissionDeniedForever();
    }
    try {
      final position = await _platform.getCurrentPosition().timeout(
        positionTimeout,
      );
      return PassengerLocationResult.available(_toLocation(position));
    } on TimeoutException {
      final lastKnown = await _platform.getLastKnownPosition();
      if (lastKnown == null) {
        return const PassengerLocationResult.noLastKnownPosition();
      }
      return PassengerLocationResult.available(
        _toLocation(lastKnown),
        isLastKnown: true,
      );
    }
  }

  @override
  Future<bool> openAppSettings() => _platform.openAppSettings();

  @override
  Future<bool> openLocationSettings() => _platform.openLocationSettings();

  PassengerLocation _toLocation(PassengerPlatformPosition position) =>
      PassengerLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracyMeters,
        timestamp: position.timestamp,
      );
}

class GeolocatorPassengerLocationPlatform implements PassengerLocationPlatform {
  @override
  Future<PassengerLocationPermission> checkPermission() async =>
      _fromGeolocatorPermission(await Geolocator.checkPermission());

  @override
  Future<PassengerPlatformPosition> getCurrentPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return PassengerPlatformPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      timestamp: position.timestamp,
    );
  }

  @override
  Future<PassengerPlatformPosition?> getLastKnownPosition() async {
    final position = await Geolocator.getLastKnownPosition();
    if (position == null) return null;
    return PassengerPlatformPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      timestamp: position.timestamp,
    );
  }

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<PassengerLocationPermission> requestPermission() async =>
      _fromGeolocatorPermission(await Geolocator.requestPermission());

  PassengerLocationPermission _fromGeolocatorPermission(
    LocationPermission permission,
  ) => switch (permission) {
    LocationPermission.denied => PassengerLocationPermission.denied,
    LocationPermission.deniedForever =>
      PassengerLocationPermission.deniedForever,
    LocationPermission.whileInUse => PassengerLocationPermission.whileInUse,
    LocationPermission.always => PassengerLocationPermission.always,
    LocationPermission.unableToDetermine => PassengerLocationPermission.denied,
  };
}
