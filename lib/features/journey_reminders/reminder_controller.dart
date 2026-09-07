import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'journey_reminder.dart';
import 'reminder_notifications.dart';
import 'reminder_repository.dart';

class ReminderController extends ChangeNotifier {
  ReminderController(
    this.repository,
    this.notifications, {
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       _owner = repository.userId;
  final ReminderRepository repository;
  final ReminderNotifications notifications;
  final DateTime Function() now;
  List<JourneyReminder> _records = [];
  String? _owner;
  String? error;
  bool busy = false;
  Future<void>? _tail;
  Timer? _expiry;
  List<JourneyReminder> get upcoming =>
      _records
          .where(
            (r) =>
                r.owner == repository.userId &&
                r.journey.departure.isAfter(now()),
          )
          .toList()
        ..sort((a, b) => a.journey.departure.compareTo(b.journey.departure));
  JourneyReminder? matching(ReminderJourney journey) {
    for (final record in upcoming) {
      if (record.journey.key == journey.key) return record;
    }
    return null;
  }

  Future<void> _serial(Future<void> Function() action) {
    final result = (_tail ?? Future<void>.value()).then((_) => action());
    _tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> refresh() {
    final owner = repository.userId;
    final changed = _owner != owner;
    _owner = owner;
    if (changed) {
      _records = [];
      notifyListeners();
    }
    return _serial(() async {
      try {
        if (changed || owner == null) await notifications.cancelAll();
        if (owner == null || owner != repository.userId) return;
        final records = await repository.load();
        if (owner != repository.userId) return;
        _records = records.where((r) => r.owner == owner).toList();
        // Reconcile once on login/resume; no network or notification polling.
        await notifications.cancelAll();
        final permitted = await notifications.permission(request: false);
        if (permitted) {
          for (final record in upcoming) {
            if (owner != repository.userId) break;
            if (record.reminderAt.isAfter(now())) {
              await notifications.schedule(record);
            }
          }
        }
        error = !permitted && upcoming.isNotEmpty
            ? 'Reminders are saved, but Android notification or alarm permission is disabled. Enable it in Settings, then retry.'
            : null;
      } on Object {
        error = 'Unable to restore reminders. Please retry.';
      }
      _notify();
    });
  }

  Future<void> set(ReminderJourney journey, int offset) => _serial(() async {
    final owner = repository.userId;
    if (owner == null) throw const ReminderException('Please sign in again.');
    journey.reminderTime(offset, now());
    if (matching(journey) != null) return;
    busy = true;
    notifyListeners();
    try {
      if (!await notifications.permission(request: true)) {
        throw const ReminderException(
          'Allow notifications and alarms in Android settings to set a departure reminder.',
        );
      }
      if (owner != repository.userId) {
        throw const ReminderException('Account changed. Please try again.');
      }
      journey.reminderTime(offset, now());
      final record = await repository.create(journey, offset, now());
      if (owner != repository.userId || record.owner != owner) return;
      _records.removeWhere((r) => r.id == record.id);
      _records.add(record);
      try {
        if (!record.reminderAt.isAfter(now())) {
          throw const ReminderException(
            'This reminder time has already passed.',
          );
        }
        await notifications.schedule(record);
      } on Object {
        // Cancel first. If persistence fails, retain the record for retry/cancel.
        await notifications.cancel(record.id);
        await repository.delete(record.id);
        _records.removeWhere((r) => r.id == record.id);
        rethrow;
      }
    } finally {
      busy = false;
      _notify();
    }
  });

  Future<void> cancel(JourneyReminder reminder) => _serial(() async {
    if (reminder.owner != repository.userId) {
      throw const ReminderException('Please sign in again.');
    }
    await notifications.cancel(reminder.id);
    await repository.delete(reminder.id);
    _records.removeWhere((r) => r.id == reminder.id);
    _notify();
  });

  void _notify() {
    _expiry?.cancel();
    final next = upcoming;
    if (next.isNotEmpty) {
      _expiry = Timer(next.first.journey.departure.difference(now()), _notify);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }
}

ReminderController? _shared;
StreamSubscription<AuthState>? _authReminders;
ReminderController? get sharedReminderController {
  if (_shared != null) return _shared;
  try {
    final client = Supabase.instance.client;
    final controller = _shared = ReminderController(
      SupabaseReminderRepository(client),
      AndroidReminderNotifications(),
    );
    _authReminders ??= client.auth.onAuthStateChange.listen((_) {
      controller.refresh();
    });
    unawaited(controller.refresh());
    return controller;
  } on Object {
    return null;
  }
}
