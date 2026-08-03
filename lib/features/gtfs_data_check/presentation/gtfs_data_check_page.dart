import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/gtfs_data_check/data/gtfs_repository.dart';

class GtfsDataCheckPage extends StatefulWidget {
  const GtfsDataCheckPage({required this.repository, super.key});

  final GtfsRepository repository;

  @override
  State<GtfsDataCheckPage> createState() => _GtfsDataCheckPageState();
}

class _GtfsDataCheckPageState extends State<GtfsDataCheckPage> {
  final _searchController = TextEditingController();
  List<GtfsRoute>? _routes;
  GtfsRoute? _selectedRoute;
  List<GtfsStop>? _stops;
  String? _routeError;
  String? _stopError;
  bool _loadingStops = false;
  int _stopRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _routes = null;
      _routeError = null;
    });
    try {
      final routes = await widget.repository.fetchRoutes();
      if (!mounted) return;
      setState(() => _routes = routes);
    } on GtfsReadException catch (error) {
      if (!mounted) return;
      setState(() => _routeError = error.message);
    }
  }

  Future<void> _selectRoute(GtfsRoute route) async {
    final requestId = ++_stopRequestId;
    setState(() {
      _selectedRoute = route;
      _stops = null;
      _stopError = null;
      _loadingStops = true;
    });
    try {
      final stops = await widget.repository.fetchStopsForRoute(route.id);
      if (!mounted || requestId != _stopRequestId) return;
      setState(() {
        _stops = stops;
        _loadingStops = false;
      });
    } on GtfsReadException catch (error) {
      if (!mounted || requestId != _stopRequestId) return;
      setState(() {
        _stopError = error.message;
        _loadingStops = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GTFS Data Check')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_routeError != null) {
      return _MessageState(
        icon: Icons.error_outline,
        message: _routeError!,
        actionLabel: 'Retry',
        onAction: _loadRoutes,
      );
    }
    final routes = _routes;
    if (routes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (routes.isEmpty) {
      return const _MessageState(
        icon: Icons.route_outlined,
        message: 'No GTFS routes were returned.',
      );
    }

    final query = _searchController.text;
    final filteredRoutes = routes
        .where((route) => route.matches(query))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${routes.length} routes returned',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Search routes',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 720) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildRouteList(filteredRoutes)),
                    const VerticalDivider(width: 24),
                    Expanded(child: _buildStopPanel()),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(child: _buildRouteList(filteredRoutes)),
                  const Divider(height: 24),
                  Expanded(child: _buildStopPanel()),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRouteList(List<GtfsRoute> routes) {
    if (routes.isEmpty) {
      return const _MessageState(
        icon: Icons.search_off,
        message: 'No routes match this search.',
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        itemCount: routes.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final route = routes[index];
          final selected = route.id == _selectedRoute?.id;
          return ListTile(
            selected: selected,
            leading: const Icon(Icons.route),
            title: Text(route.shortName?.trim().isNotEmpty == true
                ? route.shortName!
                : 'Route ${route.id}'),
            subtitle: Text(route.longName?.trim().isNotEmpty == true
                ? route.longName!
                : 'No long name'),
            trailing: selected ? const Icon(Icons.check_circle) : null,
            onTap: () => _selectRoute(route),
          );
        },
      ),
    );
  }

  Widget _buildStopPanel() {
    final route = _selectedRoute;
    if (route == null) {
      return const _MessageState(
        icon: Icons.touch_app_outlined,
        message: 'Select a route to check its stops.',
      );
    }
    if (_loadingStops) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_stopError != null) {
      return _MessageState(
        icon: Icons.error_outline,
        message: _stopError!,
        actionLabel: 'Retry',
        onAction: () => _selectRoute(route),
      );
    }
    final stops = _stops;
    if (stops == null || stops.isEmpty) {
      return const _MessageState(
        icon: Icons.not_listed_location_outlined,
        message: 'No stops were returned for this route.',
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Stops for ${route.displayName}\n'
              '${stops.length} shown (maximum ${GtfsRepository.displayedStopLimit})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: stops.length,
              itemBuilder: (context, index) {
                final stop = stops[index];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(child: Text('${stop.sequence}')),
                  title: Text(stop.name),
                  subtitle: Text(stop.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
