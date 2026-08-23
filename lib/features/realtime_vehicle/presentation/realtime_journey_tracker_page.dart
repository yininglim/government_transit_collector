import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/static_trip_matcher.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/animated_realtime_vehicle_layer.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_movement_diagnostic.dart';
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
    super.key,
  });

  final RealtimeVehicleRepository repository;
  final StaticTripMatcher tripMatcher;
  final Duration pollingInterval;
  final RealtimeMapBuilder? mapBuilder;

  @override
  State<RealtimeJourneyTrackerPage> createState() =>
      _RealtimeJourneyTrackerPageState();
}

class _RealtimeJourneyTrackerPageState extends State<RealtimeJourneyTrackerPage>
    with WidgetsBindingObserver {
  late final RealtimeTrackerController _controller;
  final _movementDiagnostics = RealtimeMovementDiagnosticTracker();
  Object? _observedSnapshot;
  String? _selectedRoute;

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
      _movementDiagnostics.observe(
        buildRealtimeVehicleMarkers(snapshot.vehicles),
      );
      _observedSnapshot = snapshot;
    }
    if (mounted) setState(() {});
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
    final diagnostic = _movementDiagnostics.forIdentity(marker.identity);
    final matched = _controller.isTripMatched(vehicle.tripId);
    final stale = vehicle.timestamp?.isBefore(
      DateTime.now().toUtc().subtract(realtimeStaleThreshold),
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            key: const Key('vehicle-details'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Route ${_displayValue(vehicle.routeId)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text('Vehicle: ${_displayValue(vehicle.vehicleId)}'),
              Text(
                'Trip matched: '
                '${matched == null
                    ? 'Not checked'
                    : matched
                    ? 'Yes'
                    : 'No'}',
              ),
              Text('Updated: ${_formatTimestamp(vehicle.timestamp)}'),
              const SizedBox(height: 16),
              Text(
                'Development movement diagnostic',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Position changed: ${_formatChanged(diagnostic?.positionChanged)}',
              ),
              Text('Previous: ${_formatCoordinate(diagnostic?.previous)}'),
              Text('Latest: ${_formatCoordinate(diagnostic?.latest)}'),
              Text('Moved: ${_formatDistance(diagnostic?.distanceMetres)}'),
              Text(
                'Previous vehicle timestamp: '
                '${_formatTimestamp(diagnostic?.previous?.vehicle.timestamp)}',
              ),
              Text(
                'Latest vehicle timestamp: '
                '${_formatTimestamp(diagnostic?.latest.vehicle.timestamp)}',
              ),
              Text(
                'Feed interval: '
                '${_formatInterval(diagnostic?.feedIntervalSeconds)}',
              ),
              if (stale == true) ...[
                const SizedBox(height: 8),
                const Text('This vehicle position may be stale.'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _displayValue(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : 'Not provided';

  String _formatChanged(bool? changed) => changed == null
      ? 'Not available (first observation)'
      : changed
      ? 'Yes'
      : 'No';

  String _formatCoordinate(RealtimeVehicleMarkerData? marker) => marker == null
      ? 'Not available'
      : '${marker.latitude.toStringAsFixed(6)}, '
            '${marker.longitude.toStringAsFixed(6)}';

  String _formatDistance(double? metres) =>
      metres == null ? 'Not available' : '${metres.toStringAsFixed(1)} m';

  String _formatInterval(int? seconds) =>
      seconds == null ? 'Not available' : '$seconds sec';

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
    final routes =
        allMarkers
            .map((marker) => marker.vehicle.routeId?.trim())
            .whereType<String>()
            .where((route) => route.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final effectiveRoute = routes.contains(_selectedRoute)
        ? _selectedRoute
        : null;
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
      formatTimestamp: _formatTimestamp,
      onRouteChanged: (route) => setState(() => _selectedRoute = route),
      onRefresh: _controller.isRefreshing ? null : _controller.refresh,
    );
    final map = visibleMarkers.isEmpty
        ? const _NoRealtimeVehicles()
        : widget.mapBuilder?.call(visibleMarkers, _showVehicleDetails) ??
              RealtimeVehicleMap(
                markers: visibleMarkers,
                onMarkerTap: _showVehicleDetails,
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
                    'Live Vehicles: $vehicleCount',
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
            Text('Last updated: ${formatTimestamp(feedTimestamp)}'),
            Text('Auto refresh: Every ${pollingInterval.inSeconds} sec'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              key: const Key('route-filter'),
              initialValue: selectedRoute,
              decoration: const InputDecoration(
                labelText: 'Route filter',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All Routes')),
                ...routes.map(
                  (route) => DropdownMenuItem(value: route, child: Text(route)),
                ),
              ],
              onChanged: onRouteChanged,
            ),
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
  const _NoRealtimeVehicles();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('tracker-empty'),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No realtime vehicle positions are currently available.',
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
