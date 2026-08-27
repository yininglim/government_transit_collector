import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';

abstract interface class FuelCostCalculationRepository {
  Future<FuelCostCalculationEvidence> calculate({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  });
}

class DefaultFuelCostCalculationRepository
    implements FuelCostCalculationRepository {
  DefaultFuelCostCalculationRepository({
    CostEstimationEvidenceRepository? evidenceRepository,
  }) : _evidenceRepository =
           evidenceRepository ?? DefaultCostEstimationEvidenceRepository();

  final CostEstimationEvidenceRepository _evidenceRepository;

  @override
  Future<FuelCostCalculationEvidence> calculate({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  }) async {
    final evidence = await _evidenceRepository.loadEvidence(
      routeId: routeId,
      startUtc: startUtc,
      endExclusiveUtc: endExclusiveUtc,
      referenceDate: referenceDate,
    );
    final tripsById = <String, List<AiRouteTripEvidence>>{};
    for (final trip in evidence.network.trips) {
      tripsById.putIfAbsent(trip.tripId, () => []).add(trip);
    }
    final directionGroups = evidence.scheduledService.directionGroups
        .map((group) {
          return DirectionFuelCalculationEvidence(
            directionId: group.directionId,
            departures: group.departures
                .map((departure) {
                  final variants = tripsById[departure.tripId];
                  if (variants == null || variants.isEmpty) {
                    return ScheduledDepartureFuelEvidence(
                      departure: departure,
                      distanceStatus:
                          ScheduledDepartureDistanceStatus.tripNotFound,
                      tripDistanceMetres: null,
                      vehicleKilometres: null,
                    );
                  }
                  if (variants.length != 1) {
                    return ScheduledDepartureFuelEvidence(
                      departure: departure,
                      distanceStatus:
                          ScheduledDepartureDistanceStatus.tripVariantAmbiguous,
                      tripDistanceMetres: null,
                      vehicleKilometres: null,
                    );
                  }
                  final distance = variants.single.routeDistanceMeters;
                  if (distance == null || !distance.isFinite || distance <= 0) {
                    return ScheduledDepartureFuelEvidence(
                      departure: departure,
                      distanceStatus:
                          ScheduledDepartureDistanceStatus.distanceUnavailable,
                      tripDistanceMetres: distance,
                      vehicleKilometres: null,
                    );
                  }
                  return ScheduledDepartureFuelEvidence(
                    departure: departure,
                    distanceStatus: ScheduledDepartureDistanceStatus.costable,
                    tripDistanceMetres: distance,
                    vehicleKilometres: distance / 1000,
                  );
                })
                .toList(growable: false),
          );
        })
        .toList(growable: false);
    final allDepartures = directionGroups
        .expand((group) => group.departures)
        .toList(growable: false);
    final costable = allDepartures
        .where(
          (departure) =>
              departure.distanceStatus ==
              ScheduledDepartureDistanceStatus.costable,
        )
        .toList(growable: false);
    final uncostable = allDepartures
        .where(
          (departure) =>
              departure.distanceStatus !=
              ScheduledDepartureDistanceStatus.costable,
        )
        .toList(growable: false);
    final vehicleKilometres = costable.fold<double>(
      0,
      (total, departure) => total + departure.vehicleKilometres!,
    );
    final hasCostableDepartures = costable.isNotEmpty;
    final lowLitres = hasCostableDepartures
        ? vehicleKilometres *
              malaysianUrbanBusFuelConsumptionBenchmark.lowLitresPerKilometre
        : null;
    final highLitres = hasCostableDepartures
        ? vehicleKilometres *
              malaysianUrbanBusFuelConsumptionBenchmark.highLitresPerKilometre
        : null;
    final price = evidence.dieselPrice;
    final canCalculateExpenditure = hasCostableDepartures && price.isAvailable;
    return FuelCostCalculationEvidence(
      route: evidence.network.route,
      periodStart: evidence.periodStart,
      periodEnd: evidence.periodEnd,
      referenceDate: evidence.referenceDate,
      dieselPrice: price,
      benchmark: malaysianUrbanBusFuelConsumptionBenchmark,
      directionGroups: directionGroups,
      totalScheduledDepartureCount: allDepartures.length,
      costableScheduledDepartureCount: costable.length,
      uncostableDepartures: uncostable,
      scheduledVehicleKilometres: vehicleKilometres,
      lowEstimatedLitres: lowLitres,
      highEstimatedLitres: highLitres,
      lowEstimatedFuelCostRm: canCalculateExpenditure
          ? lowLitres! * price.rmPerLitre!
          : null,
      highEstimatedFuelCostRm: canCalculateExpenditure
          ? highLitres! * price.rmPerLitre!
          : null,
      status: _status(
        departureCount: allDepartures.length,
        costableCount: costable.length,
        uncostableCount: uncostable.length,
        price: price,
      ),
      scheduledServiceStatus: evidence.scheduledService.status,
      incompleteTripIds: evidence.scheduledService.incompleteTripIds,
      hasCompleteDirectionData:
          evidence.scheduledService.hasCompleteDirectionData,
    );
  }

  FuelCostCalculationStatus _status({
    required int departureCount,
    required int costableCount,
    required int uncostableCount,
    required DieselPriceEvidence price,
  }) {
    if (departureCount == 0) {
      return FuelCostCalculationStatus.noScheduledDepartures;
    }
    if (costableCount == 0) {
      return FuelCostCalculationStatus.noCostableDepartures;
    }
    if (!price.isAvailable) {
      return FuelCostCalculationStatus.fuelPriceUnavailable;
    }
    if (uncostableCount > 0) return FuelCostCalculationStatus.partial;
    return FuelCostCalculationStatus.available;
  }
}
