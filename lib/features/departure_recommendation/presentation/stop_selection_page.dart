import '../data/favourite_stop_repository.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/nearby_stop_repository.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location_service.dart';
import 'package:government_transit_collector/features/passenger_location/data/boarding_stop_distance.dart';

class StopSelectionPage extends StatefulWidget {
  const StopSelectionPage({
    required this.title,
    required this.repository,
    required this.excludedStopId,
    this.allowNearby = false,
    this.startNearby = false,
    this.initialRadius = 1000,
    this.locationService,
    this.nearbyRepository,
    this.availableStops,
    this.favouriteStopRepository,
    super.key,
  });

  final String title;
  final DepartureStopRepository repository;
  final String? excludedStopId;
  final bool allowNearby;
  final bool startNearby;
  final int initialRadius;
  final PassengerLocationService? locationService;
  final NearbyStopRepository? nearbyRepository;
  final List<DepartureStop>? availableStops;
  final FavouriteStopRepository? favouriteStopRepository;

  @override
  State<StopSelectionPage> createState() => _StopSelectionPageState();
}

class _StopSelectionPageState extends State<StopSelectionPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<DepartureStop>? _stops = const [];
  String? _error;
  int _requestId = 0;
  bool _nearby = false;
  bool _locating = false;
  late int _radius;
  List<NearbyStop> _nearbyStops = [];
  PassengerLocationResult? _locationResult;
  late final PassengerLocationService _locationService;

  late final _favouriteRepository =
      widget.favouriteStopRepository ?? FavouriteStopRepository.currentUser();
  List<DepartureStop>? _favourites;
  String? _favouriteError;
  bool _savingFavourite = false;
  bool _usingFavourite = false;
  int _favouriteRequest = 0;

  Future<void> _loadFavourites() async {
    final request = ++_favouriteRequest;
    try {
      final stops = await _favouriteRepository!.load();
      if (mounted && request == _favouriteRequest)
        setState(() {
          _favourites = stops;
          _favouriteError = null;
        });
    } on Object {
      if (mounted && request == _favouriteRequest)
        setState(() => _favouriteError = 'Unable to load favourite stops.');
    }
  }

  Future<void> _toggleFavourite(DepartureStop stop) async {
    if (_savingFavourite || _favourites == null) return;
    setState(() => _savingFavourite = true);
    try {
      if (_favourites!.any((item) => item.id == stop.id)) {
        await _favouriteRepository!.remove(stop.id);
      } else {
        await _favouriteRepository!.save(stop);
      }
    } on Object {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update favourite stop. Please try again.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _savingFavourite = false);
    }
  }

  Widget? _favouriteStar(DepartureStop stop) {
    if (_favouriteRepository == null) return null;
    final saved = _favourites?.any((item) => item.id == stop.id) == true;
    return IconButton(
      key: ValueKey('favourite-stop-${stop.id}'),
      tooltip: saved ? 'Remove favourite stop' : 'Favourite stop',
      onPressed: _savingFavourite || _favourites == null
          ? null
          : () => _toggleFavourite(stop),
      icon: Icon(
        saved ? Icons.star : Icons.star_border,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Future<void> _useFavourite(DepartureStop stop) async {
    if (_usingFavourite) return;
    setState(() => _usingFavourite = true);
    try {
      final available = widget.availableStops;
      final current = available == null
          ? await widget.repository.getStopById(stop.id)
          : available.where((item) => item.id == stop.id).firstOrNull;
      if (!mounted) return;
      if (current == null || current.id == widget.excludedStopId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This stop is no longer available for selection.'),
          ),
        );
        return;
      }
      Navigator.of(context).pop(current);
    } on Object {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load this stop. Please try again.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _usingFavourite = false);
    }
  }

  Widget _favouriteSection() => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Favourite Bus Stops',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_favouriteError != null)
            TextButton(
              onPressed: _loadFavourites,
              child: Text('$_favouriteError Retry'),
            )
          else if (_favourites == null)
            const LinearProgressIndicator()
          else if (_favourites!.isEmpty)
            const Text('Tap the star beside a stop to save it here.')
          else
            for (final stop in _favourites!)
              Builder(
                builder: (context) {
                  final destination = widget.availableStops != null;
                  final reachable =
                      !destination ||
                      widget.availableStops!.any((item) => item.id == stop.id);
                  final usable = reachable && stop.id != widget.excludedStopId;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(stop.name)),
                            _favouriteStar(stop)!,
                          ],
                        ),
                        if (!reachable)
                          const Text('Not reachable from selected origin')
                        else if (!usable)
                          const Text('Already selected'),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: !usable || _usingFavourite
                                ? null
                                : () => _useFavourite(stop),
                            child: Text(
                              destination
                                  ? 'Use as Destination'
                                  : 'Use as Origin',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        ],
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    if (_favouriteRepository != null) {
      _favouriteRepository!.changes.addListener(_loadFavourites);
      _loadFavourites();
    }
    _stops = widget.availableStops ?? const [];
    _radius = [500, 1000, 2000].contains(widget.initialRadius)
        ? widget.initialRadius
        : 1000;
    _locationService =
        widget.locationService ?? ForegroundPassengerLocationService();
    if (widget.allowNearby && widget.startNearby) _findNearby();
  }

  void _manual() {
    _requestId++;
    setState(() {
      _nearby = false;
      _locating = false;
      _error = null;
      _stops = const [];
    });
    if (_searchController.text.trim().isNotEmpty) _loadStops();
  }

  Future<void> _findNearby({bool reusePosition = false}) async {
    _debounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    final request = ++_requestId;
    setState(() {
      _nearby = true;
      _locating = true;
      _error = null;
      _nearbyStops = [];
    });
    try {
      final previous = _locationResult;
      final result = reusePosition && previous?.location != null
          ? previous!
          : await _locationService.getCurrentLocation();
      if (!mounted || request != _requestId) return;
      _locationResult = result;
      final position = result.location;
      if (position == null) {
        setState(() {
          _locating = false;
          _error = switch (result.status) {
            PassengerLocationStatus.permissionDenied =>
              'Location permission is required to find nearby bus stops.',
            PassengerLocationStatus.permissionDeniedForever =>
              'Location permission is disabled.',
            PassengerLocationStatus.servicesDisabled =>
              'Location services are turned off.',
            _ => 'Unable to get your location. Please try again.',
          };
        });
        return;
      }
      final age = DateTime.now().difference(position.timestamp);
      if (!validCoordinates(position.latitude, position.longitude) ||
          !position.accuracyMeters.isFinite ||
          position.accuracyMeters < 0 ||
          age > const Duration(minutes: 2) ||
          age < const Duration(minutes: -1)) {
        setState(() {
          _locating = false;
          _error = 'Your location is invalid or outdated. Please try again.';
        });
        return;
      }
      final stops =
          await (widget.nearbyRepository ?? SupabaseNearbyStopRepository())
              .findNearby(position, _radius);
      if (!mounted || request != _requestId) return;
      setState(() {
        _nearbyStops = stops;
        _locating = false;
      });
    } on Object catch (error) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _locating = false;
        _error = error is DepartureStopReadException
            ? error.message
            : 'Unable to find nearby stops. Please try again.';
      });
    }
  }

  Future<void> _settings(bool app) async {
    try {
      final opened = app
          ? await _locationService.openAppSettings()
          : await _locationService.openLocationSettings();
      if (!mounted) return;
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to open settings. Please open Android Settings manually.',
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open settings.')),
        );
      }
    }
  }

  Widget _nearbyResults() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Nearby Bus Stops', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        'Distances are approximate straight-line distances. Check recommendations for available journeys.',
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final radius in [500, 1000, 2000])
            ChoiceChip(
              label: Text(radius == 500 ? '500 m' : '${radius ~/ 1000} km'),
              selected: _radius == radius,
              onSelected: _locating
                  ? null
                  : (_) {
                      _radius = radius;
                      _findNearby(reusePosition: true);
                    },
            ),
        ],
      ),
      TextButton(onPressed: _manual, child: const Text('Search Manually')),
      if (_locating)
        const Center(child: CircularProgressIndicator())
      else if (_error != null) ...[
        Text(_error!),
        if (_locationResult?.status ==
            PassengerLocationStatus.permissionDeniedForever)
          TextButton(
            onPressed: () => _settings(true),
            child: const Text('Open Settings'),
          ),
        if (_locationResult?.status == PassengerLocationStatus.servicesDisabled)
          TextButton(
            onPressed: () => _settings(false),
            child: const Text('Open Location Settings'),
          ),
        TextButton(onPressed: _findNearby, child: const Text('Try Again')),
      ] else ...[
        if (_locationResult?.isLastKnown == true)
          const Text('Using a recent last-known location.'),
        if (_locationResult?.location != null &&
            hasPoorPassengerLocationAccuracy(_locationResult!.location!))
          const Text(
            'Approximate location: limited accuracy may affect stop ordering.',
          ),
        if (_nearbyStops.isEmpty) ...[
          Text(
            'No bus stops found within ${_radius == 500 ? '500 m' : '${_radius ~/ 1000} km'}.',
          ),
          if (_radius < 2000)
            TextButton(
              onPressed: () {
                _radius = 2000;
                _findNearby(reusePosition: true);
              },
              child: const Text('Search within 2 km'),
            ),
        ],
        for (final nearby in _nearbyStops)
          ListTile(
            key: Key('nearby-${nearby.stop.id}'),
            title: Text(nearby.stop.name),
            trailing: _favouriteStar(nearby.stop),
            subtitle: Text(
              '${nearby.stop.id} · Approx. ${formatApproximateDistance(nearby.distanceMeters)} away',
            ),
            enabled: nearby.stop.id != widget.excludedStopId,
            onTap: nearby.stop.id == widget.excludedStopId
                ? null
                : () => Navigator.of(context).pop(nearby.stop),
          ),
      ],
    ],
  );

  @override
  void dispose() {
    _favouriteRepository?.changes.removeListener(_loadFavourites);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _nearby = false;
    _locating = false;
    _debounce?.cancel();
    final requestId = ++_requestId;
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _stops = widget.availableStops ?? const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _stops = null;
      _error = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadStops(query: query, requestId: requestId),
    );
  }

  Future<void> _loadStops({String? query, int? requestId}) async {
    final effectiveQuery = query ?? _searchController.text.trim();
    if (effectiveQuery.isEmpty) return;
    final effectiveRequestId = requestId ?? ++_requestId;
    setState(() {
      _stops = null;
      _error = null;
    });
    try {
      final stops = widget.availableStops == null
          ? await widget.repository.searchStops(effectiveQuery)
          : widget.availableStops!
                .where(
                  (s) => s.name.toLowerCase().contains(
                    effectiveQuery.toLowerCase(),
                  ),
                )
                .toList();
      if (!mounted || effectiveRequestId != _requestId) return;
      setState(() => _stops = stops);
    } on DepartureStopReadException catch (error) {
      if (!mounted || effectiveRequestId != _requestId) return;
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                key: const Key('stop-search-field'),
                controller: _searchController,
                autofocus: !widget.startNearby,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Search stops',
                  helperText: widget.availableStops == null
                      ? 'Type a stop name to search all available stops'
                      : 'Stops reachable from your selected origin',
                  prefixIcon: const Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (_) {
                  _debounce?.cancel();
                  final query = _searchController.text.trim();
                  if (query.isNotEmpty) {
                    _loadStops(query: query);
                  }
                },
              ),
              const SizedBox(height: 12),
              if (widget.allowNearby && !_nearby)
                TextButton.icon(
                  onPressed: _findNearby,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Use My Current Location'),
                ),
              if (_favouriteRepository != null) _favouriteSection(),
              _nearby ? _nearbyResults() : _buildResults(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_error != null) {
      return _StopMessage(
        icon: Icons.error_outline,
        message: _error!,
        actionLabel: 'Retry',
        onAction: () => _loadStops(),
      );
    }
    final stops = _stops;
    if (stops == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (stops.isEmpty) {
      if (widget.availableStops?.isEmpty == true) {
        return const _StopMessage(
          icon: Icons.route_outlined,
          message: 'No reachable destinations from this origin.',
        );
      }
      if (_searchController.text.trim().isEmpty) {
        return const _StopMessage(
          icon: Icons.search,
          message: 'Search to find a bus stop',
        );
      }
      return const _StopMessage(
        icon: Icons.search_off,
        message: 'No stops found',
      );
    }
    return Column(
      children: stops.map((stop) {
        final excluded = stop.id == widget.excludedStopId;
        return ListTile(
          key: Key('stop-${stop.id}'),
          leading: const Icon(Icons.directions_bus_outlined),
          title: Text(stop.name),
          trailing: _favouriteStar(stop),
          subtitle: excluded ? const Text('Already selected') : null,
          enabled: !excluded,
          onTap: excluded ? null : () => Navigator.of(context).pop(stop),
        );
      }).toList(),
    );
  }
}

class _StopMessage extends StatelessWidget {
  const _StopMessage({
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
    );
  }
}
