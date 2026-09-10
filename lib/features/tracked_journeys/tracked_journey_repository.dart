import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tracked_journey.dart';

abstract class TrackedJourneyRepository extends ChangeNotifier {
  String get userId;
  Future<TrackedJourney?> active();
  Future<List<TrackedJourney>> completed();
  Future<void> start(TrackedJourneySnapshot journey, {String? replaceId});
  Future<void> finish(String id, {required bool completed});
}

class SupabaseTrackedJourneyRepository extends TrackedJourneyRepository {
  SupabaseTrackedJourneyRepository({required this.userId, this.supabaseClient});
  @override
  final String userId;
  final SupabaseClient? supabaseClient;
  SupabaseClient get client {
    final value = supabaseClient ?? Supabase.instance.client;
    if (value.auth.currentUser?.id != userId) {
      throw StateError('Please sign in again.');
    }
    return value;
  }

  @override
  Future<TrackedJourney?> active() async {
    final rows = await client
        .from('tracking_sessions')
        .select()
        .eq('user_id', userId)
        .eq('status', 'active')
        .not('journey_snapshot', 'is', null)
        .order('started_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : TrackedJourney.fromJson(rows.single);
  }

  @override
  Future<List<TrackedJourney>> completed() async {
    final results = <TrackedJourney>[];
    for (var offset = 0; ; offset += 100) {
      final rows = await client
          .from('tracking_sessions')
          .select()
          .eq('user_id', userId)
          .eq('status', 'completed')
          .not('journey_snapshot', 'is', null)
          .order('completed_at', ascending: false)
          .order('tracking_session_id')
          .range(offset, offset + 99);
      results.addAll(rows.map(TrackedJourney.fromJson));
      if (rows.length < 100) return results;
    }
  }

  @override
  Future<void> start(
    TrackedJourneySnapshot journey, {
    String? replaceId,
  }) async {
    await client.rpc(
      'start_passenger_journey',
      params: {'p_snapshot': journey.toJson(), 'p_replace_id': replaceId},
    );
    notifyListeners();
  }

  @override
  Future<void> finish(String id, {required bool completed}) async {
    await client.rpc(
      'finish_passenger_journey',
      params: {'p_id': id, 'p_completed': completed},
    );
    notifyListeners();
  }
}
