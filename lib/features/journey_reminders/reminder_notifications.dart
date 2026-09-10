import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:government_transit_collector/core/time/transit_service_time.dart';
import 'journey_reminder.dart';

abstract interface class ReminderNotifications {
  Future<bool> permission({required bool request});
  Future<void> schedule(JourneyReminder reminder);
  Future<void> cancel(int id);
  Future<void> cancelAll();
}

class AndroidReminderNotifications implements ReminderNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> _initialize() => _initialization ??= _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_departure_reminder'),
    ),
  );

  @override
  Future<bool> permission({required bool request}) async {
    if (!_supported) return false;
    await _initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;
    final notifications = request
        ? await android.requestNotificationsPermission()
        : await android.areNotificationsEnabled();
    if (notifications != true) return false;
    final channels = await android.getNotificationChannels();
    if (channels?.any(
          (channel) =>
              channel.id == 'journey_departures' &&
              channel.importance == Importance.none,
        ) ==
        true) {
      return false;
    }
    if (await android.canScheduleExactNotifications() == true) return true;
    return request && await android.requestExactAlarmsPermission() == true;
  }

  @override
  Future<void> schedule(JourneyReminder reminder) async {
    await _initialize();
    await _plugin.zonedSchedule(
      id: reminder.id,
      title: 'Bus Departure Reminder',
      body:
          '${reminder.journey.route} from ${reminder.journey.origin} is scheduled to depart at ${reminderDisplayTime(reminder.journey.departure)}.',
      scheduledDate: transitServiceDateTime(reminder.reminderAt),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'journey_departures',
          'Departure reminders',
          channelDescription:
              'Reminders for your selected scheduled bus departures',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
    final pending = await _plugin.pendingNotificationRequests();
    if (reminder.reminderAt.isAfter(DateTime.now()) &&
        !pending.any((request) => request.id == reminder.id)) {
      throw const ReminderException(
        'Android did not retain this reminder. Please try again.',
      );
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_supported) return;
    await _initialize();
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    if (!_supported) return;
    await _initialize();
    await _plugin.cancelAll();
  }
}
