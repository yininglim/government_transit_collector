import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';
import 'package:government_transit_collector/features/journey_map/data/journey_map_repository.dart';
import 'package:government_transit_collector/features/journey_map/presentation/route_map_page.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/journey_progress_calculator.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_realtime_matcher.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/selected_journey_tracking.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_models.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/trip_progress_repository.dart';
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
    this.tripProgressRepository,
    this.pollingInterval = realtimePollingInterval,
    this.mapBuilder,
    super.key,
  });

  final SelectedJourneyTracking journey;
  final RealtimeVehicleRepository realtimeRepository;
  final JourneyMapRepository journeyMapRepository;
  final TripProgressRepository? tripProgressRepository;
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
  late List<JourneyProgressCalculator?> _progressCalculators;
  late List<JourneyProgressState?> _progressByLeg;
  late List<Object?> _progressErrors;
  late List<bool> _progressLoading;
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
    _progressCalculators = List.filled(widget.journey.legs.length, null);
    _progressByLeg = List.filled(widget.journey.legs.length, null);
    _progressErrors = List.filled(widget.journey.legs.length, null);
    _progressLoading = List.filled(widget.journey.legs.length, true);
    _controller = RealtimeTrackerController(
      repository: widget.realtimeRepository,
      pollingInterval: widget.pollingInterval,
    )..addListener(_onControllerChanged);
    _loadMap();
    _loadAllProgressData();
    _controller.startPolling();
  }

  Future<void> _loadAllProgressData() async {
    await Future.wait([
      for (var index = 0; index < widget.journey.legs.length; index++)
        _loadProgressData(index),
    ]);
  }

  Future<void> _loadProgressData(int index) async {
    if (mounted) {
      setState(() {
        _progressLoading[index] = true;
        _progressErrors[index] = null;
      });
    }
    try {
      final repository =
          widget.tripProgressRepository ?? GtfsTripProgressRepository();
      final data = await repository.loadTrip(widget.journey.legs[index].tripId);
      if (!mounted) return;
      setState(() {
        _progressCalculators[index] = JourneyProgressCalculator(data);
        _progressLoading[index] = false;
        _updateProgressForLeg(index);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _progressErrors[index] = error;
        _progressLoading[index] = false;
      });
    }
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
        if (current != null) {
          _lastKnownByLeg[index] = current;
          _updateProgressForLeg(index);
        }
      }
      _observedSnapshot = snapshot;
    }
    if (mounted) setState(() {});
  }

  void _updateProgressForLeg(int index) {
    final marker = _currentByLeg[index];
    final calculator = _progressCalculators[index];
    if (marker == null || calculator == null) return;
    _progressByLeg[index] = calculator.calculate(
      vehicleCoordinate: MapCoordinate(marker.latitude, marker.longitude),
      timestamp: marker.vehicle.timestamp,
      previous: _progressByLeg[index],
    );
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
    final local = transitServiceDateTime(value);
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
        const SizedBox(height: 16),
        _buildProgressSummary(currentIsLive: current != null),
      ],
    );
  }

  Widget _buildProgressSummary({required bool currentIsLive}) {
    if (_progressLoading[_selectedLeg]) {
      return const Column(
        key: Key('route-progress-loading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Route progress'),
          SizedBox(height: 8),
          LinearProgressIndicator(),
        ],
      );
    }
    if (_progressErrors[_selectedLeg] != null) {
      return Column(
        key: const Key('route-progress-error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Unable to load route progress information.'),
          TextButton(
            key: const Key('retry-route-progress'),
            onPressed: () => _loadProgressData(_selectedLeg),
            child: const Text('Retry progress'),
          ),
        ],
      );
    }
    final progress = _progressByLeg[_selectedLeg];
    if (progress == null) {
      return const Text(
        'Live route progress will appear when this trip has realtime vehicle data.',
        key: Key('route-progress-waiting'),
      );
    }
    if (progress.availability == JourneyProgressAvailability.shapeUnavailable) {
      return const Text(
        'Route shape is unavailable, so live progress cannot be estimated.',
        key: Key('route-progress-shape-unavailable'),
      );
    }
    if (progress.availability == JourneyProgressAvailability.offRoute) {
      return const Text(
        'Live vehicle position is temporarily outside the expected route.',
        key: Key('route-progress-off-route'),
      );
    }
    final recentCompleted = progress.completedStops.reversed.take(3).toList();
    return Column(
      key: const Key('route-progress-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Route progress',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Spacer(),
            if (progress.progressFraction case final fraction?)
              Text('${(fraction * 100).round()}%'),
          ],
        ),
        if (!currentIsLive)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Last known route progress'),
          ),
        if (progress.nearestStop case final nearest?) ...[
          const SizedBox(height: 8),
          Text('Near: ${nearest.stopName}'),
        ],
        if (progress.nextStop case final next?)
          Text('Next stop: ${next.stopName}'),
        if (recentCompleted.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Passed', style: Theme.of(context).textTheme.labelLarge),
          for (final stop in recentCompleted.reversed)
            Text('✓ ${stop.stopName}'),
        ],
        if (progress.upcomingStops.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Upcoming Stops', style: Theme.of(context).textTheme.labelLarge),
          for (var index = 0; index < progress.upcomingStops.length; index++)
            Text('${index + 1}. ${progress.upcomingStops[index].stopName}'),
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
