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
    this.busFrequencyCoordinator,
    this.routeStopCoordinator,
    this.costCoordinator,
    this.now,
    this.preloadBusFrequency = true,
    this.preloadRouteStops = true,
    super.key,
  });

  final Widget Function(BusFrequencyDashboardSession session)?
  busFrequencyPageBuilder;
  final Widget Function(RouteStopDashboardSession session)?
  routeStopPageBuilder;
  final Widget Function(CostDashboardSession session)? costPageBuilder;
  final BusFrequencyDashboardCoordinator? busFrequencyCoordinator;
  final RouteStopDashboardCoordinator? routeStopCoordinator;
  final CostDashboardCoordinator? costCoordinator;
  final DateTime Function()? now;
  final bool preloadBusFrequency;
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
  BusFrequencyDashboardCoordinator? _busFrequencyCoordinator;
  RouteStopDashboardCoordinator? _routeStopCoordinator;
  CostDashboardCoordinator? _costCoordinator;
  late final _RecommendationPreparationScheduler _preparationScheduler;

  BusFrequencyDashboardCoordinator get _frequencyCoordinator =>
      _busFrequencyCoordinator ??= BusFrequencyDashboardCoordinator();

  RouteStopDashboardCoordinator get _routeCoordinator =>
      _routeStopCoordinator ??= RouteStopDashboardCoordinator();

  CostDashboardCoordinator get _costCoordinatorValue =>
      _costCoordinator ??= CostDashboardCoordinator();

  @override
  void initState() {
    super.initState();
    _busFrequencyCoordinator = widget.busFrequencyCoordinator;
    _routeStopCoordinator = widget.routeStopCoordinator;
    _costCoordinator = widget.costCoordinator;
    _preparationScheduler = _RecommendationPreparationScheduler(
      preparations: {
        _RecommendationFeature.busFrequency: () async {
          final period = busFrequencyAnalysisPeriod(now: widget.now);
          await _frequencyCoordinator.prepareSession(
            session: _busFrequencySession,
            startUtc: period.startUtc,
            endExclusiveUtc: period.endUtc,
          );
        },
        _RecommendationFeature.routeStops: () async {
          final period = routeStopAnalysisPeriod(now: widget.now);
          await _routeCoordinator.prepareSession(
            session: _routeStopSession,
            startUtc: period.startUtc,
            endExclusiveUtc: period.endUtc,
          );
        },
        _RecommendationFeature.cost: () async {
          final period = costAnalysisPeriod(now: widget.now);
          await _costCoordinatorValue.prepareSession(
            session: _costSession,
            startUtc: period.startUtc,
            endExclusiveUtc: period.endUtc,
            referenceDate: period.referenceDate,
          );
        },
      },
      prepared: {
        _RecommendationFeature.busFrequency: () =>
            _busFrequencySession.screeningComplete &&
            _busFrequencySession.matchesPeriod(
              busFrequencyAnalysisPeriod(now: widget.now).startUtc,
              busFrequencyAnalysisPeriod(now: widget.now).endUtc,
            ),
        _RecommendationFeature.routeStops: () =>
            _routeStopSession.screeningComplete &&
            _routeStopSession.matchesPeriod(
              routeStopAnalysisPeriod(now: widget.now).startUtc,
              routeStopAnalysisPeriod(now: widget.now).endUtc,
            ),
        _RecommendationFeature.cost: () {
          final period = costAnalysisPeriod(now: widget.now);
          return _costSession.screeningComplete &&
              _costSession.matchesPeriod(
                period.startUtc,
                period.endUtc,
                period.referenceDate,
              );
        },
      },
    );
    if (widget.preloadBusFrequency) {
      unawaited(_preparationScheduler.enqueue(_RecommendationFeature.busFrequency));
    }
    if (widget.preloadRouteStops) {
      unawaited(_preparationScheduler.enqueue(_RecommendationFeature.routeStops));
    }
    unawaited(_preparationScheduler.enqueue(_RecommendationFeature.cost));
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
                        coordinator: _frequencyCoordinator,
                        now: widget.now,
                        preparationScheduler: () => _preparationScheduler.request(
                          _RecommendationFeature.busFrequency,
                        ),
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
                        preparationScheduler: () => _preparationScheduler.request(
                          _RecommendationFeature.routeStops,
                        ),
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
                      CostEstimationReportPage(
                        session: _costSession,
                        coordinator: _costCoordinatorValue,
                        preparationScheduler: () =>
                            _preparationScheduler.request(
                              _RecommendationFeature.cost,
                            ),
                        busFrequencySession: _busFrequencySession,
                        now: widget.now,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _RecommendationFeature { busFrequency, routeStops, cost }

class _RecommendationPreparationScheduler {
  _RecommendationPreparationScheduler({
    required this.preparations,
    required this.prepared,
  });

  final Map<_RecommendationFeature, Future<void> Function()> preparations;
  final Map<_RecommendationFeature, bool Function()> prepared;
  final List<_RecommendationFeature> _queue = [];
  final Map<_RecommendationFeature, Completer<void>> _pending = {};
  _RecommendationFeature? _running;

  Future<void> enqueue(_RecommendationFeature feature) {
    return _schedule(feature, userPriority: false);
  }

  Future<void> request(_RecommendationFeature feature) {
    return _schedule(feature, userPriority: true);
  }

  Future<void> _schedule(
    _RecommendationFeature feature, {
    required bool userPriority,
  }) {
    if (prepared[feature]!()) return Future<void>.value();
    final existing = _pending[feature];
    if (existing != null) {
      if (userPriority && _running != feature) {
        _queue.remove(feature);
        _queue.insert(0, feature);
      }
      return existing.future;
    }
    final completer = Completer<void>();
    _pending[feature] = completer;
    if (userPriority) {
      _queue.insert(0, feature);
    } else {
      _queue.add(feature);
    }
    _pump();
    return completer.future;
  }

  void _pump() {
    if (_running != null || _queue.isEmpty) return;
    final feature = _queue.removeAt(0);
    final completer = _pending[feature];
    if (completer == null) {
      _pump();
      return;
    }
    _running = feature;
    () async {
      try {
        await preparations[feature]!();
      } on Object {}
      if (!completer.isCompleted) completer.complete();
      _pending.remove(feature);
      _running = null;
      _pump();
    }();
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
