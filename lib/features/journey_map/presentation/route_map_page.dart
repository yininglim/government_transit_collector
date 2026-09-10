import 'package:government_transit_collector/core/widgets/readable_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/passenger_location/data/passenger_location.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/animated_realtime_vehicle_layer.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';
import 'package:latlong2/latlong.dart';

class RouteMapPage extends StatefulWidget {
  const RouteMapPage({
    required this.recommendation,
    required this.originStopName,
    required this.destinationStopName,
    required this.repository,
    this.mapBuilder,
    super.key,
  });

  final JourneyRecommendation recommendation;
  final String originStopName;
  final String destinationStopName;
  final JourneyMapRepository repository;
  final Widget Function(JourneyMapData data)? mapBuilder;

  @override
  State<RouteMapPage> createState() => _RouteMapPageState();
}

class _RouteMapPageState extends State<RouteMapPage> {
  JourneyMapData? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final data = await widget.repository.loadJourney(widget.recommendation);
      if (mounted) setState(() => _data = data);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: readableAppBar(context, title: const Text('Journey Route')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 44),
              const SizedBox(height: 12),
              const Text('Unable to load this journey route.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('retry-route-map'),
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final data = _data;
    if (data == null) return const Center(child: CircularProgressIndicator());

    final summary = _JourneyMapSummary(
      recommendation: widget.recommendation,
      originStopName: widget.originStopName,
      destinationStopName: widget.destinationStopName,
      data: data,
    );
    final map = widget.mapBuilder?.call(data) ?? JourneyRouteMap(data: data);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > constraints.maxHeight) {
          return Row(
            children: [
              SizedBox(
                width: constraints.maxWidth.clamp(280, 360).toDouble(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: summary,
                ),
              ),
              Expanded(child: map),
            ],
          );
        }
        return Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: summary),
            Expanded(child: map),
          ],
        );
      },
    );
  }
}

class _JourneyMapSummary extends StatelessWidget {
  const _JourneyMapSummary({
    required this.recommendation,
    required this.originStopName,
    required this.destinationStopName,
    required this.data,
  });

  final JourneyRecommendation recommendation;
  final String originStopName;
  final String destinationStopName;
  final JourneyMapData data;

  @override
  Widget build(BuildContext context) {
    final route = switch (recommendation) {
      DirectJourneyRecommendation direct =>
        direct.routeShortName ?? direct.routeId,
      TransferJourneyRecommendation transfer =>
        '${transfer.firstRouteShortName ?? transfer.firstRouteId} → '
            '${transfer.secondRouteShortName ?? transfer.secondRouteId}',
    };
    final transferName = recommendation is TransferJourneyRecommendation
        ? (recommendation as TransferJourneyRecommendation).transferStopName
        : null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(route, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('$originStopName → $destinationStopName'),
            if (transferName != null) Text('Transfer at $transferName'),
            const SizedBox(height: 6),
            Text(
              '${formatServiceDaySeconds(recommendation.departureSeconds)} → '
              '${formatServiceDaySeconds(recommendation.arrivalSeconds)}',
            ),
            if (!data.hasRouteShape) ...[
              const SizedBox(height: 8),
              const Text(
                'Route line is unavailable; available stops are shown.',
                key: Key('missing-route-shape'),
              ),
            ] else if (data.usedFullShapeFallback) ...[
              const SizedBox(height: 8),
              const Text('Showing the available full trip shape.'),
            ],
          ],
        ),
      ),
    );
  }
}

enum JourneyMapDisplayMode { wholeJourney, activeLeg, liveBus }

class JourneyRouteMap extends StatefulWidget {
  const JourneyRouteMap({
    required this.data,
    this.realtimeMarkers = const [],
    this.passengerLocation,
    this.activeLegIndex,
    this.showCameraControls = false,
    this.busLabel,
    this.displayMode = JourneyMapDisplayMode.wholeJourney,
    this.onDisplayModeChanged,
    this.mapController,
    super.key,
  });

  final JourneyMapData data;
  final List<RealtimeVehicleMarkerData> realtimeMarkers;
  final PassengerLocation? passengerLocation;
  final int? activeLegIndex;
  final bool showCameraControls;
  final String? busLabel;
  final JourneyMapDisplayMode displayMode;
  final ValueChanged<JourneyMapDisplayMode>? onDisplayModeChanged;
  final MapController? mapController;

  @override
  State<JourneyRouteMap> createState() => _JourneyRouteMapState();
}

class _JourneyRouteMapState extends State<JourneyRouteMap> {
  late final MapController _mapController;
  Object? _tileError;
  var _tileLoadAttempt = 0;
  var _hasFittedPassengerLocation = false;
  var _mapReady = false;
  Size? _lastPhysicalSize;

  @override
  void initState() {
    super.initState();
    _mapController = widget.mapController ?? MapController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final physicalSize = MediaQuery.sizeOf(context);
    if (_lastPhysicalSize == physicalSize) return;
    _lastPhysicalSize = physicalSize;
    _reapplyCurrentDisplayModeAfterLayout();
  }

  void _reapplyCurrentDisplayModeAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _mapReady) _applyDisplayMode(widget.displayMode);
    });
  }

  @override
  void didUpdateWidget(JourneyRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasFittedPassengerLocation &&
        oldWidget.passengerLocation == null &&
        widget.passengerLocation != null) {
      _hasFittedPassengerLocation = true;
      _reapplyCurrentDisplayModeAfterLayout();
    }
    if (widget.showCameraControls &&
        oldWidget.activeLegIndex != widget.activeLegIndex) {
      _reapplyCurrentDisplayModeAfterLayout();
    }
    if (oldWidget.displayMode != widget.displayMode) {
      _reapplyCurrentDisplayModeAfterLayout();
    }
  }

  List<MapCoordinate> _allCoordinates() => [
    ..._plannedCoordinates(),
    ...widget.realtimeMarkers.map(
      (marker) => MapCoordinate(marker.latitude, marker.longitude),
    ),
    if (widget.passengerLocation case final location?)
      MapCoordinate(location.latitude, location.longitude),
  ];

  List<MapCoordinate> _plannedCoordinates() => [
    ...widget.data.stops.map((stop) => stop.coordinate),
    ...widget.data.legs.expand((leg) => leg.points),
  ];

  List<MapCoordinate> _activeLegCoordinates() {
    final index = widget.activeLegIndex;
    if (index == null || index < 0 || index >= widget.data.legs.length) {
      return _allCoordinates();
    }
    final points = widget.data.legs[index].points;
    return points.isEmpty ? _allCoordinates() : points;
  }

  void _fitCoordinates(List<MapCoordinate> coordinates) {
    if (coordinates.isEmpty) return;
    final points = coordinates
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    if (points.length == 1) {
      _mapController.move(points.single, 16);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(48),
        maxZoom: 17,
      ),
    );
  }

  void _fitJourney() => _fitCoordinates(_plannedCoordinates());

  void _fitActiveLeg() => _fitCoordinates(_activeLegCoordinates());

  void _followBus() {
    final marker = widget.realtimeMarkers.firstOrNull;
    if (marker == null) return;
    _mapController.move(
      LatLng(marker.latitude, marker.longitude),
      _mapController.camera.zoom.clamp(15, 18),
    );
  }

  void _applyDisplayMode(JourneyMapDisplayMode mode) {
    switch (mode) {
      case JourneyMapDisplayMode.wholeJourney:
        _fitJourney();
        return;
      case JourneyMapDisplayMode.activeLeg:
        _fitActiveLeg();
        return;
      case JourneyMapDisplayMode.liveBus:
        _followBus();
        return;
    }
  }

  void _selectDisplayMode(JourneyMapDisplayMode mode) {
    _applyDisplayMode(mode);
    widget.onDisplayModeChanged?.call(mode);
  }

  void _handleTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    debugPrint('OpenStreetMap tile failed to load: $error');
    if (_tileError != null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tileError == null) setState(() => _tileError = error);
    });
  }

  void _retryTiles() {
    setState(() {
      _tileError = null;
      _tileLoadAttempt++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final allCoordinates = _allCoordinates();
    if (allCoordinates.isEmpty) {
      return const Center(
        child: Text('No coordinates are available for this journey.'),
      );
    }
    final points = allCoordinates
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.tertiary,
    ];
    return Stack(
      children: [
        FlutterMap(
          key: const Key('journey-map'),
          mapController: _mapController,
          options: MapOptions(
            onMapReady: () {
              _mapReady = true;
              _reapplyCurrentDisplayModeAfterLayout();
            },
            initialCenter: points.first,
            initialZoom: 14,
            initialCameraFit: points.length > 1
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(48),
                    maxZoom: 17,
                  )
                : null,
          ),
          children: [
            TileLayer(
              key: ValueKey('osm-tiles-$_tileLoadAttempt'),
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.government_transit_collector',
              errorTileCallback: _handleTileError,
              evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
            ),
            PolylineLayer(
              polylines: [
                for (var index = 0; index < widget.data.legs.length; index++)
                  if (widget.data.legs[index].points.length > 1)
                    Polyline(
                      points: widget.data.legs[index].points
                          .map(
                            (point) => LatLng(point.latitude, point.longitude),
                          )
                          .toList(),
                      color: colors[index % colors.length],
                      strokeWidth: 5,
                    ),
              ],
            ),
            MarkerLayer(
              markers: widget.data.stops
                  .map(
                    (stop) => Marker(
                      point: LatLng(
                        stop.coordinate.latitude,
                        stop.coordinate.longitude,
                      ),
                      width: 52,
                      height: 52,
                      child: Tooltip(
                        message: stop.name,
                        child: Icon(
                          switch (stop.role) {
                            JourneyStopRole.origin => Icons.trip_origin,
                            JourneyStopRole.transfer => Icons.sync_alt,
                            JourneyStopRole.destination => Icons.flag,
                          },
                          size: 38,
                          color: stop.role == JourneyStopRole.destination
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (widget.passengerLocation case final passenger?)
              MarkerLayer(
                key: const Key('passenger-location-layer'),
                markers: [
                  Marker(
                    key: const Key('passenger-location-marker'),
                    point: LatLng(passenger.latitude, passenger.longitude),
                    width: 52,
                    height: 52,
                    child: Semantics(
                      label: 'Your current location',
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 3,
                          ),
                          boxShadow: const [
                            BoxShadow(blurRadius: 5, color: Colors.black26),
                          ],
                        ),
                        child: Icon(
                          Icons.person_pin_circle,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            AnimatedRealtimeVehicleLayer(
              markers: widget.realtimeMarkers,
              builder: (context, markers, movingIdentities) => MarkerLayer(
                markers: markers
                    .map(
                      (marker) => Marker(
                        key: ValueKey('selected-${marker.identity}'),
                        point: LatLng(marker.latitude, marker.longitude),
                        width: 56,
                        height: 56,
                        child: Tooltip(
                          message: widget.busLabel == null
                              ? 'Live bus'
                              : 'Bus ${widget.busLabel}',
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
                    )
                    .toList(growable: false),
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
              key: const Key('tile-load-error'),
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.layers_clear_outlined,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Map background failed to load. Check your network.',
                      ),
                    ),
                    TextButton(
                      key: const Key('retry-map-tiles'),
                      onPressed: _retryTiles,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (widget.showCameraControls)
          Positioned(
            right: 12,
            bottom: 42,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapControl(
                  key: const Key('fit-journey-map'),
                  tooltip: 'Fit journey',
                  icon: Icons.fit_screen,
                  selected:
                      widget.displayMode == JourneyMapDisplayMode.wholeJourney,
                  onPressed: () =>
                      _selectDisplayMode(JourneyMapDisplayMode.wholeJourney),
                ),
                if (widget.activeLegIndex != null) ...[
                  const SizedBox(height: 8),
                  _MapControl(
                    key: const Key('fit-active-leg-map'),
                    tooltip: 'Fit active leg',
                    icon: Icons.route,
                    selected:
                        widget.displayMode == JourneyMapDisplayMode.activeLeg,
                    onPressed: () =>
                        _selectDisplayMode(JourneyMapDisplayMode.activeLeg),
                  ),
                ],
                if (widget.realtimeMarkers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _MapControl(
                    key: const Key('follow-live-bus'),
                    tooltip: 'Follow live bus',
                    icon: Icons.directions_bus,
                    selected:
                        widget.displayMode == JourneyMapDisplayMode.liveBus,
                    onPressed: () =>
                        _selectDisplayMode(JourneyMapDisplayMode.liveBus),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        visualDensity: VisualDensity.compact,
      ),
    ),
  );
}
