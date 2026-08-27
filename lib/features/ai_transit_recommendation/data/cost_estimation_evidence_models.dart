import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';

enum DieselPriceEvidenceStatus {
  available,
  unavailable,
  noApplicableRecord,
  unusable,
}

enum UnavailableCostInput {
  busFuelConsumption,
  driverStaffCost,
  maintenanceCost,
  busAcquisitionCost,
  busStopConstructionCost,
  operatingCostPerKilometre,
  operatingCostPerHour,
}

class FuelPriceSource {
  const FuelPriceSource({
    required this.platform,
    required this.publisher,
    required this.datasetId,
    required this.datasetName,
  });

  final String platform;
  final String publisher;
  final String datasetId;
  final String datasetName;
}

const fuelPriceSource = FuelPriceSource(
  platform: 'data.gov.my',
  publisher: 'Ministry of Finance Malaysia',
  datasetId: 'fuelprice',
  datasetName: 'Petrol & Diesel Prices',
);

class DieselPriceEvidence {
  const DieselPriceEvidence({
    required this.status,
    required this.source,
    required this.effectiveDate,
    required this.rmPerLitre,
  });

  final DieselPriceEvidenceStatus status;
  final FuelPriceSource source;
  final DateTime? effectiveDate;
  final double? rmPerLitre;

  bool get isAvailable =>
      status == DieselPriceEvidenceStatus.available &&
      effectiveDate != null &&
      rmPerLitre != null;
}

class CostEstimationEvidence {
  const CostEstimationEvidence({
    required this.routeId,
    required this.referenceDate,
    required this.periodStart,
    required this.periodEnd,
    required this.network,
    required this.scheduledService,
    required this.dieselPrice,
    required this.unavailableInputs,
  });

  final String routeId;
  final DateTime referenceDate;
  final DateTime periodStart;
  final DateTime periodEnd;
  final AiRouteNetworkEvidence network;
  final ScheduledServiceEvidence scheduledService;
  final DieselPriceEvidence dieselPrice;
  final Set<UnavailableCostInput> unavailableInputs;
}
