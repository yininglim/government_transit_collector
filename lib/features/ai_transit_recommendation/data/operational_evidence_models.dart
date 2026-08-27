import 'package:government_transit_collector/features/peak_operation/data/peak_operation_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

class AiOperationalEvidence {
  const AiOperationalEvidence({
    required this.route,
    required this.periodStart,
    required this.periodEnd,
    required this.peakOperationSummary,
    required this.routePerformanceSummary,
  });

  final RoutePerformanceRoute route;
  final DateTime periodStart;
  final DateTime periodEnd;
  final PeakOperationSummary peakOperationSummary;
  final RoutePerformanceSummary routePerformanceSummary;
}
