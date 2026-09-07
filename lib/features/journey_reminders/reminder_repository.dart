import 'package:supabase_flutter/supabase_flutter.dart';
import 'journey_reminder.dart';

abstract interface class ReminderRepository {
  String? get userId;
  Future<List<JourneyReminder>> load();
  Future<JourneyReminder> create(
    ReminderJourney journey,
    int offset,
    DateTime now,
  );
  Future<void> delete(int id);
}

class SupabaseReminderRepository implements ReminderRepository {
  SupabaseReminderRepository(this.client);
  final SupabaseClient client;
  @override
  String? get userId => client.auth.currentUser?.id;
  String get _owner =>
      userId ?? (throw const ReminderException('Please sign in again.'));

  @override
  Future<List<JourneyReminder>> load() async {
    final owner = _owner;
    final result = <JourneyReminder>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client
          .from('journey_reminders')
          .select()
          .eq('user_id', owner)
          .gt(
            'scheduled_departure_at',
            DateTime.now().toUtc().toIso8601String(),
          )
          .order('scheduled_departure_at')
          .order('reminder_id')
          .range(offset, offset + 499);
      if (userId != owner) return [];
      result.addAll(rows.map(JourneyReminder.new));
      if (rows.length < 500) return result;
    }
  }

  @override
  Future<JourneyReminder> create(
    ReminderJourney journey,
    int offset,
    DateTime now,
  ) async {
    final owner = _owner;
    final time = journey.reminderTime(offset, now);
    try {
      final row = await client
          .from('journey_reminders')
          .insert({
            ...journey.data,
            'user_id': owner,
            'reminder_offset_minutes': offset,
            'reminder_at': time.toUtc().toIso8601String(),
          })
          .select()
          .single();
      return JourneyReminder(row);
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
      return JourneyReminder(
        await client
            .from('journey_reminders')
            .select()
            .eq('user_id', owner)
            .eq('journey_key', journey.key)
            .single(),
      );
    }
  }

  @override
  Future<void> delete(int id) async {
    await client
        .from('journey_reminders')
        .delete()
        .eq('user_id', _owner)
        .eq('reminder_id', id);
  }
}
