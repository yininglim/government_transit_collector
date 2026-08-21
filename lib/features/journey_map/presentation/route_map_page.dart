import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/timetable_recommendation_repository.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
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
      appBar: AppBar(title: const Text('Journey Route')),
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
    final map = widget.mapBuilder?.call(data) ?? _JourneyMap(data: data);
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

class _JourneyMap extends StatefulWidget {
  const _JourneyMap({required this.data});

  final JourneyMapData data;

  @override
  State<_JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends State<_JourneyMap> {
  Object? _tileError;
  var _tileLoadAttempt = 0;

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
    final allCoordinates = [
      ...widget.data.stops.map((stop) => stop.coordinate),
      ...widget.data.legs.expand((leg) => leg.points),
    ];
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
          options: MapOptions(
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
                          stop.role == JourneyStopRole.transfer
                              ? Icons.sync_alt
                              : Icons.location_pin,
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
      ],
    );
  }
}
