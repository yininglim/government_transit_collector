import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_calculator.dart';
import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_calculator.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

abstract interface class OperationalEvidenceRepository {
  Future<AiOperationalEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  });
}

class DefaultOperationalEvidenceRepository
    implements OperationalEvidenceRepository {
  DefaultOperationalEvidenceRepository({
    PeakOperationCalculator? peakOperationCalculator,
    RoutePerformanceRepository? routePerformanceRepository,
    RoutePerformanceCalculator? routePerformanceCalculator,
  }) : _peakOperationCalculator =
           peakOperationCalculator ?? const PeakOperationCalculator(),
       _routePerformanceRepository =
           routePerformanceRepository ?? DefaultRoutePerformanceRepository(),
       _routePerformanceCalculator =
           routePerformanceCalculator ?? const RoutePerformanceCalculator();

  final PeakOperationCalculator _peakOperationCalculator;
  final RoutePerformanceRepository _routePerformanceRepository;
  final RoutePerformanceCalculator _routePerformanceCalculator;
  Future<List<RoutePerformanceRoute>>? _routesFuture;

  @override
  Future<AiOperationalEvidence> loadEvidence({
    required String routeId,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    try {
      final results = await Future.wait([
        _loadRoutes(),
        _routePerformanceRepository.loadRoutePerformance(
          routeId: routeId,
          startUtc: startUtc,
          endExclusiveUtc: endExclusiveUtc,
        ),
      ]);
      final routes = results[0] as List<RoutePerformanceRoute>;
      final route = routes.where((item) => item.routeId == routeId).firstOrNull;
      if (route == null) {
        throw const OperationalEvidenceReadException(
          'The selected route is not available.',
        );
      }
      final routePerformanceData = results[1] as RoutePerformanceData;
      final peakObservations = routePerformanceData.observations
          .map(
            (observation) => PeakOperationObservation(
              routeId: observation.routeId,
              tripId: observation.tripId,
              vehicleId: observation.vehicleId,
              recordedAt: observation.recordedAt,
            ),
          )
          .toList(growable: false);
      final peakSummary = _peakOperationCalculator.calculate(
        observations: peakObservations,
        periodStart: startUtc,
        periodEnd: endExclusiveUtc,
        routeId: routeId,
      );
      final routePerformanceSummary = _routePerformanceCalculator.calculate(
        routePerformanceData,
      );
      return AiOperationalEvidence(
        route: route,
        periodStart: startUtc,
        periodEnd: endExclusiveUtc,
        peakOperationSummary: peakSummary,
        routePerformanceSummary: routePerformanceSummary,
      );
    } on OperationalEvidenceReadException {
      rethrow;
    } on Object {
      throw const OperationalEvidenceReadException(
        'Unable to load operational evidence.',
      );
    }
  }

  Future<List<RoutePerformanceRoute>> _loadRoutes() {
    final existing = _routesFuture;
    if (existing != null) return existing;
    final future = _routePerformanceRepository.loadRoutes();
    _routesFuture = future;
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (identical(_routesFuture, future)) _routesFuture = null;
      },
    );
    return future;
  }
}

class OperationalEvidenceReadException implements Exception {
  const OperationalEvidenceReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
