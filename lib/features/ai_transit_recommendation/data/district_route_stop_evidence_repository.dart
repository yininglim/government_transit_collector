import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/johor_bahru_boundary_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/johor_bahru_boundary_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';

abstract interface class DistrictRouteStopEvidenceRepository {
  Future<DistrictRouteStopEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  });
}

class DefaultDistrictRouteStopEvidenceRepository
    implements DistrictRouteStopEvidenceRepository {
  DefaultDistrictRouteStopEvidenceRepository({
    RouteStopEvidenceRepository? routeStopRepository,
    DistrictBoundaryRepository? boundaryRepository,
  }) : _routeStopRepository =
           routeStopRepository ?? DefaultRouteStopEvidenceRepository(),
       _boundaryRepository =
           boundaryRepository ?? DefaultDistrictBoundaryRepository();

  final RouteStopEvidenceRepository _routeStopRepository;
  final DistrictBoundaryRepository _boundaryRepository;
  Future<DistrictBoundaryEvidence>? _boundaryFuture;

  @override
  Future<DistrictRouteStopEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    final results = await Future.wait([
      _routeStopRepository.loadEvidence(
        routeId: routeId,
        startUtc: startUtc,
        endExclusiveUtc: endExclusiveUtc,
      ),
      _loadBoundary(),
    ]);
    final routeStopEvidence = results[0] as RouteStopEvidence;
    final boundary = results[1] as DistrictBoundaryEvidence;
    final tripEvidence = routeStopEvidence.network.trips
        .map((trip) {
          return TripDistrictStopEvidence(
            tripId: trip.tripId,
            stops: trip.stops
                .map((stop) {
                  return DistrictStopEvidence(
                    stopId: stop.stopId,
                    stopSequence: stop.stopSequence,
                    membership: _classify(stop.coordinate, boundary),
                  );
                })
                .toList(growable: false),
          );
        })
        .toList(growable: false);
    final occurrences = tripEvidence
        .expand((trip) => trip.stops)
        .toList(growable: false);
    final uniqueMembership = <String, DistrictStopMembership>{};
    for (final stop in occurrences) {
      uniqueMembership.update(
        stop.stopId,
        (existing) => existing == stop.membership
            ? existing
            : DistrictStopMembership.unverifiable,
        ifAbsent: () => stop.membership,
      );
    }
    return DistrictRouteStopEvidence(
      routeStopEvidence: routeStopEvidence,
      boundary: boundary,
      tripStopMembership: tripEvidence,
      stopOccurrenceCounts: _counts(occurrences.map((stop) => stop.membership)),
      uniqueStopCounts: _counts(uniqueMembership.values),
    );
  }

  Future<DistrictBoundaryEvidence> _loadBoundary() {
    final existing = _boundaryFuture;
    if (existing != null) return existing;
    final future = _boundaryRepository.loadBoundary();
    _boundaryFuture = future;
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {
        if (identical(_boundaryFuture, future)) _boundaryFuture = null;
      },
    );
    return future;
  }

  DistrictStopMembership _classify(
    MapCoordinate? coordinate,
    DistrictBoundaryEvidence boundary,
  ) {
    if (coordinate == null ||
        !coordinate.latitude.isFinite ||
        !coordinate.longitude.isFinite ||
        coordinate.latitude < -90 ||
        coordinate.latitude > 90 ||
        coordinate.longitude < -180 ||
        coordinate.longitude > 180 ||
        !boundary.isAvailable) {
      return DistrictStopMembership.unverifiable;
    }
    return _contains(boundary.geometry!, coordinate)
        ? DistrictStopMembership.insideJohorBahruDistrict
        : DistrictStopMembership.outsideJohorBahruDistrict;
  }

  bool _contains(DistrictBoundaryGeometry geometry, MapCoordinate point) {
    return geometry.polygons.any((polygon) {
      if (_onRingBoundary(point, polygon.exterior) ||
          polygon.holes.any((hole) => _onRingBoundary(point, hole))) {
        return true;
      }
      return _insideRing(point, polygon.exterior) &&
          !polygon.holes.any((hole) => _insideRing(point, hole));
    });
  }

  bool _onRingBoundary(MapCoordinate point, List<MapCoordinate> ring) {
    const tolerance = 1e-10;
    for (var index = 0; index < ring.length; index++) {
      final start = ring[index];
      final end = ring[(index + 1) % ring.length];
      final cross =
          (point.longitude - start.longitude) *
              (end.latitude - start.latitude) -
          (point.latitude - start.latitude) * (end.longitude - start.longitude);
      if (cross.abs() > tolerance) continue;
      if (point.longitude >=
              (start.longitude < end.longitude
                      ? start.longitude
                      : end.longitude) -
                  tolerance &&
          point.longitude <=
              (start.longitude > end.longitude
                      ? start.longitude
                      : end.longitude) +
                  tolerance &&
          point.latitude >=
              (start.latitude < end.latitude ? start.latitude : end.latitude) -
                  tolerance &&
          point.latitude <=
              (start.latitude > end.latitude ? start.latitude : end.latitude) +
                  tolerance) {
        return true;
      }
    }
    return false;
  }

  bool _insideRing(MapCoordinate point, List<MapCoordinate> ring) {
    var inside = false;
    for (
      var current = 0, previous = ring.length - 1;
      current < ring.length;
      previous = current++
    ) {
      final a = ring[current];
      final b = ring[previous];
      final intersects =
          (a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude;
      if (intersects) inside = !inside;
    }
    return inside;
  }

  DistrictMembershipCounts _counts(
    Iterable<DistrictStopMembership> memberships,
  ) {
    var inside = 0;
    var outside = 0;
    var unverifiable = 0;
    for (final membership in memberships) {
      switch (membership) {
        case DistrictStopMembership.insideJohorBahruDistrict:
          inside++;
        case DistrictStopMembership.outsideJohorBahruDistrict:
          outside++;
        case DistrictStopMembership.unverifiable:
          unverifiable++;
      }
    }
    return DistrictMembershipCounts(
      insideJohorBahruDistrict: inside,
      outsideJohorBahruDistrict: outside,
      unverifiable: unverifiable,
    );
  }
}
