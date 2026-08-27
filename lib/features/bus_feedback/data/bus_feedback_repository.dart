import 'package:supabase_flutter/supabase_flutter.dart';

import 'bus_feedback.dart';

abstract interface class BusFeedbackRepository {
  Future<void> submitFeedback(
      BusFeedback feedback,
      );

  Future<List<BusFeedback>>
  getMyFeedback();

  Future<void> updateFeedback(
      BusFeedback feedback,
      );

  Future<void> deleteFeedback(
      String feedbackId,
      );
}

class SupabaseBusFeedbackRepository
    implements BusFeedbackRepository {
  SupabaseBusFeedbackRepository({
    SupabaseClient? client,
  }) : _client =
      client ??
          Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<void> submitFeedback(
      BusFeedback feedback,
      ) async {
    try {
      final user =
          _client.auth.currentUser;

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

      await _client
          .from('bus_feedback')
          .insert(
        feedback.toMap(),
      );
    } on BusFeedbackException {
      rethrow;
    } on PostgrestException catch (error) {
      throw BusFeedbackException(
        error.message.isEmpty
            ? 'Unable to submit feedback.'
            : error.message,
      );
    } on Object {
      throw const BusFeedbackException(
        'Unable to submit feedback.',
      );
    }
  }

  @override
  Future<List<BusFeedback>>
  getMyFeedback() async {
    try {
      final user =
          _client.auth.currentUser;

      if (user == null) {
        throw const BusFeedbackException(
          'Please log in to view your feedback.',
        );
      }

      final data = await _client
          .from('bus_feedback')
          .select()
          .eq(
        'user_id',
        user.id,
      )
          .order(
        'created_at',
        ascending: false,
      );

      return data
          .map(
            (row) =>
            BusFeedback.fromMap(
              row,
            ),
      )
          .toList(
        growable: false,
      );
    } on BusFeedbackException {
      rethrow;
    } on PostgrestException catch (error) {
      throw BusFeedbackException(
        error.message.isEmpty
            ? 'Unable to load feedback.'
            : error.message,
      );
    } on Object {
      throw const BusFeedbackException(
        'Unable to load feedback.',
      );
    }
  }

  @override
  Future<void> updateFeedback(
      BusFeedback feedback,
      ) async {
    final feedbackId =
        feedback.feedbackId;

    if (feedbackId == null) {
      throw const BusFeedbackException(
        'Feedback ID is required.',
      );
    }

    try {
      final user =
          _client.auth.currentUser;

      if (user == null) {
        throw const BusFeedbackException(
          'Please log in before updating feedback.',
        );
      }

      await _client
          .from('bus_feedback')
          .update(
        feedback.toUpdateMap(),
      )
          .eq(
        'feedback_id',
        feedbackId,
      )
          .eq(
        'user_id',
        user.id,
      );
    } on BusFeedbackException {
      rethrow;
    } on PostgrestException catch (error) {
      throw BusFeedbackException(
        error.message.isEmpty
            ? 'Unable to update feedback.'
            : error.message,
      );
    } on Object {
      throw const BusFeedbackException(
        'Unable to update feedback.',
      );
    }
  }

  @override
  Future<void> deleteFeedback(
      String feedbackId,
      ) async {
    try {
      final user =
          _client.auth.currentUser;

      if (user == null) {
        throw const BusFeedbackException(
          'Please log in before deleting feedback.',
        );
      }

      await _client
          .from('bus_feedback')
          .delete()
          .eq(
        'feedback_id',
        feedbackId,
      )
          .eq(
        'user_id',
        user.id,
      );
    } on BusFeedbackException {
      rethrow;
    } on PostgrestException catch (error) {
      throw BusFeedbackException(
        error.message.isEmpty
            ? 'Unable to delete feedback.'
            : error.message,
      );
    } on Object {
      throw const BusFeedbackException(
        'Unable to delete feedback.',
      );
    }
  }
}

class BusFeedbackException
    implements Exception {
  const BusFeedbackException(
      this.message,
      );

  final String message;

  @override
  String toString() => message;
}