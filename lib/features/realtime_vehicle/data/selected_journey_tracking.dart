import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';

enum SelectedJourneyType { direct, transfer }

class SelectedJourneyLeg {
  const SelectedJourneyLeg({
    required this.routeId,
    required this.routeName,
    required this.tripId,
    required this.fromStopId,
    required this.fromStopName,
    required this.toStopId,
    required this.toStopName,
    required this.scheduledDeparture,
    required this.scheduledArrival,
  });

  final String routeId;
  final String routeName;
  final String tripId;
  final String fromStopId;
  final String fromStopName;
  final String toStopId;
  final String toStopName;
  final DateTime scheduledDeparture;
  final DateTime scheduledArrival;
}

class SelectedJourneyTracking {
  const SelectedJourneyTracking._({
    required this.type,
    required this.originStopId,
    required this.originStopName,
    required this.destinationStopId,
    required this.destinationStopName,
    required this.scheduledDeparture,
    required this.scheduledArrival,
    required this.legs,
    required this.recommendation,
    this.transferStopId,
    this.transferStopName,
  });

  factory SelectedJourneyTracking.fromRecommendation({
    required JourneyRecommendation recommendation,
    required String originStopName,
    required String destinationStopName,
    required DateTime travelDate,
  }) {
    DateTime at(int serviceSeconds) => DateTime(
      travelDate.year,
      travelDate.month,
      travelDate.day,
    ).add(Duration(seconds: serviceSeconds));
    String label(String routeId, String? shortName) =>
        shortName?.trim().isNotEmpty == true ? shortName!.trim() : routeId;

    return switch (recommendation) {
      DirectJourneyRecommendation direct => SelectedJourneyTracking._(
        type: SelectedJourneyType.direct,
        originStopId: direct.originStopId,
        originStopName: originStopName,
        destinationStopId: direct.destinationStopId,
        destinationStopName: destinationStopName,
        scheduledDeparture: at(direct.departureSeconds),
        scheduledArrival: at(direct.arrivalSeconds),
        legs: [
          SelectedJourneyLeg(
            routeId: direct.routeId,
            routeName: label(direct.routeId, direct.routeShortName),
            tripId: direct.tripId,
            fromStopId: direct.originStopId,
            fromStopName: originStopName,
            toStopId: direct.destinationStopId,
            toStopName: destinationStopName,
            scheduledDeparture: at(direct.departureSeconds),
            scheduledArrival: at(direct.arrivalSeconds),
          ),
        ],
        recommendation: recommendation,
      ),
      TransferJourneyRecommendation transfer => SelectedJourneyTracking._(
        type: SelectedJourneyType.transfer,
        originStopId: transfer.originStopId,
        originStopName: originStopName,
        destinationStopId: transfer.destinationStopId,
        destinationStopName: destinationStopName,
        transferStopId: transfer.transferStopId,
        transferStopName: transfer.transferStopName,
        scheduledDeparture: at(transfer.departureSeconds),
        scheduledArrival: at(transfer.arrivalSeconds),
        legs: [
          SelectedJourneyLeg(
            routeId: transfer.firstRouteId,
            routeName: label(
              transfer.firstRouteId,
              transfer.firstRouteShortName,
            ),
            tripId: transfer.firstTripId,
            fromStopId: transfer.originStopId,
            fromStopName: originStopName,
            toStopId: transfer.transferStopId,
            toStopName: transfer.transferStopName,
            scheduledDeparture: at(transfer.departureSeconds),
            scheduledArrival: at(transfer.transferArrivalSeconds),
          ),
          SelectedJourneyLeg(
            routeId: transfer.secondRouteId,
            routeName: label(
              transfer.secondRouteId,
              transfer.secondRouteShortName,
            ),
            tripId: transfer.secondTripId,
            fromStopId: transfer.transferStopId,
            fromStopName: transfer.transferStopName,
            toStopId: transfer.destinationStopId,
            toStopName: destinationStopName,
            scheduledDeparture: at(transfer.secondDepartureSeconds),
            scheduledArrival: at(transfer.arrivalSeconds),
          ),
        ],
        recommendation: recommendation,
      ),
    };
  }

  final SelectedJourneyType type;
  final String originStopId;
  final String originStopName;
  final String destinationStopId;
  final String destinationStopName;
  final String? transferStopId;
  final String? transferStopName;
  final DateTime scheduledDeparture;
  final DateTime scheduledArrival;
  final List<SelectedJourneyLeg> legs;

  final JourneyRecommendation recommendation;

  bool get isTransfer => type == SelectedJourneyType.transfer;
}
