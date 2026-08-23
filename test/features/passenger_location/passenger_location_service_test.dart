import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location_service.dart';

class FakePlatform implements PassengerLocationPlatform {
  bool enabled = true;
  PassengerLocationPermission permission =
      PassengerLocationPermission.whileInUse;
  PassengerLocationPermission requestedPermission =
      PassengerLocationPermission.whileInUse;
  bool failPosition = false;
  Future<PassengerPlatformPosition>? currentPositionFuture;
  PassengerPlatformPosition? lastKnownPosition;
  Object? lastKnownError;
  int lastKnownRequests = 0;
  int permissionRequests = 0;

  @override
  Future<PassengerLocationPermission> checkPermission() async => permission;

  @override
  Future<PassengerPlatformPosition> getCurrentPosition() async {
    final future = currentPositionFuture;
    if (future != null) return future;
    if (failPosition) throw Exception('GPS failed');
    return PassengerPlatformPosition(
      latitude: 1.492,
      longitude: 103.741,
      accuracyMeters: 125,
      timestamp: DateTime.utc(2026, 8, 24),
    );
  }

  @override
  Future<PassengerPlatformPosition?> getLastKnownPosition() async {
    lastKnownRequests++;
    if (lastKnownError case final error?) throw error;
    return lastKnownPosition;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<PassengerLocationPermission> requestPermission() async {
    permissionRequests++;
    return requestedPermission;
  }
}

void main() {
  test(
    'enabled service and granted permission retrieve current location',
    () async {
      final result = await ForegroundPassengerLocationService(
        platform: FakePlatform(),
      ).getCurrentLocation();
      expect(result.status, PassengerLocationStatus.available);
      expect(result.location?.latitude, 1.492);
      expect(result.location?.accuracyMeters, 125);
      expect(result.location?.timestamp, DateTime.utc(2026, 8, 24));
    },
  );

  test('fresh-position timeout falls back to last-known position', () async {
    final pending = Completer<PassengerPlatformPosition>();
    final lastKnown = PassengerPlatformPosition(
      latitude: 1.5,
      longitude: 103.75,
      accuracyMeters: 40,
      timestamp: DateTime.utc(2026, 8, 24, 1),
    );
    final platform = FakePlatform()
      ..currentPositionFuture = pending.future
      ..lastKnownPosition = lastKnown;
    final result = await ForegroundPassengerLocationService(
      platform: platform,
      positionTimeout: const Duration(milliseconds: 5),
    ).getCurrentLocation();

    expect(result.status, PassengerLocationStatus.available);
    expect(result.location?.latitude, 1.5);
    expect(result.location?.timestamp, lastKnown.timestamp);
    expect(result.isLastKnown, isTrue);
    expect(platform.lastKnownRequests, 1);
  });

  test('fresh-position timeout without fallback returns an error', () async {
    final pending = Completer<PassengerPlatformPosition>();
    final platform = FakePlatform()..currentPositionFuture = pending.future;
    final result = await ForegroundPassengerLocationService(
      platform: platform,
      positionTimeout: const Duration(milliseconds: 5),
    ).getCurrentLocation();

    expect(result.status, PassengerLocationStatus.noLastKnownPosition);
    expect(result.location, isNull);
    expect(result.isLastKnown, isFalse);
    expect(platform.lastKnownRequests, 1);
  });

  test(
    'disabled device location service is reported without permission request',
    () async {
      final platform = FakePlatform()..enabled = false;
      final result = await ForegroundPassengerLocationService(
        platform: platform,
      ).getCurrentLocation();
      expect(result.status, PassengerLocationStatus.servicesDisabled);
      expect(platform.permissionRequests, 0);
    },
  );

  test(
    'not-yet-granted permission is requested once and can be granted',
    () async {
      final platform = FakePlatform()
        ..permission = PassengerLocationPermission.denied
        ..requestedPermission = PassengerLocationPermission.whileInUse;
      final result = await ForegroundPassengerLocationService(
        platform: platform,
      ).getCurrentLocation();
      expect(platform.permissionRequests, 1);
      expect(result.status, PassengerLocationStatus.available);
    },
  );

  test('denied permission is reported', () async {
    final platform = FakePlatform()
      ..permission = PassengerLocationPermission.denied
      ..requestedPermission = PassengerLocationPermission.denied;
    final result = await ForegroundPassengerLocationService(
      platform: platform,
    ).getCurrentLocation();
    expect(result.status, PassengerLocationStatus.permissionDenied);
  });

  test(
    'permanently denied permission is reported without requesting again',
    () async {
      final platform = FakePlatform()
        ..permission = PassengerLocationPermission.deniedForever;
      final result = await ForegroundPassengerLocationService(
        platform: platform,
      ).getCurrentLocation();
      expect(result.status, PassengerLocationStatus.permissionDeniedForever);
      expect(platform.permissionRequests, 0);
    },
  );

  test(
    'location retrieval error is converted to an application state',
    () async {
      final platform = FakePlatform()..failPosition = true;
      final result = await ForegroundPassengerLocationService(
        platform: platform,
      ).getCurrentLocation();
      expect(result.status, PassengerLocationStatus.unknownError);
    },
  );

  test('provider update exception is reported distinctly', () async {
    final platform = FakePlatform()
      ..currentPositionFuture = Future<PassengerPlatformPosition>.delayed(
        Duration.zero,
        () => throw const PositionUpdateException('provider unavailable'),
      );
    final result = await ForegroundPassengerLocationService(
      platform: platform,
    ).getCurrentLocation();
    expect(result.status, PassengerLocationStatus.providerUnavailable);
  });

  test('last-known platform exception is reported distinctly', () async {
    final platform = FakePlatform()
      ..currentPositionFuture = Completer<PassengerPlatformPosition>().future
      ..lastKnownError = PlatformException(
        code: 'LOCATION_ERROR',
        message: 'last known unavailable',
      );
    final result = await ForegroundPassengerLocationService(
      platform: platform,
      positionTimeout: const Duration(milliseconds: 5),
    ).getCurrentLocation();
    expect(result.status, PassengerLocationStatus.platformError);
  });
}
