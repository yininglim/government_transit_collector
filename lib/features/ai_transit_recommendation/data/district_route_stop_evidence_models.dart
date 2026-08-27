import 'package:government_transit_collector/features/ai_transit_recommendation/data/johor_bahru_boundary_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_models.dart';

enum DistrictStopMembership {
  insideJohorBahruDistrict,
  outsideJohorBahruDistrict,
  unverifiable,
}

class DistrictRouteStopEvidence {
  const DistrictRouteStopEvidence({
    required this.routeStopEvidence,
    required this.boundary,
    required this.tripStopMembership,
    required this.stopOccurrenceCounts,
    required this.uniqueStopCounts,
  });

  final RouteStopEvidence routeStopEvidence;
  final DistrictBoundaryEvidence boundary;
  final List<TripDistrictStopEvidence> tripStopMembership;
  final DistrictMembershipCounts stopOccurrenceCounts;
  final DistrictMembershipCounts uniqueStopCounts;
}

class TripDistrictStopEvidence {
  const TripDistrictStopEvidence({required this.tripId, required this.stops});

  final String tripId;
  final List<DistrictStopEvidence> stops;
}

class DistrictStopEvidence {
  const DistrictStopEvidence({
    required this.stopId,
    required this.stopSequence,
    required this.membership,
  });

  final String stopId;
  final int stopSequence;
  final DistrictStopMembership membership;
}

class DistrictMembershipCounts {
  const DistrictMembershipCounts({
    required this.insideJohorBahruDistrict,
    required this.outsideJohorBahruDistrict,
    required this.unverifiable,
  });

  final int insideJohorBahruDistrict;
  final int outsideJohorBahruDistrict;
  final int unverifiable;

  int get total =>
      insideJohorBahruDistrict + outsideJohorBahruDistrict + unverifiable;
}
