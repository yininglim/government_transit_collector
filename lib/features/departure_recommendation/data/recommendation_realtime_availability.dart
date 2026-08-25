import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';

class RecommendationRealtimeAvailability {
  const RecommendationRealtimeAvailability({
    required this.firstLegLive,
    this.secondLegLive,
  });

  final bool firstLegLive;
  final bool? secondLegLive;
}

String recommendationAvailabilityKey(JourneyRecommendation recommendation) =>
    switch (recommendation) {
      DirectJourneyRecommendation direct => 'direct:${direct.tripId}',
      TransferJourneyRecommendation transfer =>
        'transfer:${transfer.firstTripId}:${transfer.secondTripId}',
    };

Map<String, RecommendationRealtimeAvailability>
evaluateRecommendationRealtimeAvailability({
  required Iterable<JourneyRecommendation> recommendations,
  required Iterable<RealtimeVehiclePosition> vehicles,
}) {
  final liveTripIds = vehicles
      .map((vehicle) => vehicle.tripId?.trim())
      .whereType<String>()
      .where((tripId) => tripId.isNotEmpty)
      .toSet();
  return {
    for (final recommendation in recommendations)
      recommendationAvailabilityKey(recommendation): switch (recommendation) {
        DirectJourneyRecommendation direct =>
          RecommendationRealtimeAvailability(
            firstLegLive: liveTripIds.contains(direct.tripId),
          ),
        TransferJourneyRecommendation transfer =>
          RecommendationRealtimeAvailability(
            firstLegLive: liveTripIds.contains(transfer.firstTripId),
            secondLegLive: liveTripIds.contains(transfer.secondTripId),
          ),
      },
  };
}
