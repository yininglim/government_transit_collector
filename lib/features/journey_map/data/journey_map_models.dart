class MapCoordinate {
  const MapCoordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

enum JourneyStopRole { origin, transfer, destination }

class JourneyMapStop {
  const JourneyMapStop({
    required this.stopId,
    required this.name,
    required this.coordinate,
    required this.role,
  });

  final String stopId;
  final String name;
  final MapCoordinate coordinate;
  final JourneyStopRole role;
}

class JourneyMapLeg {
  const JourneyMapLeg({
    required this.tripId,
    required this.routeLabel,
    required this.points,
    required this.usedFullShapeFallback,
  });

  final String tripId;
  final String routeLabel;
  final List<MapCoordinate> points;
  final bool usedFullShapeFallback;
}

class JourneyMapData {
  const JourneyMapData({required this.stops, required this.legs});

  final List<JourneyMapStop> stops;
  final List<JourneyMapLeg> legs;

  bool get hasRouteShape => legs.any((leg) => leg.points.isNotEmpty);
  bool get usedFullShapeFallback =>
      legs.any((leg) => leg.usedFullShapeFallback);
}
