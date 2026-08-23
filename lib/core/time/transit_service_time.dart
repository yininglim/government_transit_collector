import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

const transitServiceTimezoneName = 'Asia/Singapore';

timezone.Location? _transitServiceLocation;

timezone.Location get transitServiceLocation {
  final existing = _transitServiceLocation;
  if (existing != null) return existing;
  timezone_data.initializeTimeZones();
  return _transitServiceLocation = timezone.getLocation(
    transitServiceTimezoneName,
  );
}

/// Converts an absolute instant to the wall-clock date and time used by GTFS.
timezone.TZDateTime transitServiceDateTime(DateTime instant) =>
    timezone.TZDateTime.from(instant.toUtc(), transitServiceLocation);

timezone.TZDateTime currentTransitServiceDateTime({DateTime Function()? now}) =>
    transitServiceDateTime((now ?? DateTime.now)());
