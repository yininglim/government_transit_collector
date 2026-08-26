import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_history_collector.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
// The pure-Dart client is supplied transitively by supabase_flutter. Importing
// it directly keeps this command-line collector independent of dart:ui.
// ignore: depend_on_referenced_packages
import 'package:supabase/supabase.dart';

class SupabaseRealtimeHistoryStorage implements RealtimeHistoryStorage {
  const SupabaseRealtimeHistoryStorage(
    this.client, {
    this.lookupBatchSize = 200,
  });
  final SupabaseClient client;
  final int lookupBatchSize;

  Future<void> close() => client.dispose();

  @override
  Future<HistoryStorageResult> insertSnapshot({
    required RealtimeFeedSnapshot snapshot,
    required List<HistoricalObservation> observations,
  }) async {
    final requestedTripIds = observations.map((item) => item.tripId).toSet();
    final existingTripIds = <String>{};
    final tripIdList = requestedTripIds.toList();
    for (
      var offset = 0;
      offset < tripIdList.length;
      offset += lookupBatchSize
    ) {
      final proposedEnd = offset + lookupBatchSize;
      final end = proposedEnd < tripIdList.length
          ? proposedEnd
          : tripIdList.length;
      final rows = await client
          .from('gtfs_trips')
          .select('trip_id')
          .inFilter('trip_id', tripIdList.sublist(offset, end));
      existingTripIds.addAll(rows.map((row) => row['trip_id'] as String));
    }
    final match = matchObservationsToStaticTrips(observations, existingTripIds);
    final matchedObservations = match.matchedObservations;
    final unmatchedTripIds = match.unmatchedTripIds;
    final unmatchedObservationCount = match.unmatchedObservationCount;

    final metadata = await client
        .from('gtfs_import_metadata')
        .insert({
          'feed_type': 'vehicle_positions',
          'source_name': realtimeHistorySourceName,
          'source_url': realtimeVehiclePositionsEndpoint,
          'feed_timestamp': snapshot.feedTimestamp?.toIso8601String(),
          'row_counts': {
            'received': snapshot.vehicles.length,
            'valid': observations.length,
            'static_trips_matched': matchedObservations.length,
            'unmatched_static_trips': unmatchedObservationCount,
          },
          'status': 'processing',
        })
        .select('import_id')
        .single();
    final importId = metadata['import_id'] as String;
    try {
      final inserted = matchedObservations.isEmpty
          ? <Map<String, dynamic>>[]
          : await client
                .from('vehicle_positions')
                .upsert(
                  matchedObservations
                      .map((item) => item.toDatabaseRow(importId))
                      .toList(),
                  onConflict: 'trip_id,vehicle_id,recorded_at',
                  ignoreDuplicates: true,
                )
                .select('position_id');
      await client
          .from('gtfs_import_metadata')
          .update({
            'status': 'completed',
            'imported_at': DateTime.now().toUtc().toIso8601String(),
            'row_counts': {
              'received': snapshot.vehicles.length,
              'valid': observations.length,
              'static_trips_matched': matchedObservations.length,
              'unmatched_static_trips': unmatchedObservationCount,
              'inserted': inserted.length,
              'duplicates': matchedObservations.length - inserted.length,
            },
          })
          .eq('import_id', importId);
      return HistoryStorageResult(
        staticTripsMatched: matchedObservations.length,
        unmatchedStaticTrips: unmatchedObservationCount,
        inserted: inserted.length,
        unmatchedTripIdSample: unmatchedTripIds.take(5).toList(),
      );
    } on Object catch (error) {
      await client
          .from('gtfs_import_metadata')
          .update({'status': 'failed', 'error_summary': error.toString()})
          .eq('import_id', importId);
      rethrow;
    }
  }
}
