import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/direct_trip_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_search_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_validation.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/stop_selection_page.dart';

class DepartureRecommendationPage extends StatefulWidget {
  const DepartureRecommendationPage({
    required this.stopRepository,
    required this.tripRepository,
    required this.recentSearchRepository,
    super.key,
  });

  final DepartureStopRepository stopRepository;
  final DirectTripRepository tripRepository;
  final RecentSearchRepository recentSearchRepository;

  @override
  State<DepartureRecommendationPage> createState() =>
      _DepartureRecommendationPageState();
}

class _DepartureRecommendationPageState
    extends State<DepartureRecommendationPage> {
  DepartureStop? _origin;
  DepartureStop? _destination;
  String? _validationMessage;
  List<DirectRouteResult>? _routeResults;
  String? _searchError;
  bool _searching = false;
  List<RecentJourneySearch>? _recentSearches;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    setState(() {
      _recentSearches = null;
      _historyError = null;
    });
    try {
      final searches = await widget.recentSearchRepository.getRecentSearches();
      if (!mounted) return;
      setState(() => _recentSearches = searches);
    } on Object {
      if (!mounted) return;
      setState(() => _historyError = 'Unable to load recent searches.');
    }
  }

  Future<void> _selectOrigin() async {
    final stop = await Navigator.of(context).push<DepartureStop>(
      MaterialPageRoute(
        builder: (_) => StopSelectionPage(
          title: 'Select origin stop',
          repository: widget.stopRepository,
          excludedStopId: _destination?.id,
        ),
      ),
    );
    if (!mounted || stop == null) return;
    setState(() {
      _origin = stop;
      _resetSearchState();
    });
  }

  Future<void> _selectDestination() async {
    final stop = await Navigator.of(context).push<DepartureStop>(
      MaterialPageRoute(
        builder: (_) => StopSelectionPage(
          title: 'Select destination stop',
          repository: widget.stopRepository,
          excludedStopId: _origin?.id,
        ),
      ),
    );
    if (!mounted || stop == null) return;
    setState(() {
      _destination = stop;
      _resetSearchState();
    });
  }

  void _resetSearchState() {
    _validationMessage = null;
    _routeResults = null;
    _searchError = null;
  }

  Future<void> _search() async {
    if (_searching) return;
    final validationMessage = validateDepartureStops(
      origin: _origin,
      destination: _destination,
    );
    if (validationMessage != null) {
      setState(() {
        _validationMessage = validationMessage;
        _routeResults = null;
        _searchError = null;
      });
      return;
    }

    final origin = _origin!;
    final destination = _destination!;
    setState(() {
      _searching = true;
      _validationMessage = null;
      _routeResults = null;
      _searchError = null;
    });
    try {
      final results = await widget.tripRepository.findDirectRoutes(
        originStopId: origin.id,
        destinationStopId: destination.id,
      );
      if (!mounted) return;
      setState(() {
        _routeResults = results;
        _searching = false;
      });
      await _saveRecentSearch(origin, destination);
    } on DirectTripReadException catch (error) {
      if (!mounted) return;
      setState(() {
        _searchError = error.message;
        _searching = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _searchError = 'Unable to find direct routes.';
        _searching = false;
      });
    }
  }

  Future<void> _saveRecentSearch(
    DepartureStop origin,
    DepartureStop destination,
  ) async {
    try {
      await widget.recentSearchRepository.saveRecentSearch(
        RecentJourneySearch(
          originStopId: origin.id,
          originStopName: origin.name,
          destinationStopId: destination.id,
          destinationStopName: destination.name,
          searchedAt: DateTime.now().toUtc(),
        ),
      );
      await _loadRecentSearches();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Route search completed, but recent history was not saved.',
          ),
        ),
      );
    }
  }

  void _restoreRecentSearch(RecentJourneySearch search) {
    setState(() {
      _origin = DepartureStop(
        id: search.originStopId,
        name: search.originStopName,
      );
      _destination = DepartureStop(
        id: search.destinationStopId,
        name: search.destinationStopName,
      );
      _resetSearchState();
    });
  }

  Future<void> _clearRecentSearches() async {
    try {
      await widget.recentSearchRepository.clearRecentSearches();
      if (!mounted) return;
      setState(() {
        _recentSearches = const [];
        _historyError = null;
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to clear recent searches.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Departure Recommendation')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth >= 700 ? 32.0 : 16.0;
            return SingleChildScrollView(
              key: const Key('departure-page-scroll'),
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Where would you like to go?',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text('Select an origin and destination stop.'),
                      const SizedBox(height: 24),
                      _buildStopFields(constraints.maxWidth),
                      if (_validationMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _validationMessage!,
                          key: const Key('validation-message'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        key: const Key('journey-search-button'),
                        onPressed: _searching ? null : _search,
                        icon: _searching
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search),
                        label: Text(_searching ? 'Searching…' : 'Search'),
                      ),
                      const SizedBox(height: 28),
                      _buildResults(),
                      const SizedBox(height: 28),
                      _buildRecentSearches(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStopFields(double width) {
    final origin = _StopField(
      key: const Key('origin-field'),
      label: 'Origin / From stop',
      icon: Icons.trip_origin,
      stop: _origin,
      onTap: _searching ? null : _selectOrigin,
    );
    final destination = _StopField(
      key: const Key('destination-field'),
      label: 'Destination / To stop',
      icon: Icons.location_on_outlined,
      stop: _destination,
      onTap: _searching ? null : _selectDestination,
    );
    if (width >= 700) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: origin),
          const SizedBox(width: 16),
          Expanded(child: destination),
        ],
      );
    }
    return Column(children: [origin, const SizedBox(height: 12), destination]);
  }

  Widget _buildResults() {
    if (_searching) {
      return const _SectionMessage(
        key: Key('route-loading'),
        icon: Icons.route,
        message: 'Finding direct routes…',
        showProgress: true,
      );
    }
    if (_searchError != null) {
      return _SectionMessage(
        key: const Key('route-error'),
        icon: Icons.error_outline,
        message: _searchError!,
        actionLabel: 'Retry',
        onAction: _search,
      );
    }
    final results = _routeResults;
    if (results == null) return const SizedBox.shrink();
    return Column(
      key: const Key('direct-route-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Available Direct Routes',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (results.isEmpty)
          const _SectionMessage(
            key: Key('no-direct-routes'),
            icon: Icons.route_outlined,
            message: 'No direct bus route was found between these stops.',
          )
        else
          ...results.map(_DirectRouteCard.new),
      ],
    );
  }

  Widget _buildRecentSearches() {
    return Column(
      key: const Key('recent-searches-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Searches',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (_recentSearches?.isNotEmpty == true)
              TextButton(
                key: const Key('clear-recent-searches'),
                onPressed: _clearRecentSearches,
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_historyError != null)
          _SectionMessage(
            icon: Icons.error_outline,
            message: _historyError!,
            actionLabel: 'Retry',
            onAction: _loadRecentSearches,
          )
        else if (_recentSearches == null)
          const Center(child: CircularProgressIndicator())
        else if (_recentSearches!.isEmpty)
          const Text('No recent searches yet.')
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: _recentSearches!
                  .map(
                    (search) => ListTile(
                      key: Key(
                        'recent-${search.originStopId}-${search.destinationStopId}',
                      ),
                      leading: const Icon(Icons.history),
                      title: Text(
                        '${search.originStopName} → ${search.destinationStopName}',
                      ),
                      trailing: const Icon(Icons.north_west),
                      onTap: () => _restoreRecentSearch(search),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }
}

class _DirectRouteCard extends StatelessWidget {
  const _DirectRouteCard(this.route);

  final DirectRouteResult route;

  @override
  Widget build(BuildContext context) {
    final shortName = route.routeShortName?.trim();
    final longName = route.routeLongName?.trim();
    final headsign = route.tripHeadsign?.trim();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.directions_bus),
        title: Text(
          shortName?.isNotEmpty == true
              ? 'Route $shortName'
              : 'Route ${route.routeId}',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (longName?.isNotEmpty == true) Text(longName!),
            if (headsign?.isNotEmpty == true) Text('Towards $headsign'),
            Text(
              '${route.matchingTripCount} matching '
              '${route.matchingTripCount == 1 ? 'trip' : 'trips'}',
            ),
          ],
        ),
      ),
    );
  }
}

class _StopField extends StatelessWidget {
  const _StopField({
    required this.label,
    required this.icon,
    required this.stop,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final DepartureStop? stop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(stop?.name ?? 'Tap to select a stop'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage({
    required this.icon,
    required this.message,
    this.showProgress = false,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String message;
  final bool showProgress;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (showProgress)
              const CircularProgressIndicator()
            else
              Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
