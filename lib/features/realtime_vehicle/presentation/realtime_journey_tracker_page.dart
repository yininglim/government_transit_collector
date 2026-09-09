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

enum RealtimeTrackerView { allBuses, selectedBus }

class RealtimeJourneyTrackerPage extends StatefulWidget {
  const RealtimeJourneyTrackerPage({
    this.showPageHeader = true,
    required this.repository,
    required this.tripMatcher,
    this.pollingInterval = realtimePollingInterval,
    this.mapBuilder,
    this.routeMetadataRepository,
    this.tripProgressRepository,
    this.now,
    super.key,
  });

  final RealtimeVehicleRepository repository;
  final StaticTripMatcher tripMatcher;
  final Duration pollingInterval;
  final RealtimeMapBuilder? mapBuilder;
  final RealtimeRouteMetadataRepository? routeMetadataRepository;
  final TripProgressRepository? tripProgressRepository;
  final DateTime Function()? now;

  final bool showPageHeader;

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
  final _mapKey = GlobalKey<_RealtimeVehicleMapState>();
  final _selectedPanelKey = GlobalKey<_SelectedVehicleProgressPanelState>();
  bool _mapExpanded = false;
  String? _selectedVehicleIdentity;
  RealtimeVehicleMarkerData? _lastSelectedMarker;
  RealtimeTrackerView _trackerView = RealtimeTrackerView.allBuses;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = RealtimeTrackerController(
      repository: widget.repository,
      tripMatcher: widget.tripMatcher,
      pollingInterval: widget.pollingInterval,
      now: widget.now,
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
      // Android may emit inactive/resumed while recreating its surface for an
      // orientation change. Resuming the one polling timer must not masquerade
      // as a new successful check merely because the layout rotated.
      _controller.startPolling(fetchImmediately: false);
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
    final viewSelected = await showModalBottomSheet<bool>(
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
        showViewSelectedAction: true,
      ),
    );
    if (!mounted) return;
    setState(() {
      _selectedVehicleIdentity = marker.identity;
      _lastSelectedMarker = _markerForIdentity(marker.identity) ?? marker;
      if (viewSelected == true) {
        _trackerView = RealtimeTrackerView.selectedBus;
      }
    });
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
      appBar: widget.showPageHeader
          ? AppBar(title: const Text('Realtime Journey Tracker'))
          : null,
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
    final selectedMarker = visibleMarkers
        .where((marker) => marker.identity == _selectedVehicleIdentity)
        .firstOrNull;
    if (selectedMarker != null) _lastSelectedMarker = selectedMarker;
    final status = _TrackerStatusPanel(
      vehicleCount: allMarkers.length,
      feedTimestamp: _controller.snapshot!.feedTimestamp,
      lastSuccessfulRefreshAt: _controller.lastSuccessfulRefreshAt,
      isRefreshing: _controller.isRefreshing,
      pollingInterval: widget.pollingInterval,
      warning: _controller.refreshWarning ?? _controller.matchingWarning,
      routes: routes,
      selectedRoute: effectiveRoute,
      routeMetadata: _routeMetadata,
      routeMetadataUnavailable: _routeMetadataError != null,
      selectedVehicleCount: visibleMarkers.length,
      formatTimestamp: _formatTimestamp,
      onRouteChanged: (route) => setState(() {
        _selectedRoute = route;
        _selectedVehicleIdentity = null;
        _lastSelectedMarker = null;
        _trackerView = RealtimeTrackerView.allBuses;
      }),
      onRefresh: _controller.isRefreshing ? null : _controller.refresh,
      now: widget.now ?? DateTime.now,
    );
    final mapMarkers = _trackerView == RealtimeTrackerView.selectedBus
        ? [?selectedMarker]
        : visibleMarkers;
    final map = mapMarkers.isEmpty
        ? _NoRealtimeVehicles(
            routeName: effectiveRoute == null
                ? null
                : _routeMetadata[effectiveRoute]?.passengerShortName ??
                      effectiveRoute,
          )
        : widget.mapBuilder?.call(mapMarkers, _showVehicleDetails) ??
              RealtimeVehicleMap(
                key: _mapKey,
                markers: mapMarkers,
                onMarkerTap: _showVehicleDetails,
                viewMode: _trackerView,
                selectedVehicleIdentity: _selectedVehicleIdentity,
                cameraScope: effectiveRoute ?? 'all-routes',
              );

    final mapWithSizeControl = Stack(
      children: [
        Positioned.fill(child: map),
        Positioned(
          top: 12,
          right: 12,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            shape: const CircleBorder(),
            elevation: 3,
            child: IconButton(
              key: Key(
                _mapExpanded ? 'collapse-realtime-map' : 'expand-realtime-map',
              ),
              tooltip: _mapExpanded ? 'Restore map size' : 'Expand map',
              onPressed: () => setState(() => _mapExpanded = !_mapExpanded),
              icon: Icon(
                _mapExpanded ? Icons.fullscreen_exit : Icons.open_in_full,
              ),
            ),
          ),
        ),
      ],
    );

    if (_mapExpanded) {
      return mapWithSizeControl;
    }

    final selectedDetails = _lastSelectedMarker == null
        ? null
        : _SelectedVehicleProgressPanel(
            key: _selectedPanelKey,
            initialMarker: _lastSelectedMarker!,
            route: _routeMetadata[_lastSelectedMarker!.vehicle.routeId],
            routeFallback: _displayValue(_lastSelectedMarker!.vehicle.routeId),
            realtimeUpdates: _controller,
            resolveCurrentMarker: () =>
                _markerForIdentity(_lastSelectedMarker!.identity),
            loadTrip: _loadTripProgress,
            isCurrentlyLive: selectedMarker != null,
            detailed: _trackerView == RealtimeTrackerView.selectedBus,
            onViewSelected: () =>
                setState(() => _trackerView = RealtimeTrackerView.selectedBus),
            onBackToAllBuses: () =>
                setState(() => _trackerView = RealtimeTrackerView.allBuses),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      status,
                      if (selectedDetails != null) ...[
                        const SizedBox(height: 12),
                        selectedDetails,
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(child: mapWithSizeControl),
            ],
          );
        }
        if (selectedDetails == null) {
          return Column(
            children: [
              Padding(padding: const EdgeInsets.all(16), child: status),
              Expanded(child: mapWithSizeControl),
            ],
          );
        }
        final mapHeight = (constraints.maxHeight * 0.42).clamp(260.0, 420.0);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: status,
              ),
              SizedBox(height: mapHeight, child: mapWithSizeControl),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: selectedDetails,
              ),
            ],
          ),
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
    this.showViewSelectedAction = false,
  });

  final RealtimeVehicleMarkerData initialMarker;
  final RealtimeRouteMetadata? route;
  final String routeFallback;
  final Listenable realtimeUpdates;
  final RealtimeVehicleMarkerData? Function() resolveCurrentMarker;
  final Future<TripProgressData> Function(String exactTripId) loadTrip;
  final String Function(DateTime?) formatTimestamp;
  final Duration staleThreshold;
  final bool showViewSelectedAction;

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
            if (widget.showViewSelectedAction) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('view-selected-bus-sheet'),
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.gps_fixed),
                  label: const Text('View Selected Bus'),
                ),
              ),
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

class _SelectedVehicleProgressPanel extends StatefulWidget {
  const _SelectedVehicleProgressPanel({
    required this.initialMarker,
    required this.route,
    required this.routeFallback,
    required this.realtimeUpdates,
    required this.resolveCurrentMarker,
    required this.loadTrip,
    required this.isCurrentlyLive,
    required this.detailed,
    required this.onViewSelected,
    required this.onBackToAllBuses,
    super.key,
  });

  final RealtimeVehicleMarkerData initialMarker;
  final RealtimeRouteMetadata? route;
  final String routeFallback;
  final Listenable realtimeUpdates;
  final RealtimeVehicleMarkerData? Function() resolveCurrentMarker;
  final Future<TripProgressData> Function(String exactTripId) loadTrip;
  final bool isCurrentlyLive;
  final bool detailed;
  final VoidCallback onViewSelected;
  final VoidCallback onBackToAllBuses;

  @override
  State<_SelectedVehicleProgressPanel> createState() =>
      _SelectedVehicleProgressPanelState();
}

class _SelectedVehicleProgressPanelState
    extends State<_SelectedVehicleProgressPanel> {
  late RealtimeVehicleMarkerData _marker;
  JourneyProgressCalculator? _calculator;
  JourneyProgressState? _progress;
  Object? _error;
  var _loading = false;
  var _loadGeneration = 0;
  final _timelineController = ScrollController();

  @override
  void initState() {
    super.initState();
    _marker = widget.initialMarker;
    widget.realtimeUpdates.addListener(_onRealtimeChanged);
    _loadExactTrip();
  }

  @override
  void didUpdateWidget(covariant _SelectedVehicleProgressPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.realtimeUpdates != widget.realtimeUpdates) {
      oldWidget.realtimeUpdates.removeListener(_onRealtimeChanged);
      widget.realtimeUpdates.addListener(_onRealtimeChanged);
    }
    if (oldWidget.initialMarker.identity != widget.initialMarker.identity) {
      _marker = widget.initialMarker;
      _calculator = null;
      _progress = null;
      _loadExactTrip();
    }
  }

  @override
  void dispose() {
    widget.realtimeUpdates.removeListener(_onRealtimeChanged);
    _timelineController.dispose();
    super.dispose();
  }

  void _onRealtimeChanged() {
    final latest = widget.resolveCurrentMarker();
    if (latest == null || !mounted) return;
    final previousTripId = _marker.vehicle.tripId?.trim();
    final latestTripId = latest.vehicle.tripId?.trim();
    if (latestTripId != previousTripId) {
      setState(() {
        _marker = latest;
        _calculator = null;
        _progress = null;
      });
      _loadExactTrip();
      return;
    }
    setState(() {
      _marker = latest;
      _calculateProgress();
    });
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
      _scrollToCurrentProgress();
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

  void _scrollToCurrentProgress() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_timelineController.hasClients) return;
      final completed = _completedStopCount;
      final target = (completed * 54.0 - 80).clamp(
        0.0,
        _timelineController.position.maxScrollExtent,
      );
      _timelineController.jumpTo(target);
    });
  }

  List<TrackedTripStop> get _orderedStops =>
      _calculator?.stopProgress.map((item) => item.stop).toList() ?? const [];

  int get _completedStopCount {
    final completedIds = _progress?.completedStops
        .map((stop) => stop.stopId)
        .toSet();
    if (completedIds == null) return 0;
    return _orderedStops
        .where((stop) => completedIds.contains(stop.stopId))
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final routeName = widget.route?.passengerShortName ?? widget.routeFallback;
    final longName = widget.route?.passengerLongName;
    return Card(
      key: const Key('selected-bus-progress-panel'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Selected Bus', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              longName == null ? routeName : '$routeName • $longName',
              key: const Key('selected-bus-route'),
            ),
            Text('Vehicle: ${_marker.vehicle.vehicleId ?? 'Not provided'}'),
            if (!widget.isCurrentlyLive)
              Text(
                'This bus is temporarily absent from the latest feed.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator(
                key: Key('selected-route-progress-loading'),
              )
            else if (_error != null)
              const Text(
                'Route progress is unavailable for this exact trip.',
                key: Key('selected-route-progress-error'),
              )
            else if (_progress?.availability !=
                JourneyProgressAvailability.available)
              const Text(
                'Route progress is unavailable for this position.',
                key: Key('selected-route-progress-unavailable'),
              )
            else if (widget.detailed)
              _buildProgress(context)
            else
              _buildBriefProgress(context),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: widget.detailed
                  ? OutlinedButton.icon(
                      key: const Key('back-to-all-buses'),
                      onPressed: widget.onBackToAllBuses,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to All Buses'),
                    )
                  : FilledButton.icon(
                      key: const Key('view-selected-bus'),
                      onPressed: widget.onViewSelected,
                      icon: const Icon(Icons.gps_fixed),
                      label: const Text('View Selected Bus'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBriefProgress(BuildContext context) => Column(
    key: const Key('selected-bus-brief'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Next Stop', style: Theme.of(context).textTheme.labelLarge),
      Text(
        _progress?.nextStop?.stopName ?? 'Route trip completed',
        key: const Key('selected-next-stop'),
      ),
    ],
  );

  Widget _buildProgress(BuildContext context) {
    final stops = _orderedStops;
    final completed = _completedStopCount.clamp(0, stops.length);
    final remaining = (stops.length - completed).clamp(0, stops.length);
    final fraction = stops.isEmpty ? 0.0 : completed / stops.length;
    return Column(
      key: const Key('selected-route-progress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Next Stop', style: Theme.of(context).textTheme.labelLarge),
        Text(
          _progress?.nextStop?.stopName ?? 'Route trip completed',
          key: const Key('selected-next-stop'),
        ),
        const SizedBox(height: 12),
        Text('Route Progress', style: Theme.of(context).textTheme.titleSmall),
        Text(
          'Stop $completed of ${stops.length} • $remaining stops remaining',
          key: const Key('stop-progress-summary'),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          key: const Key('stop-progress-indicator'),
          value: fraction,
        ),
        const SizedBox(height: 14),
        Text('Route Stops', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        SizedBox(
          height: 260,
          child: ListView.builder(
            key: const Key('route-stop-timeline'),
            controller: _timelineController,
            itemCount: stops.length + 1,
            itemBuilder: (context, index) {
              if (index == completed) {
                return const _RouteTimelineRow.currentProgress();
              }
              final stopIndex = index > completed ? index - 1 : index;
              final stop = stops[stopIndex];
              final passed = stopIndex < completed;
              final next =
                  !passed && stop.stopId == _progress?.nextStop?.stopId;
              return _RouteTimelineRow.stop(
                stop: stop,
                passed: passed,
                next: next,
                first: index == 0,
                last: index == stops.length,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RouteTimelineRow extends StatelessWidget {
  const _RouteTimelineRow.stop({
    required this.stop,
    required this.passed,
    required this.next,
    required this.first,
    required this.last,
  }) : currentProgress = false;

  const _RouteTimelineRow.currentProgress()
    : stop = null,
      passed = false,
      next = false,
      first = false,
      last = false,
      currentProgress = true;

  final TrackedTripStop? stop;
  final bool passed;
  final bool next;
  final bool first;
  final bool last;
  final bool currentProgress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completedColor = colors.primary;
    final remainingColor = colors.outlineVariant;
    final nodeColor = currentProgress || passed
        ? completedColor
        : colors.surface;
    final borderColor = currentProgress || passed
        ? completedColor
        : colors.outline;
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!first)
                  Positioned(
                    top: 0,
                    height: 27,
                    child: Container(
                      width: 3,
                      color: passed || currentProgress
                          ? completedColor
                          : remainingColor,
                    ),
                  ),
                if (!last)
                  Positioned(
                    bottom: 0,
                    height: 27,
                    child: Container(width: 3, color: remainingColor),
                  ),
                Container(
                  width: currentProgress ? 24 : 16,
                  height: currentProgress ? 24 : 16,
                  decoration: BoxDecoration(
                    color: nodeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 2),
                  ),
                  child: currentProgress
                      ? Icon(
                          Icons.directions_bus,
                          size: 15,
                          color: colors.onPrimary,
                        )
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              currentProgress ? 'Current Progress' : stop!.stopName,
              key: currentProgress
                  ? const Key('timeline-current-progress')
                  : ValueKey('timeline-stop-${stop!.stopId}'),
              style: passed ? TextStyle(color: colors.onSurfaceVariant) : null,
            ),
          ),
          if (next)
            Text(
              'NEXT',
              key: const Key('timeline-next-label'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackerStatusPanel extends StatelessWidget {
  const _TrackerStatusPanel({
    required this.vehicleCount,
    required this.feedTimestamp,
    required this.lastSuccessfulRefreshAt,
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
    required this.now,
  });

  final int vehicleCount;
  final DateTime? feedTimestamp;
  final DateTime? lastSuccessfulRefreshAt;
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
  final DateTime Function() now;

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
            _LiveUpdateIndicator(
              lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
              feedTimestamp: feedTimestamp,
              isRefreshing: isRefreshing,
              formatTimestamp: formatTimestamp,
              now: now,
              warning: warning,
            ),
            Text('Refresh interval: Every ${pollingInterval.inSeconds} sec'),
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
          ],
        ),
      ),
    );
  }
}

class _LiveUpdateIndicator extends StatefulWidget {
  const _LiveUpdateIndicator({
    required this.lastSuccessfulRefreshAt,
    required this.feedTimestamp,
    required this.isRefreshing,
    required this.formatTimestamp,
    required this.now,
    required this.warning,
  });

  final DateTime? lastSuccessfulRefreshAt;
  final DateTime? feedTimestamp;
  final bool isRefreshing;
  final String Function(DateTime?) formatTimestamp;
  final DateTime Function() now;
  final String? warning;

  @override
  State<_LiveUpdateIndicator> createState() => _LiveUpdateIndicatorState();
}

class _LiveUpdateIndicatorState extends State<_LiveUpdateIndicator> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _age() {
    final checked = widget.lastSuccessfulRefreshAt;
    if (checked == null) return 'No successful refresh yet';
    final seconds = widget.now().difference(checked).inSeconds.clamp(0, 9999);
    return '${seconds}s ago';
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('live-update-indicator'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            Icons.circle,
            size: 10,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          const Expanded(child: Text('Live')),
          if (widget.isRefreshing)
            const SizedBox.square(
              key: Key('live-update-spinner'),
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      Text('Last successful refresh: ${_age()}'),
      if (widget.warning != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.warning!,
                  key: const Key('tracker-warning'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      Tooltip(
        message: 'Vehicle feed timestamp',
        child: Text(
          'Vehicle data updated: '
          '${widget.formatTimestamp(widget.feedTimestamp)}',
        ),
      ),
    ],
  );
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
    this.viewMode = RealtimeTrackerView.allBuses,
    this.selectedVehicleIdentity,
    this.mapController,
    this.cameraScope = 'all-routes',
    super.key,
  });

  final List<RealtimeVehicleMarkerData> markers;
  final ValueChanged<RealtimeVehicleMarkerData> onMarkerTap;
  final RealtimeTrackerView viewMode;
  final String? selectedVehicleIdentity;
  final MapController? mapController;
  final Object cameraScope;

  @override
  State<RealtimeVehicleMap> createState() => _RealtimeVehicleMapState();
}

class _RealtimeVehicleMapState extends State<RealtimeVehicleMap>
    with SingleTickerProviderStateMixin {
  Object? _tileError;
  var _tileAttempt = 0;
  late final MapController _mapController;
  late final AnimationController _cameraController;
  LatLng? _cameraFrom;
  LatLng? _cameraTo;
  var _mapReady = false;
  var _cameraFitToken = 0;
  Object? _pendingCameraFitScope;
  var _mapTilesLoading = true;
  var _tileLoadToken = 0;
  int? _targetTileZoom;
  var _tileCompletionScheduled = false;

  @override
  void initState() {
    super.initState();
    _mapController = widget.mapController ?? MapController();
    _cameraController = AnimationController(
      vsync: this,
      duration: realtimeMarkerMovementDuration,
    )..addListener(_advanceCamera);
    if (widget.viewMode == RealtimeTrackerView.allBuses) {
      _cameraFitToken = 1;
      _pendingCameraFitScope = widget.cameraScope;
      _beginMapTileLoad();
    }
  }

  @override
  void didUpdateWidget(covariant RealtimeVehicleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final routeChanged = oldWidget.cameraScope != widget.cameraScope;
    final oldCoordinate = _selectedCoordinate(oldWidget.markers);
    final coordinate = _selectedCoordinate(widget.markers);
    final enteredFollowMode =
        oldWidget.viewMode != RealtimeTrackerView.selectedBus &&
        widget.viewMode == RealtimeTrackerView.selectedBus;
    final returnedToOverview =
        oldWidget.viewMode == RealtimeTrackerView.selectedBus &&
        widget.viewMode == RealtimeTrackerView.allBuses;
    final selectedBusChanged =
        oldWidget.selectedVehicleIdentity != widget.selectedVehicleIdentity;
    if (routeChanged) {
      _cameraController.stop();
      _beginMapTileLoad();
      _queueAllBusesCameraFit(widget.cameraScope);
    } else if (returnedToOverview) {
      _queueAllBusesCameraFit(widget.cameraScope);
    } else if (widget.viewMode == RealtimeTrackerView.selectedBus &&
        (enteredFollowMode ||
            selectedBusChanged ||
            coordinate != oldCoordinate)) {
      _followSelectedBus(animate: _mapReady);
    }
  }

  void _queueAllBusesCameraFit(Object expectedScope) {
    final token = ++_cameraFitToken;
    _pendingCameraFitScope = expectedScope;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyPendingCameraFit(expectedScope, token);
    });
  }

  void _applyPendingCameraFit(Object expectedScope, int token) {
    if (!mounted ||
        token != _cameraFitToken ||
        _pendingCameraFitScope != expectedScope ||
        widget.cameraScope != expectedScope ||
        widget.viewMode != RealtimeTrackerView.allBuses ||
        widget.markers.isEmpty) {
      return;
    }
    if (!_mapReady) return;
    final layoutSize = context.size;
    if (layoutSize == null ||
        _mapController.camera.nonRotatedSize != layoutSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyPendingCameraFit(expectedScope, token);
      });
      return;
    }
    _pendingCameraFitScope = null;
    final points = widget.markers
        .map((marker) => LatLng(marker.latitude, marker.longitude))
        .toList();
    if (points.length == 1) {
      _mapController.move(points.single, 15);
    } else {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(48),
          maxZoom: 16,
        ),
      );
    }
    _targetTileZoom = _mapController.camera.zoom.round();
  }

  void _beginMapTileLoad() {
    _tileLoadToken++;
    _targetTileZoom = null;
    _tileCompletionScheduled = false;
    _mapTilesLoading = true;
  }

  Widget _buildMapTile(BuildContext context, Widget tile, TileImage tileImage) {
    if (_mapTilesLoading &&
        !_tileCompletionScheduled &&
        !tileImage.loadError &&
        tileImage.readyToDisplay &&
        tileImage.coordinates.z == _targetTileZoom) {
      _tileCompletionScheduled = true;
      final token = _tileLoadToken;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _tileLoadToken) return;
        setState(() {
          _mapTilesLoading = false;
          _tileCompletionScheduled = false;
        });
      });
    }
    return tile;
  }

  void _handleMapEvent(MapEvent event) {
    if (event.source != MapEventSource.nonRotatedSizeChange ||
        widget.viewMode != RealtimeTrackerView.allBuses ||
        widget.markers.isEmpty) {
      return;
    }
    _beginMapTileLoad();
    _queueAllBusesCameraFit(widget.cameraScope);
    if (mounted) setState(() {});
  }

  void _completePendingCameraFitAfterLayout() {
    final expectedScope = _pendingCameraFitScope;
    if (expectedScope == null) return;
    final token = _cameraFitToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyPendingCameraFit(expectedScope, token);
    });
  }

  LatLng? _selectedCoordinate(List<RealtimeVehicleMarkerData> markers) {
    final identity = widget.selectedVehicleIdentity;
    if (identity == null) return null;
    final marker = markers
        .where((candidate) => candidate.identity == identity)
        .firstOrNull;
    return marker == null ? null : LatLng(marker.latitude, marker.longitude);
  }

  void _followSelectedBus({required bool animate}) {
    if (!_mapReady) return;
    final target = _selectedCoordinate(widget.markers);
    if (target == null) return;
    _cameraController.stop();
    if (!animate) {
      _mapController.move(target, _mapController.camera.zoom.clamp(15, 18));
      return;
    }
    _cameraFrom = _mapController.camera.center;
    _cameraTo = target;
    if (_cameraFrom == _cameraTo) return;
    _cameraController.forward(from: 0);
  }

  void _advanceCamera() {
    final from = _cameraFrom;
    final to = _cameraTo;
    if (!_mapReady || from == null || to == null) return;
    final progress = Curves.easeInOut.transform(_cameraController.value);
    _mapController.move(
      LatLng(
        from.latitude + (to.latitude - from.latitude) * progress,
        from.longitude + (to.longitude - from.longitude) * progress,
      ),
      _mapController.camera.zoom.clamp(15, 18),
    );
  }

  @override
  void dispose() {
    _cameraController
      ..removeListener(_advanceCamera)
      ..dispose();
    super.dispose();
  }

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
          mapController: _mapController,
          options: MapOptions(
            onMapEvent: _handleMapEvent,
            onMapReady: () {
              _mapReady = true;
              if (widget.viewMode == RealtimeTrackerView.selectedBus) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _followSelectedBus(animate: false);
                });
              } else {
                _completePendingCameraFitAfterLayout();
              }
            },
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
              tileBuilder: _buildMapTile,
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
                            key:
                                marker.identity ==
                                    widget.selectedVehicleIdentity
                                ? ValueKey('selected-${marker.identity}')
                                : null,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  marker.identity ==
                                      widget.selectedVehicleIdentity
                                  ? Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondary,
                                      width: 4,
                                    )
                                  : movingIdentities.contains(marker.identity)
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
                                  onTap: () => widget.onMarkerTap(
                                    widget.markers.firstWhere(
                                      (observation) =>
                                          observation.identity ==
                                          marker.identity,
                                    ),
                                  ),
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
        if (_mapTilesLoading)
          Positioned(
            key: const Key('realtime-map-loading'),
            top: 12,
            left: 12,
            child: IgnorePointer(
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
                elevation: 2,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Loading map…'),
                    ],
                  ),
                ),
              ),
            ),
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
