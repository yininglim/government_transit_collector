import 'dart:async';
import 'dart:io';

import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_history_collector.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/realtime_vehicle_repository.dart';
import 'package:government_transit_collector/features/realtime_vehicle/data/supabase_realtime_history_storage.dart';
// The pure-Dart client is supplied transitively by supabase_flutter. Importing
// it directly keeps this command-line collector independent of dart:ui.
// ignore: depend_on_referenced_packages
import 'package:supabase/supabase.dart';

Future<void> main(List<String> arguments) async {
  late final CollectorOptions options;
  try {
    options = CollectorOptions.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(CollectorOptions.usage);
    exitCode = 64;
    return;
  }

  final url = Platform.environment['SUPABASE_URL']?.trim();
  final serviceRoleKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY']
      ?.trim();
  if (!options.dryRun &&
      (url == null ||
          url.isEmpty ||
          serviceRoleKey == null ||
          serviceRoleKey.isEmpty)) {
    stderr.writeln(
      'Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the process environment.',
    );
    exitCode = 78;
    return;
  }

  final stopController = CollectorStopController();
  final sessionStarted = DateTime.now();
  final repository = DataGovMyRealtimeVehicleRepository();
  final supabaseClient = options.dryRun
      ? null
      : SupabaseClient(url!, serviceRoleKey!);
  final storage = supabaseClient == null
      ? null
      : SupabaseRealtimeHistoryStorage(supabaseClient);
  final collector = RealtimeHistoryCollector(
    repository: repository,
    storage: storage,
    interval: options.interval,
    dryRun: options.dryRun,
    once: options.once,
    wait: stopController.wait,
  );

  late final StreamSubscription<ProcessSignal> signalSubscription;
  Future<void>? signalCancellation;
  signalSubscription = ProcessSignal.sigint.watch().listen((_) {
    if (!stopController.isStopped) {
      // On Windows, unregister the console signal handler immediately. Keeping
      // the signal stream subscribed while awaiting shutdown can leave Dart's
      // Ctrl+C handler installed and PowerShell waiting on the process.
      signalCancellation ??= signalSubscription.cancel();
      stdout.writeln('\nStopping collector...');
      collector.requestStop();
      stopController.requestStop();
    }
  });
  final cleanup = CollectorCleanup([
    () async {
      await (signalCancellation ??= signalSubscription.cancel());
    },
    () async => stopController.dispose(),
    () async => repository.close(),
    if (storage != null) storage.close,
  ], onError: (error) => stderr.writeln('Shutdown cleanup warning: $error'));

  stdout.writeln('Starting MyBAS Johor historical collector');
  stdout.writeln('Interval: ${options.interval.inMinutes} minutes');
  if (options.dryRun) {
    stdout.writeln('Mode: dry run (Supabase writes disabled)');
  }
  stdout.writeln('Use Ctrl+C to stop.\n');
  try {
    await collector.run();
  } finally {
    await cleanup.run();
  }

  for (final line in sessionSummaryLines(
    collector.totals,
    DateTime.now().difference(sessionStarted),
  )) {
    stdout.writeln(line);
  }
}

typedef CleanupAction = Future<void> Function();

class CollectorCleanup {
  CollectorCleanup(this._actions, {this.onError});
  final List<CleanupAction> _actions;
  final void Function(Object error)? onError;
  Future<void>? _cleanup;

  Future<void> run() => _cleanup ??= _runOnce();

  Future<void> _runOnce() async {
    for (final action in _actions) {
      try {
        await action();
      } on Object catch (error) {
        onError?.call(error);
      }
    }
  }
}

class CollectorStopController {
  bool _isStopped = false;
  Timer? _timer;
  Completer<void>? _activeWait;

  bool get isStopped => _isStopped;

  Future<void> wait(Duration duration) {
    if (_isStopped) return Future<void>.value();
    final completion = Completer<void>();
    _activeWait = completion;
    _timer = Timer(duration, () {
      if (!completion.isCompleted) completion.complete();
    });
    return completion.future.whenComplete(() {
      if (identical(_activeWait, completion)) {
        _timer = null;
        _activeWait = null;
      }
    });
  }

  void requestStop() {
    if (_isStopped) return;
    _isStopped = true;
    _timer?.cancel();
    _timer = null;
    final wait = _activeWait;
    if (wait != null && !wait.isCompleted) wait.complete();
  }

  void dispose() => requestStop();
}

class CollectorOptions {
  const CollectorOptions({
    required this.interval,
    required this.once,
    required this.dryRun,
  });
  final Duration interval;
  final bool once;
  final bool dryRun;

  static const usage =
      'Usage: dart run scripts/realtime_history_collector.dart '
      '[--once] [--dry-run] [--interval-minutes=N]';

  factory CollectorOptions.parse(List<String> arguments) {
    var once = false;
    var dryRun = false;
    var interval = defaultCollectionInterval;
    for (final argument in arguments) {
      if (argument == '--once') {
        once = true;
      } else if (argument == '--dry-run') {
        dryRun = true;
      } else if (argument.startsWith('--interval-minutes=')) {
        final value = int.tryParse(
          argument.substring('--interval-minutes='.length),
        );
        if (value == null || value <= 0) {
          throw const FormatException(
            '--interval-minutes must be a positive integer.',
          );
        }
        interval = Duration(minutes: value);
      } else {
        throw FormatException('Unknown option: $argument');
      }
    }
    return CollectorOptions(interval: interval, once: once, dryRun: dryRun);
  }
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

List<String> sessionSummaryLines(
  CollectorSessionTotals totals,
  Duration sessionDuration,
) => [
  '',
  'Collector stopped',
  'Session duration: ${formatDuration(sessionDuration)}',
  'Collection cycles: ${totals.cycles}',
  'Realtime records received: ${totals.received}',
  'Historical rows inserted: ${totals.inserted}',
  'Duplicates skipped: ${totals.duplicates}',
  'Invalid skipped: ${totals.invalid}',
  'Unmatched static trips skipped: ${totals.unmatchedStaticTrips}',
];
