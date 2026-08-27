import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

enum FuelCostCalculationStatus {
  available,
  partial,
  fuelPriceUnavailable,
  noScheduledDepartures,
  noCostableDepartures,
}

enum ScheduledDepartureDistanceStatus {
  costable,
  tripNotFound,
  distanceUnavailable,
  tripVariantAmbiguous,
}

class FuelConsumptionBenchmark {
  const FuelConsumptionBenchmark({
    required this.lowLitresPerKilometre,
    required this.highLitresPerKilometre,
    required this.source,
    required this.context,
    required this.limitation,
  });

  final double lowLitresPerKilometre;
  final double highLitresPerKilometre;
  final String source;
  final String context;
  final String limitation;
}

const malaysianUrbanBusFuelConsumptionBenchmark = FuelConsumptionBenchmark(
  lowLitresPerKilometre: 0.2794,
  highLitresPerKilometre: 0.3695,
  source: 'Melaka Greenhouse Gas Emissions Inventory 2016',
  context: 'Historical Malaysian urban-bus operating evidence from Melaka',
  limitation:
      'The benchmark is not a measurement of the Johor Bahru bus fleet.',
);

class ScheduledDepartureFuelEvidence {
  const ScheduledDepartureFuelEvidence({
    required this.departure,
    required this.distanceStatus,
    required this.tripDistanceMetres,
    required this.vehicleKilometres,
  });

  final ScheduledDepartureEvidence departure;
  final ScheduledDepartureDistanceStatus distanceStatus;
  final double? tripDistanceMetres;
  final double? vehicleKilometres;
}

class DirectionFuelCalculationEvidence {
  const DirectionFuelCalculationEvidence({
    required this.directionId,
    required this.departures,
  });

  final int? directionId;
  final List<ScheduledDepartureFuelEvidence> departures;

  int get costableDepartureCount => departures
      .where(
        (departure) =>
            departure.distanceStatus ==
            ScheduledDepartureDistanceStatus.costable,
      )
      .length;
}

class FuelCostCalculationEvidence {
  const FuelCostCalculationEvidence({
    required this.route,
    required this.periodStart,
    required this.periodEnd,
    required this.referenceDate,
    required this.dieselPrice,
    required this.benchmark,
    required this.directionGroups,
    required this.totalScheduledDepartureCount,
    required this.costableScheduledDepartureCount,
    required this.uncostableDepartures,
    required this.scheduledVehicleKilometres,
    required this.lowEstimatedLitres,
    required this.highEstimatedLitres,
    required this.lowEstimatedFuelCostRm,
    required this.highEstimatedFuelCostRm,
    required this.status,
    required this.scheduledServiceStatus,
    required this.incompleteTripIds,
    required this.hasCompleteDirectionData,
  });

  final RoutePerformanceRoute route;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime referenceDate;
  final DieselPriceEvidence dieselPrice;
  final FuelConsumptionBenchmark benchmark;
  final List<DirectionFuelCalculationEvidence> directionGroups;
  final int totalScheduledDepartureCount;
  final int costableScheduledDepartureCount;
  final List<ScheduledDepartureFuelEvidence> uncostableDepartures;
  final double scheduledVehicleKilometres;
  final double? lowEstimatedLitres;
  final double? highEstimatedLitres;
  final double? lowEstimatedFuelCostRm;
  final double? highEstimatedFuelCostRm;
  final FuelCostCalculationStatus status;
  final ScheduledServiceEvidenceStatus scheduledServiceStatus;
  final List<String> incompleteTripIds;
  final bool hasCompleteDirectionData;
}
