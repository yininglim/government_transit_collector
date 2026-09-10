import 'package:flutter/material.dart';
import 'package:government_transit_collector/features/realtime_vehicle/presentation/realtime_vehicle_marker_data.dart';

const realtimeMarkerMovementDuration = Duration(seconds: 2);

typedef AnimatedRealtimeVehicleBuilder =
    Widget Function(
      BuildContext context,
      List<RealtimeVehicleMarkerData> markers,
      Set<String> movingIdentities,
    );

class AnimatedRealtimeVehicleLayer extends StatefulWidget {
  const AnimatedRealtimeVehicleLayer({
    required this.markers,
    required this.builder,
    this.duration = realtimeMarkerMovementDuration,
    super.key,
  });

  final List<RealtimeVehicleMarkerData> markers;
  final AnimatedRealtimeVehicleBuilder builder;
  final Duration duration;

  @override
  State<AnimatedRealtimeVehicleLayer> createState() =>
      _AnimatedRealtimeVehicleLayerState();
}

class _AnimatedRealtimeVehicleLayerState
    extends State<AnimatedRealtimeVehicleLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Map<String, _Coordinate> _displayed = {};
  final Map<String, _CoordinateTransition> _transitions = {};

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(_advanceAnimation)
      ..addStatusListener(_handleAnimationStatus);
    for (final marker in widget.markers) {
      _displayed[marker.identity] = _Coordinate(
        marker.latitude,
        marker.longitude,
      );
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedRealtimeVehicleLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    _controller.stop();
    _transitions.clear();

    final latestIdentities = widget.markers
        .map((marker) => marker.identity)
        .toSet();
    _displayed.removeWhere(
      (identity, coordinate) => !latestIdentities.contains(identity),
    );
    for (final marker in widget.markers) {
      final latest = _Coordinate(marker.latitude, marker.longitude);
      final previous = _displayed[marker.identity];
      if (previous == null) {
        _displayed[marker.identity] = latest;
      } else if (previous != latest) {
        _transitions[marker.identity] = _CoordinateTransition(
          from: previous,
          to: latest,
        );
      }
    }
    if (_transitions.isNotEmpty) _controller.forward(from: 0);
  }

  void _advanceAnimation() {
    if (!mounted) return;
    final progress = Curves.easeInOut.transform(_controller.value);
    setState(() {
      for (final entry in _transitions.entries) {
        _displayed[entry.key] = entry.value.coordinateAt(progress);
      }
    });
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      for (final entry in _transitions.entries) {
        _displayed[entry.key] = entry.value.to;
      }
      _transitions.clear();
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_advanceAnimation)
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animatedMarkers = widget.markers
        .map((marker) {
          final coordinate =
              _displayed[marker.identity] ??
              _Coordinate(marker.latitude, marker.longitude);
          return RealtimeVehicleMarkerData(
            identity: marker.identity,
            vehicle: marker.vehicle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
          );
        })
        .toList(growable: false);
    return widget.builder(context, animatedMarkers, _transitions.keys.toSet());
  }
}

class _CoordinateTransition {
  const _CoordinateTransition({required this.from, required this.to});

  final _Coordinate from;
  final _Coordinate to;

  _Coordinate coordinateAt(double progress) => _Coordinate(
    from.latitude + (to.latitude - from.latitude) * progress,
    from.longitude + (to.longitude - from.longitude) * progress,
  );
}

class _Coordinate {
  const _Coordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is _Coordinate &&
      latitude == other.latitude &&
      longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}
