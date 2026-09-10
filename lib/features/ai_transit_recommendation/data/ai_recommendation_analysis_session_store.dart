import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_dashboard_coordinator.dart';

class AiRecommendationAnalysisSessionStore {
  AiRecommendationAnalysisSessionStore({required this.adminUserId});

  final String adminUserId;
  final BusFrequencyDashboardSession busFrequency =
      BusFrequencyDashboardSession();
  final RouteStopDashboardSession routeStop = RouteStopDashboardSession();
  final CostDashboardSession cost = CostDashboardSession();

  bool belongsTo(String userId) => adminUserId == userId;

  void clear() {
    busFrequency.clear();
    routeStop.clear();
    cost.clear();
  }
}
