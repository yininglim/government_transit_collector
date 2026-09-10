import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/ai_recommendation_dashboard_page.dart';

void main() {
  testWidgets('dashboard retains separate feature sessions until disposed', (
    tester,
  ) async {
    final busSessions = <BusFrequencyDashboardSession>[];
    final costSessions = <CostDashboardSession>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AiRecommendationDashboardPage(
          preloadRouteStops: false,
          busFrequencyPageBuilder: (session) {
            busSessions.add(session);
            return const Scaffold(body: Text('Bus Session'));
          },
          costPageBuilder: (session) {
            costSessions.add(session);
            return const Scaffold(body: Text('Cost Session'));
          },
        ),
      ),
    );

    await tester.tap(find.text('Bus Frequency Recommendation'));
    await tester.pumpAndSettle();
    final firstBusSession = busSessions.single;

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cost Estimation Report'));
    await tester.pumpAndSettle();
    final costSession = costSessions.single;

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bus Frequency Recommendation'));
    await tester.pumpAndSettle();
    final reopenedBusSession = busSessions.last;
    expect(reopenedBusSession, same(firstBusSession));
    expect(reopenedBusSession, isNot(same(costSession)));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: AiRecommendationDashboardPage(
          preloadRouteStops: false,
          busFrequencyPageBuilder: (session) {
            busSessions.add(session);
            return const Scaffold(body: Text('Bus Session'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bus Frequency Recommendation'));
    await tester.pumpAndSettle();
    final newDashboardSession = busSessions.last;
    expect(newDashboardSession, isNot(same(firstBusSession)));
  });
}
