import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/journey_progress_calculator.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_route_metadata_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/static_trip_matcher.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/animated_realtime_vehicle_layer.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_tracker_controller.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';
import 'package:latlong2/latlong.dart';

const realtimeStaleThreshold = Duration(minutes: 5);

typedef RealtimeMapBuilder =
    Widget Function(
      List<RealtimeVehicleMarkerData> markers,
      ValueChanged<RealtimeVehicleMarkerData> onMarkerTap,
    );

class RealtimeJourneyTrackerPage extends StatefulWidget {
  const RealtimeJourneyTrackerPage({
    required this.repository,
    required this.tripMatcher,
    this.pollingInterval = realtimePollingInterval,
    this.mapBuilder,
    this.routeMetadataRepository,
    this.tripProgressRepository,
    super.key,
  });

  final RealtimeVehicleRepository repository;
  final StaticTripMatcher tripMatcher;
  final Duration pollingInterval;
  final RealtimeMapBuilder? mapBuilder;
  final RealtimeRouteMetadataRepository? routeMetadataRepository;
  final TripProgressRepository? tripProgressRepository;

  @override
  State<RealtimeJourneyTrackerPage> createState() =>
      _RealtimeJourneyTrackerPageState();
}

class _RealtimeJourneyTrackerPageState extends State<RealtimeJourneyTrackerPage>
    with WidgetsBindingObserver {
  late final RealtimeTrackerController _controller;
  Object? _observedSnapshot;
  String? _selectedRoute;
  final Map<String, RealtimeRouteMetadata> _routeMetadata = {};
  final Set<String> _requestedRouteIds = {};
  final Set<String> _knownRouteIds = {};
  Object? _routeMetadataError;
  final Map<String, Future<TripProgressData>> _tripProgressCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = RealtimeTrackerController(
      repository: widget.repository,
      tripMatcher: widget.tripMatcher,
      pollingInterval: widget.pollingInterval,
    )..addListener(_onControllerChanged);
    _controller.startPolling();
  }

  void _onControllerChanged() {
    final snapshot = _controller.snapshot;
    if (snapshot != null && !identical(snapshot, _observedSnapshot)) {
      _observedSnapshot = snapshot;
      unawaited(_loadRouteMetadata(snapshot.vehicles));
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadRouteMetadata(
    Iterable<RealtimeVehiclePosition> vehicles,
  ) async {
    final routeIds = vehicles
        .map((vehicle) => vehicle.routeId?.trim())
        .whereType<String>()
        .where((routeId) => routeId.isNotEmpty)
        .where((routeId) => !_requestedRouteIds.contains(routeId))
        .toSet();
    if (routeIds.isEmpty) return;
    _knownRouteIds.addAll(routeIds);
    _requestedRouteIds.addAll(routeIds);
    try {
      final loaded =
          await (widget.routeMetadataRepository ??
                  SupabaseRealtimeRouteMetadataRepository())
              .loadRoutes(routeIds);
      if (!mounted) return;
      setState(() {
        _routeMetadata.addAll(loaded);
        _routeMetadataError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _routeMetadataError = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.startPolling(fetchImmediately: true);
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _controller.stopPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Not provided';
    final local = transitServiceDateTime(timestamp);
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second ${local.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _showVehicleDetails(RealtimeVehicleMarkerData marker) async {
    final vehicle = marker.vehicle;
    final routeId = vehicle.routeId?.trim();
    final route = routeId == null ? null : _routeMetadata[routeId];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _LiveVehicleProgressSheet(
        initialMarker: marker,
        route: route,
        routeFallback: _displayValue(routeId),
        realtimeUpdates: _controller,
        resolveCurrentMarker: () => _markerForIdentity(marker.identity),
        loadTrip: _loadTripProgress,
        formatTimestamp: _formatTimestamp,
        staleThreshold: realtimeStaleThreshold,
      ),
    );
  }

  Future<TripProgressData> _loadTripProgress(String exactTripId) =>
      _tripProgressCache.putIfAbsent(
        exactTripId,
        () => (widget.tripProgressRepository ?? GtfsTripProgressRepository())
            .loadTrip(exactTripId),
      );

  RealtimeVehicleMarkerData? _markerForIdentity(String identity) {
    final snapshot = _controller.snapshot;
    if (snapshot == null) return null;
    return buildRealtimeVehicleMarkers(
      snapshot.vehicles,
    ).where((marker) => marker.identity == identity).firstOrNull;
  }

  String _displayValue(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : 'Not provided';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Realtime Journey Tracker')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_controller.isInitialLoading) {
      return const Center(
        key: Key('tracker-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_controller.snapshot == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                _controller.initialError ??
                    'Unable to load realtime vehicle positions.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('retry-tracker'),
                onPressed: _controller.refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final allMarkers = buildRealtimeVehicleMarkers(
      _controller.snapshot!.vehicles,
    );
    _knownRouteIds.addAll(
      allMarkers
          .map((marker) => marker.vehicle.routeId?.trim())
          .whereType<String>()
          .where((route) => route.isNotEmpty),
    );
    final routes = _knownRouteIds.toList()..sort();
    final effectiveRoute = _selectedRoute;
    final visibleMarkers = effectiveRoute == null
        ? allMarkers
        : allMarkers
              .where(
                (marker) => marker.vehicle.routeId?.trim() == effectiveRoute,
              )
              .toList();
    final status = _TrackerStatusPanel(
      vehicleCount: allMarkers.length,
      feedTimestamp: _controller.snapshot!.feedTimestamp,
      isRefreshing: _controller.isRefreshing,
      pollingInterval: widget.pollingInterval,
      warning: _controller.refreshWarning ?? _controller.matchingWarning,
      routes: routes,
      selectedRoute: effectiveRoute,
      routeMetadata: _routeMetadata,
      routeMetadataUnavailable: _routeMetadataError != null,
      selectedVehicleCount: visibleMarkers.length,
      formatTimestamp: _formatTimestamp,
      onRouteChanged: (route) => setState(() => _selectedRoute = route),
      onRefresh: _controller.isRefreshing ? null : _controller.refresh,
    );
    final map = KeyedSubtree(
      key: ValueKey('realtime-map-route-${effectiveRoute ?? 'all'}'),
      child: visibleMarkers.isEmpty
          ? _NoRealtimeVehicles(
              routeName: effectiveRoute == null
                  ? null
                  : _routeMetadata[effectiveRoute]?.passengerShortName ??
                        effectiveRoute,
            )
          : widget.mapBuilder?.call(visibleMarkers, _showVehicleDetails) ??
                RealtimeVehicleMap(
                  markers: visibleMarkers,
                  onMarkerTap: _showVehicleDetails,
                ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > constraints.maxHeight) {
          return Row(
            children: [
              SizedBox(
                width: constraints.maxWidth.clamp(280, 340).toDouble(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: status,
                ),
              ),
              Expanded(child: map),
            ],
          );
        }
        return Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: status),
            Expanded(child: map),
          ],
        );
      },
    );
  }
}

class _LiveVehicleProgressSheet extends StatefulWidget {
  const _LiveVehicleProgressSheet({
    required this.initialMarker,
    required this.route,
    required this.routeFallback,
    required this.realtimeUpdates,
    required this.resolveCurrentMarker,
    required this.loadTrip,
    required this.formatTimestamp,
    required this.staleThreshold,
  });

  final RealtimeVehicleMarkerData initialMarker;
  final RealtimeRouteMetadata? route;
  final String routeFallback;
  final Listenable realtimeUpdates;
  final RealtimeVehicleMarkerData? Function() resolveCurrentMarker;
  final Future<TripProgressData> Function(String exactTripId) loadTrip;
  final String Function(DateTime?) formatTimestamp;
  final Duration staleThreshold;

  @override
  State<_LiveVehicleProgressSheet> createState() =>
      _LiveVehicleProgressSheetState();
}

class _LiveVehicleProgressSheetState extends State<_LiveVehicleProgressSheet> {
  late RealtimeVehicleMarkerData _marker;
  JourneyProgressCalculator? _calculator;
  JourneyProgressState? _progress;
  Object? _error;
  var _loading = false;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _marker = widget.initialMarker;
    widget.realtimeUpdates.addListener(_onRealtimeChanged);
    _loadExactTrip();
  }

  @override
  void dispose() {
    widget.realtimeUpdates.removeListener(_onRealtimeChanged);
    super.dispose();
  }

  void _onRealtimeChanged() {
    final latest = widget.resolveCurrentMarker();
    if (latest == null || !mounted) return;
    final previousTripId = _marker.vehicle.tripId?.trim();
    final latestTripId = latest.vehicle.tripId?.trim();
    setState(() => _marker = latest);
    if (latestTripId != previousTripId) {
      _calculator = null;
      _progress = null;
      _loadExactTrip();
    } else {
      _calculateProgress();
    }
  }

  Future<void> _loadExactTrip() async {
    final tripId = _marker.vehicle.tripId?.trim();
    final generation = ++_loadGeneration;
    if (tripId == null || tripId.isEmpty) {
      setState(() {
        _loading = false;
        _error = StateError('Missing exact trip ID');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.loadTrip(tripId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _calculator = JourneyProgressCalculator(data);
        _loading = false;
        _calculateProgress();
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  void _calculateProgress() {
    final calculator = _calculator;
    if (calculator == null) return;
    _progress = calculator.calculate(
      vehicleCoordinate: MapCoordinate(_marker.latitude, _marker.longitude),
      timestamp: _marker.vehicle.timestamp,
      previous: _progress,
    );
  }

  bool get _tripCompleted {
    final progress = _progress;
    final finalStop = _calculator?.stopProgress.lastOrNull?.stop;
    return progress?.availability == JourneyProgressAvailability.available &&
        finalStop != null &&
        progress!.nextStop == null &&
        progress.completedStops.any((stop) => stop.stopId == finalStop.stopId);
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = _marker.vehicle;
    final stale = vehicle.timestamp?.isBefore(
      DateTime.now().toUtc().subtract(widget.staleThreshold),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          key: const Key('vehicle-details'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.route?.passengerShortName ?? widget.routeFallback,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (widget.route?.passengerLongName case final longName?) ...[
              const SizedBox(height: 2),
              Text(longName),
            ],
            const SizedBox(height: 14),
            _ProgressDetail(
              icon: Icons.location_on_outlined,
              label: 'Bus location',
              value: _locationText,
              valueKey: const Key('vehicle-near-stop'),
            ),
            const SizedBox(height: 10),
            if (_tripCompleted)
              const _ProgressDetail(
                icon: Icons.flag_outlined,
                label: 'Route status',
                value: 'Route trip completed',
                valueKey: Key('vehicle-trip-completed'),
              )
            else
              _ProgressDetail(
                icon: Icons.directions_bus_filled_outlined,
                label: 'Next stop',
                value: _nextStopText,
                valueKey: const Key('vehicle-next-stop'),
              ),
            const SizedBox(height: 14),
            Text('Vehicle: ${_displayValue(vehicle.vehicleId)}'),
            Text('Updated: ${widget.formatTimestamp(vehicle.timestamp)}'),
            if (stale == true) ...[
              const SizedBox(height: 6),
              const Text('This vehicle position may be stale.'),
            ],
          ],
        ),
      ),
    );
  }

  String get _locationText {
    if (_loading) return 'Loading route position...';
    if (_error != null) return 'Route position unavailable';
    final progress = _progress;
    if (progress?.availability != JourneyProgressAvailability.available) {
      return 'Route position unavailable';
    }
    final nearest = progress?.nearestStop;
    return nearest == null
        ? 'Route position unavailable'
        : 'Near ${nearest.stopName}';
  }

  String get _nextStopText {
    if (_loading) return 'Loading...';
    if (_error != null) return 'Unavailable';
    final progress = _progress;
    if (progress?.availability != JourneyProgressAvailability.available) {
      return 'Unavailable';
    }
    return progress?.nextStop?.stopName ?? 'Unavailable';
  }

  String _displayValue(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : 'Not provided';
}

class _ProgressDetail extends StatelessWidget {
  const _ProgressDetail({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              Text(value, key: valueKey),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrackerStatusPanel extends StatelessWidget {
  const _TrackerStatusPanel({
    required this.vehicleCount,
    required this.feedTimestamp,
    required this.isRefreshing,
    required this.pollingInterval,
    required this.warning,
    required this.routes,
    required this.selectedRoute,
    required this.formatTimestamp,
    required this.onRouteChanged,
    required this.onRefresh,
    required this.routeMetadata,
    required this.routeMetadataUnavailable,
    required this.selectedVehicleCount,
  });

  final int vehicleCount;
  final DateTime? feedTimestamp;
  final bool isRefreshing;
  final Duration pollingInterval;
  final String? warning;
  final List<String> routes;
  final String? selectedRoute;
  final String Function(DateTime?) formatTimestamp;
  final ValueChanged<String?> onRouteChanged;
  final VoidCallback? onRefresh;
  final Map<String, RealtimeRouteMetadata> routeMetadata;
  final bool routeMetadataUnavailable;
  final int selectedVehicleCount;

  String routeLabel(String routeId) {
    final metadata = routeMetadata[routeId];
    final shortName = metadata?.passengerShortName ?? routeId;
    final longName = metadata?.passengerLongName;
    return longName == null ? shortName : '$shortName — $longName';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Live buses: $vehicleCount',
                    key: const Key('tracker-vehicle-count'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('refresh-tracker'),
                  tooltip: 'Refresh vehicle positions',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text('Updated: ${formatTimestamp(feedTimestamp)}'),
            Text('Auto refresh: ${pollingInterval.inSeconds} sec'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              key: const Key('route-filter'),
              initialValue: selectedRoute,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Route filter',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All Routes')),
                ...routes.map(
                  (route) => DropdownMenuItem(
                    value: route,
                    child: Text(
                      routeLabel(route),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: onRouteChanged,
            ),
            if (selectedRoute case final routeId?) ...[
              const SizedBox(height: 8),
              Text(
                routeMetadata[routeId]?.passengerShortName ?? routeId,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (routeMetadata[routeId]?.passengerLongName case final name?)
                Text(name),
              Text('Live buses: $selectedVehicleCount'),
            ],
            if (routeMetadataUnavailable)
              const Text('Passenger route names are temporarily unavailable.'),
            if (isRefreshing) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(key: Key('tracker-refreshing')),
            ],
            if (warning != null) ...[
              const SizedBox(height: 8),
              Text(
                warning!,
                key: const Key('tracker-warning'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoRealtimeVehicles extends StatelessWidget {
  const _NoRealtimeVehicles({this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: Key('tracker-empty'),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          routeName == null
              ? 'No realtime vehicle positions are currently available.'
              : 'No realtime buses are currently available for $routeName.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class RealtimeVehicleMap extends StatefulWidget {
  const RealtimeVehicleMap({
    required this.markers,
    required this.onMarkerTap,
    super.key,
  });

  final List<RealtimeVehicleMarkerData> markers;
  final ValueChanged<RealtimeVehicleMarkerData> onMarkerTap;

  @override
  State<RealtimeVehicleMap> createState() => _RealtimeVehicleMapState();
}

class _RealtimeVehicleMapState extends State<RealtimeVehicleMap> {
  Object? _tileError;
  var _tileAttempt = 0;

  void _handleTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    debugPrint('OpenStreetMap realtime tile failed to load: $error');
    if (_tileError != null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tileError == null) setState(() => _tileError = error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.markers
        .map((marker) => LatLng(marker.latitude, marker.longitude))
        .toList();
    final cameraPlan = buildRealtimeMapCameraPlan(widget.markers)!;
    return Stack(
      children: [
        FlutterMap(
          key: const Key('realtime-vehicle-map'),
          options: MapOptions(
            initialCenter: LatLng(
              cameraPlan.centerLatitude,
              cameraPlan.centerLongitude,
            ),
            initialZoom: 15,
            initialCameraFit: cameraPlan.fitBounds
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(48),
                    maxZoom: 16,
                  )
                : null,
          ),
          children: [
            TileLayer(
              key: ValueKey('realtime-osm-tiles-$_tileAttempt'),
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.government_transit_collector',
              errorTileCallback: _handleTileError,
              evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
            ),
            AnimatedRealtimeVehicleLayer(
              markers: widget.markers,
              builder: (context, markers, movingIdentities) => MarkerLayer(
                markers: markers
                    .map(
                      (marker) => Marker(
                        key: ValueKey(marker.identity),
                        point: LatLng(marker.latitude, marker.longitude),
                        width: 56,
                        height: 56,
                        child: Semantics(
                          label:
                              'Bus ${_markerLabel(marker.vehicle.vehicleId)} '
                              'on route ${_markerLabel(marker.vehicle.routeId)}',
                          button: true,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: movingIdentities.contains(marker.identity)
                                  ? Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.4),
                                      width: 3,
                                    )
                                  : null,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Material(
                                color: Theme.of(context).colorScheme.primary,
                                shape: const CircleBorder(),
                                elevation: 4,
                                child: InkWell(
                                  key: ValueKey('tap-${marker.identity}'),
                                  customBorder: const CircleBorder(),
                                  onTap: () => widget.onMarkerTap(marker),
                                  child: Icon(
                                    Icons.directions_bus,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const RichAttributionWidget(
              showFlutterMapAttribution: false,
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        if (_tileError != null)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                dense: true,
                title: const Text('Map background failed to load.'),
                trailing: TextButton(
                  onPressed: () => setState(() {
                    _tileError = null;
                    _tileAttempt++;
                  }),
                  child: const Text('Retry'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _markerLabel(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : 'unknown';
}
