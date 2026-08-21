import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';

FeedEntity vehicleEntity({
  required String entityId,
  String? vehicleId = 'bus-1',
  String? tripId = 'trip-1',
  String? routeId = 'J10',
  double latitude = 1.49,
  double longitude = 103.74,
  int timestamp = 1787332800,
}) {
  return FeedEntity(
    id: entityId,
    vehicle: VehiclePosition(
      trip: tripId == null && routeId == null
          ? null
          : TripDescriptor(tripId: tripId, routeId: routeId),
      position: Position(latitude: latitude, longitude: longitude),
      timestamp: Int64(timestamp),
      vehicle: vehicleId == null ? null : VehicleDescriptor(id: vehicleId),
    ),
  );
}

List<int> feedBytes(Iterable<FeedEntity> entities) => FeedMessage(
  header: FeedHeader(gtfsRealtimeVersion: '2.0', timestamp: Int64(1787332900)),
  entity: entities,
).writeToBuffer();

void main() {
  const decoder = GtfsRealtimeFeedDecoder();

  test('decodes a valid FeedMessage vehicle entity', () {
    final result = decoder.decode(feedBytes([vehicleEntity(entityId: '1')]));

    expect(result.feedTimestampSeconds, 1787332900);
    expect(result.vehicles, hasLength(1));
    final vehicle = result.vehicles.single;
    expect(vehicle.vehicleId, 'bus-1');
    expect(vehicle.tripId, 'trip-1');
    expect(vehicle.routeId, 'J10');
    expect(vehicle.latitude, closeTo(1.49, 0.000001));
    expect(vehicle.longitude, closeTo(103.74, 0.00001));
    expect(vehicle.timestampSeconds, 1787332800);
  });

  test('decodes multiple vehicle entities', () {
    final result = decoder.decode(
      feedBytes([
        vehicleEntity(entityId: '1'),
        vehicleEntity(entityId: '2', vehicleId: 'bus-2'),
      ]),
    );

    expect(result.vehicles, hasLength(2));
  });

  test('ignores entities without VehiclePosition', () {
    final result = decoder.decode(
      feedBytes([FeedEntity(id: 'alert'), vehicleEntity(entityId: 'vehicle')]),
    );

    expect(result.vehicles, hasLength(1));
  });

  test('keeps missing vehicle descriptor and trip fields nullable', () {
    final result = decoder.decode(
      feedBytes([
        vehicleEntity(
          entityId: '1',
          vehicleId: null,
          tripId: null,
          routeId: null,
        ),
      ]),
    );

    expect(result.vehicles.single.vehicleId, isNull);
    expect(result.vehicles.single.tripId, isNull);
    expect(result.vehicles.single.routeId, isNull);
  });

  test('rejects malformed protobuf bytes', () {
    expect(
      () => decoder.decode(const [255, 255, 255]),
      throwsA(isA<RealtimeFeedDecodeException>()),
    );
  });

  test('rejects an empty byte response', () {
    expect(
      () => decoder.decode(const []),
      throwsA(isA<RealtimeFeedDecodeException>()),
    );
  });
}
