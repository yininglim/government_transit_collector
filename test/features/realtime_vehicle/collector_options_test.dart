import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_history_collector.dart';
import '../../../scripts/realtime_history_collector.dart' as script;

void main() {
  test('interval argument accepts a positive integer', () {
    final options = script.CollectorOptions.parse(['--interval-minutes=5']);
    expect(options.interval, const Duration(minutes: 5));
  });

  test('interval argument rejects zero and malformed values', () {
    expect(
      () => script.CollectorOptions.parse(['--interval-minutes=0']),
      throwsFormatException,
    );
    expect(
      () => script.CollectorOptions.parse(['--interval-minutes=no']),
      throwsFormatException,
    );
  });

  test('stop controller cancels an active long interval immediately', () async {
    final controller = script.CollectorStopController();
    final wait = controller.wait(const Duration(hours: 1));

    controller.requestStop();

    await expectLater(wait, completes);
    expect(controller.isStopped, isTrue);
  });

  test('disposed stop controller does not create later timers', () async {
    final controller = script.CollectorStopController()..dispose();

    await expectLater(controller.wait(const Duration(hours: 1)), completes);
  });

  test('cleanup actions run exactly once', () async {
    var signalCanceled = 0;
    var repositoryClosed = 0;
    var storageDisposed = 0;
    final cleanup = script.CollectorCleanup([
      () async => signalCanceled++,
      () async => repositoryClosed++,
      () async => storageDisposed++,
    ]);

    await Future.wait([cleanup.run(), cleanup.run()]);

    expect(signalCanceled, 1);
    expect(repositoryClosed, 1);
    expect(storageDisposed, 1);
  });

  test('session summary is produced after shutdown', () {
    final totals = CollectorSessionTotals()
      ..cycles = 2
      ..received = 10
      ..inserted = 8;

    final lines = script.sessionSummaryLines(
      totals,
      const Duration(minutes: 2),
    );

    expect(lines, contains('Collector stopped'));
    expect(lines, contains('Collection cycles: 2'));
    expect(lines, contains('Historical rows inserted: 8'));
  });
}
