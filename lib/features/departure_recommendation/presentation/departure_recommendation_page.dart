import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/direct_trip_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_journey_search.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/recent_search_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/transfer_journey_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_validation.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/stop_selection_page.dart';

class DepartureRecommendationPage extends StatefulWidget {
  const DepartureRecommendationPage({
    required this.stopRepository,
    required this.tripRepository,
    required this.transferRepository,
    required this.recentSearchRepository,
    super.key,
  });

  final DepartureStopRepository stopRepository;
  final DirectTripRepository tripRepository;
  final TransferJourneyRepository transferRepository;
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
  List<OneTransferJourneyResult>? _transferResults;
  String? _directError;
  String? _transferError;
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
    _transferResults = null;
    _directError = null;
    _transferError = null;
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
        _transferResults = null;
        _directError = null;
        _transferError = null;
      });
      return;
    }

    final origin = _origin!;
    final destination = _destination!;
    setState(() {
      _searching = true;
      _validationMessage = null;
      _routeResults = null;
      _transferResults = null;
      _directError = null;
      _transferError = null;
    });

    final directFuture = widget.tripRepository.findDirectRoutes(
      originStopId: origin.id,
      destinationStopId: destination.id,
    );
    final transferFuture = widget.transferRepository.findOneTransferJourneys(
      originStopId: origin.id,
      destinationStopId: destination.id,
    );
    List<DirectRouteResult>? directResults;
    List<OneTransferJourneyResult>? transferResults;
    String? directError;
    String? transferError;
    try {
      directResults = await directFuture;
    } on DirectTripReadException catch (error) {
      directError = error.message;
    } on Object {
      directError = 'Unable to find direct routes.';
    }
    try {
      transferResults = await transferFuture;
    } on TransferJourneyReadException catch (error) {
      transferError = error.message;
    } on Object {
      transferError = 'Unable to find one-transfer routes.';
    }
    if (!mounted) return;
    setState(() {
      _routeResults = directResults;
      _transferResults = transferResults;
      _directError = directError;
      _transferError = transferError;
      _searching = false;
    });
    if (directError == null || transferError == null) {
      await _saveRecentSearch(origin, destination);
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
        message: 'Finding direct and one-transfer routes…',
        showProgress: true,
      );
    }
    final directResults = _routeResults;
    final transferResults = _transferResults;
    if (directResults == null &&
        transferResults == null &&
        _directError == null &&
        _transferError == null) {
      return const SizedBox.shrink();
    }
    final hasDirect = directResults?.isNotEmpty == true;
    final hasTransfer = transferResults?.isNotEmpty == true;
    final hasAnyJourney = hasDirect || hasTransfer;
    return Column(
      key: const Key('journey-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hasAnyJourney && _directError == null && _transferError == null)
          const _SectionMessage(
            key: Key('no-journeys'),
            icon: Icons.route_outlined,
            message:
                'No direct or one-transfer journey was found between these stops.',
          )
        else ...[
          if (_directError != null)
            _SectionMessage(
              key: const Key('direct-route-error'),
              icon: Icons.error_outline,
              message: _directError!,
              actionLabel: 'Retry',
              onAction: _search,
            )
          else if (hasDirect) ...[
            Text(
              'Direct Routes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...directResults!.map(
              (route) => _DirectRouteCard(
                route: route,
                originStopName: _origin!.name,
                destinationStopName: _destination!.name,
              ),
            ),
          ],
          if ((hasDirect || _directError != null) &&
              (hasTransfer || _transferError != null))
            const SizedBox(height: 24),
          if (_transferError != null)
            _SectionMessage(
              key: const Key('transfer-route-error'),
              icon: Icons.error_outline,
              message: _transferError!,
              actionLabel: 'Retry',
              onAction: _search,
            )
          else if (hasTransfer) ...[
            Text(
              '1-Transfer Routes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...transferResults!.map(
              (journey) => _TransferRouteCard(
                journey: journey,
                originStopName: _origin!.name,
                destinationStopName: _destination!.name,
              ),
            ),
          ],
        ],
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
  const _DirectRouteCard({
    required this.route,
    required this.originStopName,
    required this.destinationStopName,
  });

  final DirectRouteResult route;
  final String originStopName;
  final String destinationStopName;

  @override
  Widget build(BuildContext context) {
    final shortName = route.routeShortName?.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shortName?.isNotEmpty == true ? shortName! : route.routeId,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('$originStopName → $destinationStopName'),
            const SizedBox(height: 10),
            const _JourneySummary(label: 'Direct • No transfer'),
          ],
        ),
      ),
    );
  }
}

class _TransferRouteCard extends StatelessWidget {
  const _TransferRouteCard({
    required this.journey,
    required this.originStopName,
    required this.destinationStopName,
  });

  final OneTransferJourneyResult journey;
  final String originStopName;
  final String destinationStopName;

  String _routeLabel(TransferJourneyLeg leg) {
    final shortName = leg.routeShortName?.trim();
    return shortName?.isNotEmpty == true ? shortName! : leg.routeId;
  }

  @override
  Widget build(BuildContext context) {
    final firstRoute = _routeLabel(journey.firstLeg);
    final secondRoute = _routeLabel(journey.secondLeg);
    return Card(
      key: Key(
        'transfer-${journey.firstLeg.routeId}-'
        '${journey.transferStopId}-${journey.secondLeg.routeId}',
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$firstRoute → $secondRoute',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            _JourneyPoint(icon: Icons.trip_origin, label: originStopName),
            _RouteConnector(routeLabel: firstRoute),
            _JourneyPoint(
              icon: Icons.sync_alt,
              label: 'Transfer at ${journey.transferStopName}',
            ),
            _RouteConnector(routeLabel: secondRoute),
            _JourneyPoint(
              icon: Icons.location_on_outlined,
              label: destinationStopName,
            ),
            const SizedBox(height: 12),
            const _JourneySummary(label: '2 buses • 1 transfer'),
          ],
        ),
      ),
    );
  }
}

class _JourneyPoint extends StatelessWidget {
  const _JourneyPoint({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    );
  }
}

class _RouteConnector extends StatelessWidget {
  const _RouteConnector({required this.routeLabel});

  final String routeLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 4, bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.arrow_downward, size: 16),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              routeLabel,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneySummary extends StatelessWidget {
  const _JourneySummary({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
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
