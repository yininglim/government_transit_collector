import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const decodedSnapshot = RealtimeFeedSnapshot(
  vehicles: [
    RealtimeVehiclePosition(
      vehicleId: 'bus-1',
      tripId: 'trip-1',
      routeId: 'J10',
      latitude: 1.49,
      longitude: 103.74,
      timestampSeconds: 100,
    ),
  ],
  feedTimestampSeconds: 101,
);

class FakeDecoder implements RealtimeFeedDecoder {
  FakeDecoder({this.result = decodedSnapshot, this.error});
  final RealtimeFeedSnapshot result;
  final Object? error;
  List<int>? receivedBytes;

  @override
  RealtimeFeedSnapshot decode(List<int> bytes) {
    receivedBytes = bytes;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  test('successful HTTP response decodes body bytes', () async {
    final decoder = FakeDecoder();
    final client = MockClient((request) async {
      expect(request.url.toString(), realtimeVehiclePositionsEndpoint);
      return http.Response.bytes([8, 1], 200);
    });
    final result = await DataGovMyRealtimeVehicleRepository(
      client: client,
      decoder: decoder,
    ).fetchVehiclePositions();

    expect(decoder.receivedBytes, [8, 1]);
    expect(result.vehicles.single.vehicleId, 'bus-1');
  });

  test('successful feed may contain no vehicle entities', () async {
    final repository = DataGovMyRealtimeVehicleRepository(
      client: MockClient((_) async => http.Response.bytes([8, 1], 200)),
      decoder: FakeDecoder(
        result: const RealtimeFeedSnapshot(
          vehicles: [],
          feedTimestampSeconds: 101,
        ),
      ),
    );

    expect((await repository.fetchVehiclePositions()).vehicles, isEmpty);
  });

  test('non-success HTTP status reports the status', () async {
    final repository = DataGovMyRealtimeVehicleRepository(
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );

    expect(
      repository.fetchVehiclePositions(),
      throwsA(
        isA<RealtimeVehicleReadException>().having(
          (error) => error.message,
          'message',
          contains('503'),
        ),
      ),
    );
  });

  test('network client failure becomes a readable exception', () async {
    final repository = DataGovMyRealtimeVehicleRepository(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );

    expect(
      repository.fetchVehiclePositions(),
      throwsA(isA<RealtimeVehicleReadException>()),
    );
  });

  test('request timeout becomes a readable exception', () async {
    final repository = DataGovMyRealtimeVehicleRepository(
      client: MockClient((_) => Completer<http.Response>().future),
      requestTimeout: const Duration(milliseconds: 1),
    );

    expect(
      repository.fetchVehiclePositions(),
      throwsA(
        isA<RealtimeVehicleReadException>().having(
          (error) => error.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test('empty HTTP response is rejected before decoding', () async {
    final repository = DataGovMyRealtimeVehicleRepository(
      client: MockClient((_) async => http.Response.bytes([], 200)),
    );

    expect(
      repository.fetchVehiclePositions(),
      throwsA(
        isA<RealtimeVehicleReadException>().having(
          (error) => error.message,
          'message',
          contains('empty'),
        ),
      ),
    );
  });

  test('malformed protobuf decoder failure is reported', () async {
    final repository = DataGovMyRealtimeVehicleRepository(
      client: MockClient((_) async => http.Response.bytes([255], 200)),
      decoder: FakeDecoder(
        error: const RealtimeFeedDecodeException('Malformed protobuf.'),
      ),
    );

    expect(
      repository.fetchVehiclePositions(),
      throwsA(
        isA<RealtimeVehicleReadException>().having(
          (error) => error.message,
          'message',
          contains('Malformed'),
        ),
      ),
    );
  });
}
