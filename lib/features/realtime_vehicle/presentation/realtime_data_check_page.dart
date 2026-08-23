import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/gtfs_realtime_decoder.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_position.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/static_trip_matcher.dart';

class RealtimeDataCheckPage extends StatefulWidget {
  const RealtimeDataCheckPage({
    required this.repository,
    required this.tripMatcher,
    super.key,
  });

  final RealtimeVehicleRepository repository;
  final StaticTripMatcher tripMatcher;

  @override
  State<RealtimeDataCheckPage> createState() => _RealtimeDataCheckPageState();
}

class _RealtimeDataCheckPageState extends State<RealtimeDataCheckPage> {
  static const _visibleVehicleLimit = 20;

  RealtimeFeedSnapshot? _snapshot;
  Set<String>? _knownTripIds;
  String? _error;
  String? _matchingWarning;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading && _snapshot != null) return;
    setState(() {
      _loading = true;
      _error = null;
      _matchingWarning = null;
    });
    try {
      final snapshot = await widget.repository.fetchVehiclePositions();
      Set<String>? knownTripIds;
      String? matchingWarning;
      try {
        knownTripIds = await widget.tripMatcher.findKnownTripIds(
          snapshot.vehicles
              .map((vehicle) => vehicle.tripId)
              .whereType<String>(),
        );
      } on Object {
        matchingWarning =
            'Vehicles loaded, but GTFS Static trip matching is unavailable.';
      }
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _knownTripIds = knownTripIds;
        _matchingWarning = matchingWarning;
        _loading = false;
      });
    } on RealtimeVehicleReadException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load realtime vehicle positions.';
        _loading = false;
      });
    }
  }

  String _formatTimestamp(BuildContext context, DateTime? timestamp) {
    if (timestamp == null) return 'Not provided';
    final local = transitServiceDateTime(timestamp);
    final date =
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime Data Check'),
        actions: [
          IconButton(
            key: const Key('refresh-realtime'),
            tooltip: 'Refresh realtime data',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _snapshot == null) {
      return const Center(
        key: Key('realtime-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null && _snapshot == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('retry-realtime'),
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final snapshot = _snapshot!;
    final visibleVehicles = snapshot.vehicles
        .take(_visibleVehicleLimit)
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        return RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            key: const Key('realtime-vehicle-list'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverList.list(
                  children: [
                    Text(
                      'Realtime Vehicle Positions',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Vehicles received: ${snapshot.vehicles.length}',
                      key: const Key('realtime-vehicle-count'),
                    ),
                    Text(
                      'Last feed update: '
                      '${_formatTimestamp(context, snapshot.feedTimestamp)}',
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                    if (_matchingWarning != null) ...[
                      const SizedBox(height: 8),
                      _StatusNotice(
                        key: const Key('trip-matching-warning'),
                        message: _matchingWarning!,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      _StatusNotice(message: _error!),
                    ],
                    if (snapshot.vehicles.length > _visibleVehicleLimit) ...[
                      const SizedBox(height: 8),
                      const Text('Showing the first 20 vehicles.'),
                    ],
                    if (visibleVehicles.isEmpty) ...[
                      const SizedBox(height: 32),
                      const Center(
                        key: Key('realtime-empty'),
                        child: Column(
                          children: [
                            Icon(Icons.directions_bus_outlined, size: 48),
                            SizedBox(height: 12),
                            Text(
                              'No vehicle positions are in the current feed.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (visibleVehicles.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: landscape ? 2 : 1,
                      mainAxisExtent: 220,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _VehicleCard(
                        vehicle: visibleVehicles[index],
                        matched: _knownTripIds == null
                            ? null
                            : visibleVehicles[index].tripId != null &&
                                  _knownTripIds!.contains(
                                    visibleVehicles[index].tripId,
                                  ),
                        formatTimestamp: (timestamp) =>
                            _formatTimestamp(context, timestamp),
                      ),
                      childCount: visibleVehicles.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.matched,
    required this.formatTimestamp,
  });

  final RealtimeVehiclePosition vehicle;
  final bool? matched;
  final String Function(DateTime? timestamp) formatTimestamp;

  String _text(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : 'Not provided';

  String _coordinate(double? value) =>
      value == null ? 'Not provided' : value.toStringAsFixed(6);

  @override
  Widget build(BuildContext context) {
    final matchLabel = vehicle.tripId == null
        ? 'Unavailable'
        : matched == null
        ? 'Not checked'
        : matched!
        ? 'Yes'
        : 'No';
    return Card(
      key: ObjectKey(vehicle),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _text(vehicle.routeId),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('Vehicle: ${_text(vehicle.vehicleId)}'),
            Text('Trip matched: $matchLabel'),
            Text('Latitude: ${_coordinate(vehicle.latitude)}'),
            Text('Longitude: ${_coordinate(vehicle.longitude)}'),
            const Spacer(),
            Text('Updated: ${formatTimestamp(vehicle.timestamp)}'),
          ],
        ),
      ),
    );
  }
}

class _StatusNotice extends StatelessWidget {
  const _StatusNotice({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
    );
  }
}
