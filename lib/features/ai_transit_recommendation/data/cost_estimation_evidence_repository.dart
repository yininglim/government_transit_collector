import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_estimation_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_price_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_network_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_repository.dart';

abstract interface class CostEstimationEvidenceRepository {
  Future<CostEstimationEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  });
}

class DefaultCostEstimationEvidenceRepository
    implements CostEstimationEvidenceRepository {
  DefaultCostEstimationEvidenceRepository({
    RouteNetworkEvidenceRepository? routeNetworkRepository,
    ScheduledServiceEvidenceRepository? scheduledServiceRepository,
    FuelPriceRepository? fuelPriceRepository,
  }) : _routeNetworkRepository =
           routeNetworkRepository ?? DefaultRouteNetworkEvidenceRepository(),
       _scheduledServiceRepository =
           scheduledServiceRepository ??
           DefaultScheduledServiceEvidenceRepository(),
       _fuelPriceRepository =
           fuelPriceRepository ?? DefaultFuelPriceRepository();

  final RouteNetworkEvidenceRepository _routeNetworkRepository;
  final ScheduledServiceEvidenceRepository _scheduledServiceRepository;
  final FuelPriceRepository _fuelPriceRepository;

  @override
  Future<CostEstimationEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
    required DateTime referenceDate,
  }) async {
    if (!endExclusiveUtc.isAfter(startUtc)) {
      throw const CostEstimationEvidenceReadException(
        'The analysis period is invalid.',
      );
    }
    try {
      final results = await Future.wait([
        _routeNetworkRepository.loadRoute(routeId),
        _scheduledServiceRepository.loadEvidence(
          routeId: routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        ),
        _fuelPriceRepository.loadDieselPrice(referenceDate),
      ]);
      return CostEstimationEvidence(
        routeId: routeId,
        referenceDate: DateTime(
          referenceDate.year,
          referenceDate.month,
          referenceDate.day,
        ),
        periodStart: startUtc,
        periodEnd: endExclusiveUtc,
        network: results[0] as AiRouteNetworkEvidence,
        scheduledService: results[1] as ScheduledServiceEvidence,
        dieselPrice: results[2] as DieselPriceEvidence,
        unavailableInputs: const {
          UnavailableCostInput.busFuelConsumption,
          UnavailableCostInput.driverStaffCost,
          UnavailableCostInput.maintenanceCost,
          UnavailableCostInput.busAcquisitionCost,
          UnavailableCostInput.busStopConstructionCost,
          UnavailableCostInput.operatingCostPerKilometre,
          UnavailableCostInput.operatingCostPerHour,
        },
      );
    } on CostEstimationEvidenceReadException {
      rethrow;
    } on Object {
      throw const CostEstimationEvidenceReadException(
        'Unable to load cost estimation evidence.',
      );
    }
  }
}

class CostEstimationEvidenceReadException implements Exception {
  const CostEstimationEvidenceReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
