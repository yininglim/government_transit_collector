import 'package:supabase_flutter/supabase_flutter.dart';

import 'bus_feedback.dart';

const duplicateFeedbackMessage =
    'You have already submitted a report for this stop and scheduled departure.';

abstract interface class BusFeedbackRepository {
  Future<void> submitFeedback(BusFeedback feedback);

  Future<List<BusFeedback>> getMyFeedback();

  Future<void> updateFeedback(BusFeedback feedback);

  Future<void> deleteFeedback(String feedbackId);
}

class SupabaseBusFeedbackRepository implements BusFeedbackRepository {
  SupabaseBusFeedbackRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<void> submitFeedback(BusFeedback feedback) async {
    try {
      final user = _client.auth.currentUser;

      if (user == null) {
        throw const BusFeedbackException(
          'Please log in before submitting feedback.',
        );
      }

      if (feedback.userId != user.id) {
        throw const BusFeedbackException(
          'Unable to submit feedback for another user.',
        );
      }

      if (feedback.serviceDate == null ||
          feedback.scheduledDepartureSeconds == null ||
          feedback.scheduledDepartureSeconds! < 0) {
        throw const BusFeedbackException(
          'Please select a valid scheduled departure.',
        );
      }
      final existing = await _client
          .from('bus_feedback')
          .select('feedback_id')
          .eq('user_id', user.id)
          .eq('route_id', feedback.routeId)
          .eq('stop_id', feedback.stopId)
          .eq('service_date', feedback.serviceDateKey!)
          .eq(
            'scheduled_departure_seconds',
            feedback.scheduledDepartureSeconds!,
          )
          .limit(1);
      if (existing.isNotEmpty) {
        throw const BusFeedbackException(duplicateFeedbackMessage);
      }
      if (_client.auth.currentUser?.id != user.id) {
        throw const BusFeedbackException(
          'Account changed. Please reopen the report.',
        );
      }

      await _client.from('bus_feedback').insert(feedback.toMap());
    } on BusFeedbackException {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == '23505' &&
          error.message.contains('bus_feedback_user_scheduled_event_key')) {
        throw const BusFeedbackException(duplicateFeedbackMessage);
      }
      throw BusFeedbackException(
        error.message.isEmpty ? 'Unable to submit feedback.' : error.message,
      );
    } on Object {
      throw const BusFeedbackException('Unable to submit feedback.');
    }
  }

  @override
  Future<List<BusFeedback>> getMyFeedback() async {
    try {
      final user = _client.auth.currentUser;

      if (user == null) {
        throw const BusFeedbackException(
          'Please log in to view your feedback.',
        );
      }

      final rows = <Map<String, dynamic>>[];
      for (var offset = 0; ; offset += 500) {
        final page = await _client
            .from('bus_feedback')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .order('feedback_id')
            .range(offset, offset + 499);
        rows.addAll(page.where((row) => row['user_id'] == user.id));
        if (page.length < 500) break;
      }
      final routeLabels = <String, String>{};
      final stopNames = <String, String>{};
      Future<void> names(
        String table,
        String idColumn,
        List<String> ids,
        String columns,
        Map<String, String> target,
        String Function(Map<String, dynamic>) label,
      ) async {
        for (var start = 0; start < ids.length; start += 100) {
          final data = await _client
              .from(table)
              .select(columns)
              .inFilter(
                idColumn,
                ids.sublist(start, (start + 100).clamp(0, ids.length)),
              );
          for (final row in data) {
            target[row[idColumn] as String] = label(row);
          }
        }
      }

      await names(
        'gtfs_routes',
        'route_id',
        rows.map((r) => r['route_id']).whereType<String>().toSet().toList(),
        'route_id, route_short_name, route_long_name',
        routeLabels,
        (r) =>
            (r['route_short_name'] as String?) ??
            (r['route_long_name'] as String?) ??
            r['route_id'] as String,
      );
      await names(
        'gtfs_stops',
        'stop_id',
        rows.map((r) => r['stop_id']).whereType<String>().toSet().toList(),
        'stop_id, stop_name',
        stopNames,
        (r) => r['stop_name'] as String,
      );
      if (_client.auth.currentUser?.id != user.id) {
        throw const BusFeedbackException(
          'Account changed. Please reopen your profile.',
        );
      }
      return rows
          .map(
            (row) => BusFeedback.fromMap({
              ...row,
              'route_label': routeLabels[row['route_id']],
              'stop_name': stopNames[row['stop_id']],
            }),
          )
          .toList(growable: false);
    } on BusFeedbackException {
      rethrow;
    } on PostgrestException catch (error) {
      throw BusFeedbackException(
        error.message.isEmpty ? 'Unable to load feedback.' : error.message,
      );
    } on Object {
      throw const BusFeedbackException('Unable to load feedback.');
    }
  }

  @override
  Future<void> updateFeedback(BusFeedback feedback) async {
    final feedbackId = feedback.feedbackId;

    if (feedbackId == null) {
      throw const BusFeedbackException('Feedback ID is required.');
    }

    try {
      final user = _client.auth.currentUser;

      if (user == null) {
        throw const BusFeedbackException(
          'Please log in before updating feedback.',
        );
      }

      await _client
          .from('bus_feedback')
          .update(feedback.toUpdateMap())
          .eq('feedback_id', feedbackId)
          .eq('user_id', user.id);
    } on BusFeedbackException {
      rethrow;
    } on PostgrestException catch (error) {
      throw BusFeedbackException(
        error.message.isEmpty ? 'Unable to update feedback.' : error.message,
      );
    } on Object {
      throw const BusFeedbackException('Unable to update feedback.');
    }
  }

  @override
  Future<void> deleteFeedback(String feedbackId) async {
    try {
      final user = _client.auth.currentUser;

      if (user == null) {
        throw const BusFeedbackException(
          'Please log in before deleting feedback.',
        );
      }

      await _client
          .from('bus_feedback')
          .delete()
          .eq('feedback_id', feedbackId)
          .eq('user_id', user.id);
    } on BusFeedbackException {
      rethrow;
    } on PostgrestException catch (error) {
      throw BusFeedbackException(
        error.message.isEmpty ? 'Unable to delete feedback.' : error.message,
      );
    } on Object {
      throw const BusFeedbackException('Unable to delete feedback.');
    }
  }
}

class BusFeedbackException implements Exception {
  const BusFeedbackException(this.message);

  final String message;

  @override
  String toString() => message;
}
