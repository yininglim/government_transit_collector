import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/journey_map/presentation/route_map_page.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_realtime_matcher.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_tracker_controller.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';

typedef SelectedJourneyMapBuilder =
    Widget Function(
      JourneyMapData data,
      List<RealtimeVehicleMarkerData> realtimeMarkers,
    );

class SelectedJourneyTrackerPage extends StatefulWidget {
  const SelectedJourneyTrackerPage({
    required this.journey,
    required this.realtimeRepository,
    required this.journeyMapRepository,
    this.pollingInterval = realtimePollingInterval,
    this.mapBuilder,
    super.key,
  });

  final SelectedJourneyTracking journey;
  final RealtimeVehicleRepository realtimeRepository;
  final JourneyMapRepository journeyMapRepository;
  final Duration pollingInterval;
  final SelectedJourneyMapBuilder? mapBuilder;

  @override
  State<SelectedJourneyTrackerPage> createState() =>
      _SelectedJourneyTrackerPageState();
}

class _SelectedJourneyTrackerPageState extends State<SelectedJourneyTrackerPage>
    with WidgetsBindingObserver {
  late final RealtimeTrackerController _controller;
  late List<RealtimeVehicleMarkerData?> _currentByLeg;
  late List<RealtimeVehicleMarkerData?> _lastKnownByLeg;
  Object? _observedSnapshot;
  JourneyMapData? _mapData;
  Object? _mapError;
  var _selectedLeg = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentByLeg = List.filled(widget.journey.legs.length, null);
    _lastKnownByLeg = List.filled(widget.journey.legs.length, null);
    _controller = RealtimeTrackerController(
      repository: widget.realtimeRepository,
      pollingInterval: widget.pollingInterval,
    )..addListener(_onControllerChanged);
    _loadMap();
    _controller.startPolling();
  }

  Future<void> _loadMap() async {
    setState(() {
      _mapData = null;
      _mapError = null;
    });
    try {
      final data = await widget.journeyMapRepository.loadJourney(
        widget.journey.recommendation,
      );
      if (mounted) setState(() => _mapData = data);
    } on Object catch (error) {
      if (mounted) setState(() => _mapError = error);
    }
  }

  void _onControllerChanged() {
    final snapshot = _controller.snapshot;
    if (snapshot != null && !identical(snapshot, _observedSnapshot)) {
      final match = matchSelectedJourneyVehicles(
        journey: widget.journey,
        vehicles: snapshot.vehicles,
      );
      _currentByLeg = match.byLeg.map(_markerFor).toList(growable: false);
      for (var index = 0; index < _currentByLeg.length; index++) {
        final current = _currentByLeg[index];
        if (current != null) _lastKnownByLeg[index] = current;
      }
      _observedSnapshot = snapshot;
    }
    if (mounted) setState(() {});
  }

  RealtimeVehicleMarkerData? _markerFor(RealtimeVehiclePosition? vehicle) {
    if (vehicle == null) return null;
    final markers = buildRealtimeVehicleMarkers([vehicle]);
    return markers.isEmpty ? null : markers.single;
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

  String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _formatUpdated(DateTime? value) {
    if (value == null) return 'Not provided';
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second ${local.hour >= 12 ? 'PM' : 'AM'}';
  }

  String get _status {
    if (_controller.snapshot == null && _controller.initialError != null) {
      return 'Unable to refresh realtime vehicle data.';
    }
    if (_controller.refreshWarning != null) {
      return _lastKnownByLeg[_selectedLeg] == null
          ? 'Unable to refresh realtime vehicle data.'
          : 'Unable to refresh — showing last known position';
    }
    if (_currentByLeg[_selectedLeg] != null) return 'Live tracking active';
    if (_lastKnownByLeg[_selectedLeg] != null) {
      return 'Live vehicle position is temporarily unavailable — showing last known position';
    }
    return 'Waiting for realtime vehicle data for this trip.';
  }

  @override
  Widget build(BuildContext context) {
    final summary = _buildSummary();
    final map = _buildMap();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Journey'),
        actions: [
          IconButton(
            key: const Key('refresh-selected-journey'),
            onPressed: _controller.isRefreshing ? null : _controller.refresh,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > constraints.maxHeight) {
              return Row(
                children: [
                  SizedBox(
                    width: constraints.maxWidth.clamp(300, 380).toDouble(),
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
                Flexible(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: summary,
                  ),
                ),
                Expanded(flex: 3, child: map),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final activeLeg = widget.journey.legs[_selectedLeg];
    final current = _currentByLeg[_selectedLeg];
    final displayed = current ?? _lastKnownByLeg[_selectedLeg];
    final routeLabel = widget.journey.legs
        .map((leg) => leg.routeName)
        .join(' → ');
    return Column(
      key: const Key('selected-journey-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(routeLabel, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          '${widget.journey.originStopName} → '
          '${widget.journey.destinationStopName}',
        ),
        if (widget.journey.transferStopName case final transfer?)
          Text('Transfer at $transfer'),
        const SizedBox(height: 12),
        Text('Scheduled', style: Theme.of(context).textTheme.labelLarge),
        Text(
          '${_formatTime(widget.journey.scheduledDeparture)} → '
          '${_formatTime(widget.journey.scheduledArrival)}',
        ),
        if (widget.journey.isTransfer) ...[
          const SizedBox(height: 16),
          SegmentedButton<int>(
            key: const Key('selected-leg-selector'),
            segments: [
              for (var index = 0; index < widget.journey.legs.length; index++)
                ButtonSegment(
                  value: index,
                  label: Text(
                    'Leg ${index + 1}: ${widget.journey.legs[index].routeName}',
                  ),
                ),
            ],
            selected: {_selectedLeg},
            onSelectionChanged: (selection) {
              setState(() => _selectedLeg = selection.single);
            },
          ),
        ],
        const SizedBox(height: 16),
        Text('Selected leg: ${activeLeg.routeName}'),
        const SizedBox(height: 8),
        Text(
          _status,
          key: const Key('selected-tracking-status'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (_controller.isInitialLoading) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (displayed != null) ...[
          const SizedBox(height: 12),
          Text('Live bus', style: Theme.of(context).textTheme.labelLarge),
          Text('Vehicle: ${_displayValue(displayed.vehicle.vehicleId)}'),
          Text('Last updated: ${_formatUpdated(displayed.vehicle.timestamp)}'),
          if (current == null) const Text('Last known position'),
        ],
      ],
    );
  }

  Widget _buildMap() {
    final displayed =
        _currentByLeg[_selectedLeg] ?? _lastKnownByLeg[_selectedLeg];
    final markers = displayed == null
        ? const <RealtimeVehicleMarkerData>[]
        : [displayed];
    if (_mapError != null) {
      final fallbackMap = markers.isEmpty
          ? const SizedBox.shrink()
          : widget.mapBuilder?.call(
                  const JourneyMapData(stops: [], legs: []),
                  markers,
                ) ??
                JourneyRouteMap(
                  data: const JourneyMapData(stops: [], legs: []),
                  realtimeMarkers: markers,
                );
      return Stack(
        children: [
          Positioned.fill(child: fallbackMap),
          Center(
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Planned route is currently unavailable.'),
                    TextButton(
                      key: const Key('retry-selected-route'),
                      onPressed: _loadMap,
                      child: const Text('Retry route'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    final data = _mapData;
    if (data == null) return const Center(child: CircularProgressIndicator());
    return widget.mapBuilder?.call(data, markers) ??
        JourneyRouteMap(data: data, realtimeMarkers: markers);
  }

  String _displayValue(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : 'Not provided';
}
