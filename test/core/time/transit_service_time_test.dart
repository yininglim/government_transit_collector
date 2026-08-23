import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';

void main() {
  test('converts the current instant to Asia/Singapore wall-clock time', () {
    final result = currentTransitServiceDateTime(
      now: () => DateTime.utc(2026, 8, 21, 23, 53),
    );

    expect(result.location.name, transitServiceTimezoneName);
    expect(result.year, 2026);
    expect(result.month, 8);
    expect(result.day, 22);
    expect(result.hour, 7);
    expect(result.minute, 53);
  });

  test('conversion depends on the instant, not the source timezone', () {
    final utc = DateTime.utc(2026, 8, 21, 11, 53);
    final plusEight = DateTime.parse('2026-08-21T19:53:00+08:00');

    expect(transitServiceDateTime(utc), transitServiceDateTime(plusEight));
    expect(transitServiceDateTime(utc).hour, 19);
  });
}
