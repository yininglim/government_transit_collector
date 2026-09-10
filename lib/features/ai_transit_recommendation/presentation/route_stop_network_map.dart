import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:latlong2/latlong.dart';

enum RouteStopMapMarkerRole {
  existingStop,
  stopToImprove,
  candidateBoundary,
  recommendedArea,
}

enum RouteStopMapInitialFocus { allHighlights, stopImprovement, additionalCoverage }

class RouteStopMapMarker {
  const RouteStopMapMarker({
    required this.id,
    required this.label,
    required this.coordinate,
    required this.role,
    this.isTargetStop = false,
  });

  final String id;
  final String label;
  final MapCoordinate coordinate;
  final RouteStopMapMarkerRole role;
  final bool isTargetStop;
}

class RouteStopNetworkMap extends StatefulWidget {
  const RouteStopNetworkMap({
    required this.routeLines,
    required this.markers,
    required this.candidateSegment,
    required this.showCandidateLegend,
    required this.showTargetLegend,
    required this.recommendationAreaDescription,
    required this.initialFocus,
    this.baseMapEnabled = true,
    super.key,
  });

  final List<List<MapCoordinate>> routeLines;
  final List<RouteStopMapMarker> markers;
  final List<MapCoordinate>? candidateSegment;
  final bool showCandidateLegend;
  final bool showTargetLegend;
  final String? recommendationAreaDescription;
  final RouteStopMapInitialFocus initialFocus;
  final bool baseMapEnabled;

  @override
  State<RouteStopNetworkMap> createState() => _RouteStopNetworkMapState();
}

class _RouteStopNetworkMapState extends State<RouteStopNetworkMap> {
  final _controller = MapController();
  RouteStopMapMarker? _selectedStop;
  bool _recommendationAreaSelected = false;

  List<MapCoordinate> get _coordinates => [
    for (final line in widget.routeLines) ...line,
    for (final marker in widget.markers) marker.coordinate,
  ];

  List<MapCoordinate> get _targetCoordinates => [
    for (final marker in widget.markers)
      if (marker.role == RouteStopMapMarkerRole.stopToImprove ||
          marker.isTargetStop)
        marker.coordinate,
  ];

  List<MapCoordinate> get _coverageCoordinates => [
    if (widget.candidateSegment case final segment?) ...segment,
    for (final marker in widget.markers)
      if (marker.role == RouteStopMapMarkerRole.candidateBoundary ||
          marker.role == RouteStopMapMarkerRole.recommendedArea)
        marker.coordinate,
  ];

  List<MapCoordinate> get _allHighlightCoordinates {
    final highlighted = <MapCoordinate>[
      if (widget.candidateSegment case final segment?) ...segment,
      for (final marker in widget.markers)
        if (marker.role != RouteStopMapMarkerRole.existingStop)
          marker.coordinate,
    ];
    return highlighted.isEmpty ? _coordinates : highlighted;
  }

  List<MapCoordinate> get _initialFocusCoordinates => switch (
    widget.initialFocus
  ) {
    RouteStopMapInitialFocus.stopImprovement
        when _targetCoordinates.isNotEmpty =>
      _targetCoordinates,
    RouteStopMapInitialFocus.additionalCoverage
        when _coverageCoordinates.isNotEmpty =>
      _coverageCoordinates,
    _ => _allHighlightCoordinates,
  };

  @override
  void didUpdateWidget(RouteStopNetworkMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedId = _selectedStop?.id;
    if (selectedId != null) {
      _selectedStop = _selectableMarker(selectedId);
    }
    if (widget.recommendationAreaDescription == null ||
        !widget.markers.any(
          (marker) => marker.role == RouteStopMapMarkerRole.recommendedArea,
        )) {
      _recommendationAreaSelected = false;
    }
    if (oldWidget.routeLines != widget.routeLines ||
        oldWidget.candidateSegment != widget.candidateSegment ||
        oldWidget.markers != widget.markers) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitCoordinates(_initialFocusCoordinates);
      });
    }
  }

  void _fitCoordinates(List<MapCoordinate> focus) {
    if (focus.isEmpty) return;
    final points = focus
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    if (points.length == 1) {
      _controller.move(points.single, 16);
      return;
    }
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(42),
        maxZoom: 17,
      ),
    );
  }

  void _fit() => _fitCoordinates(_allHighlightCoordinates);

  void _zoom(double change) {
    _controller.move(
      _controller.camera.center,
      (_controller.camera.zoom + change).clamp(3, 19),
    );
  }

  RouteStopMapMarker? _selectableMarker(String id) {
    for (final marker in widget.markers) {
      if (marker.id == id &&
          marker.role != RouteStopMapMarkerRole.recommendedArea) {
        return marker;
      }
    }
    return null;
  }

  String? get _selectedRecommendationAreaDescription =>
      _recommendationAreaSelected ? widget.recommendationAreaDescription : null;

  @override
  Widget build(BuildContext context) {
    if (_coordinates.isEmpty) {
      return const Center(
        child: Text('No existing route or stop coordinates are available.'),
      );
    }
    final points = _initialFocusCoordinates
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
          key: const Key('route-stop-interactive-map'),
          mapController: _controller,
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 14,
            minZoom: 3,
            maxZoom: 19,
            initialCameraFit: points.length > 1
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(42),
                    maxZoom: 17,
                  )
                : null,
          ),
          children: [
            if (widget.baseMapEnabled)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName:
                    'com.example.government_transit_collector',
              )
            else
              const ColoredBox(color: Color(0xFFF1F3F4)),
            if (widget.routeLines.any((line) => line.length > 1))
              PolylineLayer(
                key: const Key('existing-route-shape'),
                polylines: [
                  for (final line in widget.routeLines)
                    if (line.length > 1)
                      Polyline(
                        points: line
                            .map(
                              (point) =>
                                  LatLng(point.latitude, point.longitude),
                            )
                            .toList(),
                        color: Theme.of(context).colorScheme.primary,
                        strokeWidth: 5,
                      ),
                ],
              ),
            if (widget.candidateSegment case final segment?)
              PolylineLayer(
                key: const Key('recommended-candidate-segment'),
                polylines: [
                  Polyline(
                    points: segment
                        .map((point) => LatLng(point.latitude, point.longitude))
                        .toList(),
                    color: Theme.of(context).colorScheme.tertiary,
                    strokeWidth: 8,
                  ),
                ],
              ),
            _markerLayer(RouteStopMapMarkerRole.existingStop),
            _markerLayer(RouteStopMapMarkerRole.stopToImprove),
            _markerLayer(RouteStopMapMarkerRole.candidateBoundary),
            _markerLayer(RouteStopMapMarkerRole.recommendedArea),
            const RichAttributionWidget(
              showFlutterMapAttribution: false,
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
              Positioned(
                right: 10,
                top: 10,
                child: Column(
                  children: [
                    _MapControl(
                      key: const Key('route-stop-map-zoom-in'),
                      tooltip: 'Zoom in',
                      icon: Icons.add,
                      onPressed: () => _zoom(1),
                    ),
                    const SizedBox(height: 6),
                    _MapControl(
                      key: const Key('route-stop-map-zoom-out'),
                      tooltip: 'Zoom out',
                      icon: Icons.remove,
                      onPressed: () => _zoom(-1),
                    ),
                    const SizedBox(height: 6),
                    _MapControl(
                      key: const Key('route-stop-map-recenter'),
                      tooltip: 'Reset View',
                      icon: Icons.fit_screen,
                      onPressed: _fit,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        _MapLegend(
          showTargetRole: widget.showTargetLegend,
          showCandidateRoles: widget.showCandidateLegend,
        ),
        if (widget.showTargetLegend && widget.showCandidateLegend) ...[
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              key: const Key('route-stop-map-focus-actions'),
              spacing: 6,
              runSpacing: 2,
              children: [
                ActionChip(
                  key: const Key('route-stop-focus-stop-improvement'),
                  label: const Text('Focus Stop Improvement'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _fitCoordinates(_targetCoordinates),
                ),
                ActionChip(
                  key: const Key('route-stop-focus-additional-coverage'),
                  label: const Text('Focus Additional Coverage'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _fitCoordinates(_coverageCoordinates),
                ),
              ],
            ),
          ),
        ],
        if (_selectedRecommendationAreaDescription
            case final description?) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected Recommendation Area',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const Text('Additional Stop Coverage'),
                    const SizedBox(height: 3),
                    Text(
                      'Suggested Area',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(description),
                  ],
                ),
              ),
            ),
          ),
        ] else if (_selectedStop case final selected?) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected Stop',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      selected.label,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (selected.role ==
                        RouteStopMapMarkerRole.candidateBoundary)
                      Text(
                        'Boundary Stop',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    if (selected.isTargetStop)
                      Text(
                        'Stop to Improve',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  MarkerLayer _markerLayer(RouteStopMapMarkerRole role) => MarkerLayer(
    markers: widget.markers.where((marker) => marker.role == role).map((marker) {
      final size = _markerSize(marker.role);
      return Marker(
        key: Key('${marker.role.name}-marker-${marker.id}'),
        point: LatLng(
          marker.coordinate.latitude,
          marker.coordinate.longitude,
        ),
        width: size + 10,
        height: size + 10,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: marker.role == RouteStopMapMarkerRole.recommendedArea
              ? widget.recommendationAreaDescription == null
                    ? null
                    : () => setState(() {
                        _selectedStop = null;
                        _recommendationAreaSelected =
                            !_recommendationAreaSelected;
                      })
              : () => setState(() {
                  _selectedStop = _selectedStop?.id == marker.id
                      ? null
                      : marker;
                  _recommendationAreaSelected = false;
                }),
          child: Tooltip(
            message: marker.label,
            child: Semantics(
              button:
                  marker.role != RouteStopMapMarkerRole.recommendedArea ||
                  widget.recommendationAreaDescription != null,
              selected: marker.role == RouteStopMapMarkerRole.recommendedArea
                  ? _recommendationAreaSelected
                  : _selectedStop?.id == marker.id,
              label: '${marker.role.name}: ${marker.label}',
              child: _MarkerSymbol(
                role: marker.role,
                isTargetStop: marker.isTargetStop,
                selected: _selectedStop?.id == marker.id,
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );
}

double _markerSize(RouteStopMapMarkerRole role) => switch (role) {
  RouteStopMapMarkerRole.existingStop => 10,
  RouteStopMapMarkerRole.stopToImprove => 22,
  RouteStopMapMarkerRole.candidateBoundary => 32,
  RouteStopMapMarkerRole.recommendedArea => 42,
};

class _MarkerSymbol extends StatelessWidget {
  const _MarkerSymbol({
    required this.role,
    this.isTargetStop = false,
    this.compact = false,
    this.selected = false,
  });

  final RouteStopMapMarkerRole role;
  final bool isTargetStop;
  final bool compact;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final targetColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.orangeAccent
        : Colors.orange.shade800;
    if (role == RouteStopMapMarkerRole.existingStop) {
      final size = compact ? 9.0 : _markerSize(role) + (selected ? 1 : 0);
      return SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              width: compact ? 1 : (selected ? 1.75 : 1.25),
            ),
          ),
          child: Center(
            child: SizedBox.square(
              dimension: compact ? 2.5 : 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (role == RouteStopMapMarkerRole.stopToImprove) {
      return Icon(
        Icons.adjust,
        size: compact ? 16 : _markerSize(role) + (selected ? 2 : 0),
        color: targetColor,
      );
    }
    final icon = Icon(
      role == RouteStopMapMarkerRole.candidateBoundary
          ? Icons.location_on_outlined
          : Icons.assistant_navigation,
      size: compact ? 18 : _markerSize(role) + (selected ? 2 : 0),
      color: role == RouteStopMapMarkerRole.candidateBoundary
          ? Theme.of(context).colorScheme.tertiary
          : Theme.of(context).colorScheme.error,
    );
    if (role != RouteStopMapMarkerRole.candidateBoundary || !isTargetStop) {
      return icon;
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        icon,
        Positioned(
          right: compact ? 0 : 1,
          top: compact ? 0 : 1,
          child: Icon(
            Icons.adjust,
            size: compact ? 8 : 11,
            color: targetColor,
          ),
        ),
      ],
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({
    required this.showTargetRole,
    required this.showCandidateRoles,
  });

  final bool showTargetRole;
  final bool showCandidateRoles;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Map legend',
    child: Wrap(
      key: const Key('route-stop-map-legend'),
      spacing: 10,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const _LegendItem(
          role: RouteStopMapMarkerRole.existingStop,
          label: 'Existing Stop',
        ),
        if (showTargetRole)
          const _LegendItem(
            role: RouteStopMapMarkerRole.stopToImprove,
            label: 'Stop to Improve',
          ),
        if (showCandidateRoles) ...[
          const _LegendItem(
            role: RouteStopMapMarkerRole.candidateBoundary,
            label: 'Boundary Stop',
          ),
          const _LegendItem(
            role: RouteStopMapMarkerRole.recommendedArea,
            label: 'Recommended Stop Area',
          ),
        ],
      ],
    ),
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.role, required this.label});

  final RouteStopMapMarkerRole role;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _MarkerSymbol(role: role, compact: true),
      const SizedBox(width: 3),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: const CircleBorder(),
    elevation: 3,
    child: IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    ),
  );
}
