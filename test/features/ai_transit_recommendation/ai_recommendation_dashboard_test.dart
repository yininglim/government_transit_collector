import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_recommendation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/ai_recommendation_dashboard_page.dart';

void main() {
  testWidgets('6C preload settles before 6D preload starts', (tester) async {
    final events = <String>[];
    final busGate = Completer<void>();
    final routeCoordinator = RecordingRouteStopCoordinator(
      events: events,
    );
    final busCoordinator = RecordingBusFrequencyCoordinator(
      events: events,
      gate: busGate,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AiRecommendationDashboardPage(
          busFrequencyCoordinator: busCoordinator,
          routeStopCoordinator: routeCoordinator,
          now: () => DateTime.utc(2026, 8, 31, 4),
        ),
      ),
    );
    await tester.pump();
    expect(events, ['6C started']);
    expect(busCoordinator.prepareCalls, 1);
    busGate.complete();
    await tester.pump();
    await Future<void>.delayed(Duration.zero);
    expect(events, ['6C started', '6C settled', '6D started']);
    expect(busCoordinator.analysisCalls, 0);
  });

  testWidgets('dashboard preloads 6C and shares its session without Gemini', (
    tester,
  ) async {
    final coordinator = RecordingBusFrequencyCoordinator();
    BusFrequencyDashboardSession? openedSession;
    await tester.pumpWidget(
      MaterialApp(
        home: AiRecommendationDashboardPage(
          preloadRouteStops: false,
          busFrequencyCoordinator: coordinator,
          busFrequencyPageBuilder: (session) {
            openedSession = session;
            return const Scaffold(body: Text('Bus Session'));
          },
          now: () => DateTime.utc(2026, 8, 31, 4),
        ),
      ),
    );
    await tester.pump();
    expect(coordinator.prepareCalls, 1);
    expect(coordinator.analysisCalls, 0);
    await tester.tap(find.text('Bus Frequency Recommendation'));
    await tester.pumpAndSettle();
    expect(openedSession, same(coordinator.preparedSession));
    expect(coordinator.analysisCalls, 0);
  });

  testWidgets('dashboard retains separate feature sessions until disposed', (
    tester,
  ) async {
    final busSessions = <BusFrequencyDashboardSession>[];
    final costSessions = <CostDashboardSession>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AiRecommendationDashboardPage(
          preloadRouteStops: false,
          preloadBusFrequency: false,
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
          preloadBusFrequency: false,
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

class RecordingBusFrequencyCoordinator
    extends BusFrequencyDashboardCoordinator {
  RecordingBusFrequencyCoordinator({this.events, this.gate});

  final List<String>? events;
  final Completer<void>? gate;
  int prepareCalls = 0;
  int analysisCalls = 0;
  BusFrequencyDashboardSession? preparedSession;

  @override
  Future<void> prepareSession({
    required BusFrequencyDashboardSession session,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    prepareCalls++;
    events?.add('6C started');
    preparedSession = session;
    if (gate != null) await gate!.future;
    events?.add('6C settled');
  }

  @override
  Future<BusFrequencyRecommendationResult> analyse({
    required List<BusFrequencyDashboardCandidate> candidates,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) {
    analysisCalls++;
    throw StateError('Gemini generation must not run during preload');
  }
}

class RecordingRouteStopCoordinator extends RouteStopDashboardCoordinator {
  RecordingRouteStopCoordinator({required this.events});

  final List<String> events;

  @override
  Future<void> prepareSession({
    required RouteStopDashboardSession session,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    events.add('6D started');
    events.add('6D settled');
  }
}
