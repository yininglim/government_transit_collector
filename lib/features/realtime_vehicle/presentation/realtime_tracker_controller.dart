import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/static_trip_matcher.dart';

const realtimePollingInterval = Duration(seconds: 15);

class RealtimeTrackerController extends ChangeNotifier {
  RealtimeTrackerController({
    required this.repository,
    required this.tripMatcher,
    this.pollingInterval = realtimePollingInterval,
  });

  final RealtimeVehicleRepository repository;
  final StaticTripMatcher tripMatcher;
  final Duration pollingInterval;

  RealtimeFeedSnapshot? snapshot;
  Set<String>? knownTripIds;
  String? initialError;
  String? refreshWarning;
  String? matchingWarning;
  bool isRefreshing = false;

  Timer? _timer;
  bool _disposed = false;

  bool get isInitialLoading => snapshot == null && isRefreshing;
  bool get isPolling => _timer?.isActive == true;

  void startPolling({bool fetchImmediately = true}) {
    if (_disposed || isPolling) return;
    if (fetchImmediately) unawaited(refresh());
    _timer = Timer.periodic(pollingInterval, (_) => unawaited(refresh()));
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    if (_disposed || isRefreshing) return;
    isRefreshing = true;
    initialError = null;
    refreshWarning = null;
    _notify();
    try {
      final latest = await repository.fetchVehiclePositions();
      Set<String>? latestKnownTripIds;
      String? latestMatchingWarning;
      try {
        latestKnownTripIds = await tripMatcher.findKnownTripIds(
          latest.vehicles.map((vehicle) => vehicle.tripId).whereType<String>(),
        );
      } on Object {
        latestMatchingWarning =
            'Vehicle positions loaded, but trip matching is unavailable.';
      }
      if (_disposed) return;
      snapshot = latest;
      knownTripIds = latestKnownTripIds;
      matchingWarning = latestMatchingWarning;
    } on RealtimeVehicleReadException catch (error) {
      if (_disposed) return;
      if (snapshot == null) {
        initialError = error.message;
      } else {
        refreshWarning =
            'Unable to refresh. Showing last known vehicle positions.';
      }
    } on Object {
      if (_disposed) return;
      if (snapshot == null) {
        initialError = 'Unable to load realtime vehicle positions.';
      } else {
        refreshWarning =
            'Unable to refresh. Showing last known vehicle positions.';
      }
    } finally {
      if (!_disposed) {
        isRefreshing = false;
        _notify();
      }
    }
  }

  bool? isTripMatched(String? tripId) {
    if (tripId == null || tripId.trim().isEmpty) return false;
    return knownTripIds?.contains(tripId);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}
