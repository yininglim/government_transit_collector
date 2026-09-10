import 'dart:async';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/recommendation_management_repository.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_repository.dart';

class FakeManagementRepository implements RecommendationManagementRepository {
  FakeManagementRepository({this.rows = const [], this.pending});
  final List<Map<String, dynamic>> rows;
  final Completer<List<SavedRecommendation>>? pending;
  int loads = 0;
  @override
  Future<List<SavedRecommendation>> loadSavedRecommendations() async {
    loads++;
    return pending == null ? rows.map(SavedRecommendation.fromJson).toList() : await pending!.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected repository operation: ${invocation.memberName}');
}

const testRoute = RoutePerformanceRoute(routeId: 'route', shortName: 'R', longName: 'Route');

class FakeRoutesRepository implements RoutePerformanceRepository {
  @override
  Future<List<RoutePerformanceRoute>> loadRoutes() async => [testRoute];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Analysis must not run');
}

class FakeCostEvidence implements FuelCostCalculationEvidence {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Evidence must not be read');
}
