import 'dart:async';

import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/cost_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_dashboard_coordinator.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/bus_frequency_recommendation_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/cost_estimation_report_page.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/presentation/route_bus_stop_recommendation_page.dart';

class AiRecommendationDashboardPage extends StatefulWidget {
  const AiRecommendationDashboardPage({
    this.busFrequencyPageBuilder,
    this.routeStopPageBuilder,
    this.costPageBuilder,
    this.routeStopCoordinator,
    this.now,
    this.preloadRouteStops = true,
    super.key,
  });

  final Widget Function(BusFrequencyDashboardSession session)?
  busFrequencyPageBuilder;
  final Widget Function(RouteStopDashboardSession session)?
  routeStopPageBuilder;
  final Widget Function(CostDashboardSession session)? costPageBuilder;
  final RouteStopDashboardCoordinator? routeStopCoordinator;
  final DateTime Function()? now;
  final bool preloadRouteStops;

  @override
  State<AiRecommendationDashboardPage> createState() =>
      _AiRecommendationDashboardPageState();
}

class _AiRecommendationDashboardPageState
    extends State<AiRecommendationDashboardPage> {
  final _busFrequencySession = BusFrequencyDashboardSession();
  final _routeStopSession = RouteStopDashboardSession();
  final _costSession = CostDashboardSession();
  RouteStopDashboardCoordinator? _routeStopCoordinator;

  RouteStopDashboardCoordinator get _routeCoordinator =>
      _routeStopCoordinator ??= RouteStopDashboardCoordinator();

  @override
  void initState() {
    super.initState();
    _routeStopCoordinator = widget.routeStopCoordinator;
    if (widget.preloadRouteStops) {
      final period = routeStopAnalysisPeriod(now: widget.now);
      unawaited(
        _routeCoordinator.prepareSession(
          session: _routeStopSession,
          startUtc: period.startUtc,
          endExclusiveUtc: period.endUtc,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Recommendation Dashboard')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'AI Transit Recommendation',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Select a recommendation area to continue.'),
            const SizedBox(height: 32),
            _RecommendationSection(
              icon: Icons.schedule,
              title: 'Bus Frequency Recommendation',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      widget.busFrequencyPageBuilder?.call(
                        _busFrequencySession,
                      ) ??
                      BusFrequencyRecommendationPage(
                        session: _busFrequencySession,
                      ),
                ),
              ),
            ),
            _RecommendationSection(
              icon: Icons.alt_route,
              title: 'Route & Bus Stop Recommendation',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      widget.routeStopPageBuilder?.call(_routeStopSession) ??
                      RouteBusStopRecommendationPage(
                        session: _routeStopSession,
                        coordinator: _routeCoordinator,
                        now: widget.now,
                      ),
                ),
              ),
            ),
            _RecommendationSection(
              icon: Icons.request_quote_outlined,
              title: 'Cost Estimation Report',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      widget.costPageBuilder?.call(_costSession) ??
                      CostEstimationReportPage(session: _costSession),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationSection extends StatelessWidget {
  const _RecommendationSection({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
