import 'dart:async';

import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';

const defaultCollectionInterval = Duration(minutes: 2);
const realtimeHistorySourceName = 'data.gov.my MyBAS Johor vehicle positions';

class HistoricalObservation {
  const HistoricalObservation({
    required this.feedEntityId,
    required this.vehicleId,
    required this.tripId,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.vehicleTimestamp,
    required this.collectedAt,
  });

  final String feedEntityId;
  final String vehicleId;
  final String tripId;
  final String routeId;
  final double latitude;
  final double longitude;
  final DateTime vehicleTimestamp;
  final DateTime collectedAt;

  String get duplicateKey =>
      '$tripId\u0000$vehicleId\u0000${vehicleTimestamp.toUtc().toIso8601String()}';

  Map<String, dynamic> toDatabaseRow(String importId) => {
    'import_id': importId,
    'feed_entity_id': feedEntityId,
    'trip_id': tripId,
    'route_id': routeId,
    'vehicle_id': vehicleId,
    'latitude': latitude,
    'longitude': longitude,
    'recorded_at': vehicleTimestamp.toUtc().toIso8601String(),
    'received_at': collectedAt.toUtc().toIso8601String(),
  };
}

class ObservationValidationResult {
  const ObservationValidationResult(this.observations, this.invalidCount);
  final List<HistoricalObservation> observations;
  final int invalidCount;
}

ObservationValidationResult validateHistoricalObservations(
  Iterable<RealtimeVehiclePosition> vehicles,
  DateTime collectedAt,
) {
  final observations = <HistoricalObservation>[];
  var invalidCount = 0;
  for (final vehicle in vehicles) {
    final entityId = vehicle.entityId?.trim();
    final vehicleId = vehicle.vehicleId?.trim();
    final tripId = vehicle.tripId?.trim();
    final routeId = vehicle.routeId?.trim();
    final latitude = vehicle.latitude;
    final longitude = vehicle.longitude;
    final timestamp = vehicle.timestamp;
    if (entityId == null ||
        entityId.isEmpty ||
        vehicleId == null ||
        vehicleId.isEmpty ||
        tripId == null ||
        tripId.isEmpty ||
        routeId == null ||
        routeId.isEmpty ||
        timestamp == null ||
        latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      invalidCount++;
      continue;
    }
    observations.add(
      HistoricalObservation(
        feedEntityId: entityId,
        vehicleId: vehicleId,
        tripId: tripId,
        routeId: routeId,
        latitude: latitude,
        longitude: longitude,
        vehicleTimestamp: timestamp,
        collectedAt: collectedAt,
      ),
    );
  }
  return ObservationValidationResult(observations, invalidCount);
}

abstract interface class RealtimeHistoryStorage {
  Future<HistoryStorageResult> insertSnapshot({
    required RealtimeFeedSnapshot snapshot,
    required List<HistoricalObservation> observations,
  });
}

class HistoryStorageResult {
  const HistoryStorageResult({
    required this.staticTripsMatched,
    required this.unmatchedStaticTrips,
    required this.inserted,
    this.unmatchedTripIdSample = const [],
  });

  final int staticTripsMatched;
  final int unmatchedStaticTrips;
  final int inserted;
  final List<String> unmatchedTripIdSample;
}

class StaticTripMatchResult {
  const StaticTripMatchResult({
    required this.matchedObservations,
    required this.unmatchedObservationCount,
    required this.unmatchedTripIds,
  });
  final List<HistoricalObservation> matchedObservations;
  final int unmatchedObservationCount;
  final List<String> unmatchedTripIds;
}

StaticTripMatchResult matchObservationsToStaticTrips(
  List<HistoricalObservation> observations,
  Set<String> existingTripIds,
) {
  final matched = observations
      .where((item) => existingTripIds.contains(item.tripId))
      .toList();
  final requested = observations.map((item) => item.tripId).toSet();
  final unmatchedIds = requested.difference(existingTripIds).toList()..sort();
  return StaticTripMatchResult(
    matchedObservations: matched,
    unmatchedObservationCount: observations.length - matched.length,
    unmatchedTripIds: unmatchedIds,
  );
}

class CollectionCycleResult {
  const CollectionCycleResult({
    required this.received,
    required this.valid,
    required this.inserted,
    required this.duplicates,
    required this.invalid,
    required this.duration,
    this.staticTripsMatched,
    this.unmatchedStaticTrips = 0,
    this.unmatchedTripIdSample = const [],
    this.error,
  });
  final int received;
  final int valid;
  final int inserted;
  final int duplicates;
  final int invalid;
  final int? staticTripsMatched;
  final int unmatchedStaticTrips;
  final List<String> unmatchedTripIdSample;
  final Duration duration;
  final Object? error;
}

class CollectorSessionTotals {
  int cycles = 0;
  int received = 0;
  int inserted = 0;
  int duplicates = 0;
  int invalid = 0;
  int unmatchedStaticTrips = 0;
}

typedef CollectorLog = void Function(String message);
typedef CollectorWait = Future<void> Function(Duration duration);

class RealtimeHistoryCollector {
  RealtimeHistoryCollector({
    required this.repository,
    this.storage,
    this.interval = defaultCollectionInterval,
    this.dryRun = false,
    this.once = false,
    this.log = print,
    CollectorWait? wait,
    DateTime Function()? clock,
  }) : wait = wait ?? Future<void>.delayed,
       clock = clock ?? DateTime.now;

  final RealtimeVehicleRepository repository;
  final RealtimeHistoryStorage? storage;
  final Duration interval;
  final bool dryRun;
  final bool once;
  final CollectorLog log;
  final CollectorWait wait;
  final DateTime Function() clock;
  final totals = CollectorSessionTotals();
  bool _stopRequested = false;

  void requestStop() => _stopRequested = true;

  Future<CollectionCycleResult> collectOnce() async {
    final started = clock();
    late final RealtimeFeedSnapshot snapshot;
    try {
      snapshot = await repository.fetchVehiclePositions();
    } on Object catch (error) {
      return CollectionCycleResult(
        received: 0,
        valid: 0,
        inserted: 0,
        duplicates: 0,
        invalid: 0,
        duration: clock().difference(started),
        error: error,
      );
    }
    final validation = validateHistoricalObservations(
      snapshot.vehicles,
      clock().toUtc(),
    );
    try {
      HistoryStorageResult? storageResult;
      if (!dryRun && validation.observations.isNotEmpty) {
        storageResult = await storage!.insertSnapshot(
          snapshot: snapshot,
          observations: validation.observations,
        );
      }
      final inserted = storageResult?.inserted ?? 0;
      final matched = storageResult?.staticTripsMatched;
      final duplicates = dryRun ? 0 : (matched ?? 0) - inserted;
      return CollectionCycleResult(
        received: snapshot.vehicles.length,
        valid: validation.observations.length,
        inserted: inserted,
        duplicates: duplicates,
        invalid: validation.invalidCount,
        staticTripsMatched: matched,
        unmatchedStaticTrips: storageResult?.unmatchedStaticTrips ?? 0,
        unmatchedTripIdSample: storageResult?.unmatchedTripIdSample ?? const [],
        duration: clock().difference(started),
      );
    } on Object catch (error) {
      return CollectionCycleResult(
        received: snapshot.vehicles.length,
        valid: validation.observations.length,
        inserted: 0,
        duplicates: 0,
        invalid: validation.invalidCount,
        duration: clock().difference(started),
        error: error,
      );
    }
  }

  Future<void> run() async {
    do {
      final result = await collectOnce();
      totals.cycles++;
      totals.received += result.received;
      totals.inserted += result.inserted;
      totals.duplicates += result.duplicates;
      totals.invalid += result.invalid;
      totals.unmatchedStaticTrips += result.unmatchedStaticTrips;
      _logCycle(result);
      if (once || dryRun || _stopRequested) break;
      log('Next collection in ${_formatInterval(interval)}...');
      await wait(interval);
    } while (!_stopRequested);
  }

  void _logCycle(CollectionCycleResult result) {
    log('[${clock().toLocal().toIso8601String()}]');
    if (result.error != null) {
      log('Collection failed: ${result.error}');
      log(
        'Duration: ${(result.duration.inMilliseconds / 1000).toStringAsFixed(1)} s',
      );
      return;
    }
    log('Realtime vehicles: ${result.received}');
    log('Valid observations: ${result.valid}');
    if (result.staticTripsMatched == null) {
      log('Static trip matching: not checked (dry run)');
    } else {
      log('Static trips matched: ${result.staticTripsMatched}');
      log('Unmatched static trips skipped: ${result.unmatchedStaticTrips}');
      if (result.unmatchedTripIdSample.isNotEmpty) {
        log(
          'Unmatched trip ID sample: ${result.unmatchedTripIdSample.join(', ')}',
        );
      }
    }
    log(dryRun ? 'Inserted: 0 (dry run)' : 'Inserted: ${result.inserted}');
    log('Duplicates skipped: ${result.duplicates}');
    log('Invalid skipped: ${result.invalid}');
    log(
      'Duration: ${(result.duration.inMilliseconds / 1000).toStringAsFixed(1)} s',
    );
  }
}

String _formatInterval(Duration duration) =>
    duration.inMinutes == 1 ? '1 minute' : '${duration.inMinutes} minutes';
