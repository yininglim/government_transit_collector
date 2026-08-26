import 'dart:async';

import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:http/http.dart' as http;

const realtimeVehiclePositionsEndpoint =
    'https://api.data.gov.my/gtfs-realtime/vehicle-position/mybas-johor';

abstract interface class RealtimeVehicleRepository {
  Future<RealtimeFeedSnapshot> fetchVehiclePositions();
}

class DataGovMyRealtimeVehicleRepository implements RealtimeVehicleRepository {
  DataGovMyRealtimeVehicleRepository({
    http.Client? client,
    RealtimeFeedDecoder? decoder,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _decoder = decoder ?? const GtfsRealtimeFeedDecoder();

  final http.Client _client;
  final RealtimeFeedDecoder _decoder;
  final Duration requestTimeout;
  bool _isClosed = false;

  /// Releases the repository's persistent HTTP connection exactly once.
  void close() {
    if (_isClosed) return;
    _isClosed = true;
    _client.close();
  }

  @override
  Future<RealtimeFeedSnapshot> fetchVehiclePositions() async {
    try {
      final response = await _client
          .get(Uri.parse(realtimeVehiclePositionsEndpoint))
          .timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RealtimeVehicleReadException(
          'Realtime service returned HTTP ${response.statusCode}.',
        );
      }
      if (response.bodyBytes.isEmpty) {
        throw const RealtimeVehicleReadException(
          'The realtime service returned an empty response.',
        );
      }
      try {
        return _decoder.decode(response.bodyBytes);
      } on RealtimeFeedDecodeException catch (error) {
        throw RealtimeVehicleReadException(error.message);
      }
    } on RealtimeVehicleReadException {
      rethrow;
    } on TimeoutException {
      throw const RealtimeVehicleReadException(
        'The realtime request timed out. Please try again.',
      );
    } on http.ClientException {
      throw const RealtimeVehicleReadException(
        'Unable to reach the realtime service. Check your network.',
      );
    } on Object {
      throw const RealtimeVehicleReadException(
        'Unable to load realtime vehicle positions.',
      );
    }
  }
}

class RealtimeVehicleReadException implements Exception {
  const RealtimeVehicleReadException(this.message);
  final String message;

  @override
  String toString() => message;
}
