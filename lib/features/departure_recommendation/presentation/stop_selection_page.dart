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

  @override
  void initState() {
    super.initState();
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

  Widget _nearbyResults() => ListView(
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
        _stops = const [];
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
      final stops = await widget.repository.searchStops(effectiveQuery);
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                key: const Key('stop-search-field'),
                controller: _searchController,
                autofocus: !widget.startNearby,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Search stops',
                  helperText: 'Type a stop name to search all available stops',
                  prefixIcon: Icon(Icons.search),
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
              Expanded(child: _nearby ? _nearbyResults() : _buildResults()),
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
    return ListView.separated(
      itemCount: stops.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final stop = stops[index];
        final excluded = stop.id == widget.excludedStopId;
        return ListTile(
          key: Key('stop-${stop.id}'),
          leading: const Icon(Icons.directions_bus_outlined),
          title: Text(stop.name),
          subtitle: excluded ? const Text('Already selected') : null,
          enabled: !excluded,
          onTap: excluded ? null : () => Navigator.of(context).pop(stop),
        );
      },
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
