import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback_repository.dart';
import 'feedback_test_support.dart';

BusFeedback report({
  String user = 'owner',
  String route = 'r',
  String stop = 'a',
  int seconds = 48480,
  int day = 7,
  String issue = 'Bus was late',
  String description = 'Late bus',
}) => BusFeedback(
  userId: user,
  routeId: route,
  stopId: stop,
  tripId: 'trip',
  issueType: issue,
  comment: description,
  createdAt: DateTime.utc(2026, 9, 8),
  serviceDate: DateTime(2026, 9, day),
  scheduledDepartureSeconds: seconds,
);

void main() {
  test(
    'first report succeeds; identity excludes problem type and description and permits different events/users',
    () async {
      final rows = <Map<String, dynamic>>[];
      Future<dynamic> create(String owner) async =>
          feedbackClient((request) async {
            if (request.method == 'GET') {
              final query = request.url.queryParameters;
              expect(query['user_id'], 'eq.$owner');
              expect(query.containsKey('issue_type'), isFalse);
              expect(query.containsKey('comment'), isFalse);
              return jsonResponse(
                rows
                    .where(
                      (row) => [
                        'user_id',
                        'route_id',
                        'stop_id',
                        'service_date',
                        'scheduled_departure_seconds',
                      ].every((key) => query[key] == 'eq.${row[key]}'),
                    )
                    .toList(),
              );
            }
            rows.add(jsonDecode(request.body) as Map<String, dynamic>);
            return jsonResponse(null, status: 201);
          }, owner: owner);
      final client = await create('owner');
      addTearDown(client.dispose);
      final repository = SupabaseBusFeedbackRepository(client: client);
      await repository.submitFeedback(report());
      expect(rows, hasLength(1));
      for (final duplicate in [
        report(),
        report(issue: 'Bus overcrowded'),
        report(description: 'Another description'),
      ]) {
        await expectLater(
          repository.submitFeedback(duplicate),
          throwsA(
            isA<BusFeedbackException>().having(
              (e) => e.message,
              'friendly duplicate',
              duplicateFeedbackMessage,
            ),
          ),
        );
      }
      for (final different in [
        report(stop: 'b'),
        report(seconds: 48540),
        report(day: 8),
        report(route: 'other'),
      ]) {
        await repository.submitFeedback(different);
      }
      final other = await create('other');
      addTearDown(other.dispose);
      await SupabaseBusFeedbackRepository(
        client: other,
      ).submitFeedback(report(user: 'other'));
      expect(rows, hasLength(6));
      expect(rows.first['service_date'], '2026-09-07');
      expect(rows.first['created_at'], '2026-09-08T00:00:00.000Z');
    },
  );

  test('database race unique violation becomes friendly duplicate', () async {
    final client = await feedbackClient(
      (request) async => request.method == 'GET'
          ? jsonResponse([])
          : jsonResponse({
              'code': '23505',
              'message':
                  'duplicate key violates unique constraint "bus_feedback_user_scheduled_event_key"',
            }, status: 409),
    );
    addTearDown(client.dispose);
    await expectLater(
      SupabaseBusFeedbackRepository(client: client).submitFeedback(report()),
      throwsA(
        isA<BusFeedbackException>().having(
          (e) => e.message,
          'message',
          duplicateFeedbackMessage,
        ),
      ),
    );
  });

  test('query failures are surfaced and do not insert', () async {
    var inserts = 0;
    final client = await feedbackClient((request) async {
      if (request.method == 'POST') inserts++;
      return jsonResponse({
        'code': '08000',
        'message': 'Connection failed',
      }, status: 503);
    });
    addTearDown(client.dispose);
    await expectLater(
      SupabaseBusFeedbackRepository(client: client).submitFeedback(report()),
      throwsA(isA<BusFeedbackException>()),
    );
    expect(inserts, 0);
  });

  test('unauthenticated and mismatched ownership cannot submit', () async {
    var reads = 0;
    final client = await feedbackClient((request) async {
      reads++;
      return jsonResponse([]);
    });
    addTearDown(client.dispose);
    await expectLater(
      SupabaseBusFeedbackRepository(
        client: client,
      ).submitFeedback(report(user: 'other')),
      throwsA(isA<BusFeedbackException>()),
    );
    final signedOut = await feedbackClient((request) async {
      reads++;
      return jsonResponse([]);
    }, signIn: false);
    addTearDown(signedOut.dispose);
    await expectLater(
      SupabaseBusFeedbackRepository(client: signedOut).submitFeedback(report()),
      throwsA(isA<BusFeedbackException>()),
    );
    expect(reads, 0);
  });

  test(
    'My Reports is owner-filtered and resolves names; historical schedule stays absent',
    () async {
      final client = await feedbackClient((request) async {
        if (request.url.path.endsWith('bus_feedback')) {
          expect(request.url.queryParameters['user_id'], 'eq.owner');
          return jsonResponse([
            {...report().toMap(), 'feedback_id': 'new'},
            {...report(user: 'other').toMap(), 'feedback_id': 'private'},
            {
              ...report().toMap(),
              'feedback_id': 'old',
              'route_id': null,
              'stop_id': null,
              'trip_id': null,
              'service_date': null,
              'scheduled_departure_seconds': null,
            },
          ]);
        }
        if (request.url.path.endsWith('gtfs_routes')) {
          return jsonResponse([
            {
              'route_id': 'r',
              'route_short_name': 'J30',
              'route_long_name': 'Route',
            },
          ]);
        }
        return jsonResponse([
          {'stop_id': 'a', 'stop_name': 'Taman Universiti'},
        ]);
      });
      addTearDown(client.dispose);
      final reports = await SupabaseBusFeedbackRepository(
        client: client,
      ).getMyFeedback();
      expect(reports, hasLength(2));
      expect(reports.every((r) => r.userId == 'owner'), isTrue);
      expect(reports.first.routeLabel, 'J30');
      expect(reports.first.stopName, 'Taman Universiti');
      expect(reports.last.serviceDate, isNull);
      expect(reports.last.scheduledDepartureSeconds, isNull);
      expect(reports.last.description, 'Late bus');
      expect(reports.last.routeLabel, 'Not recorded');
      expect(reports.last.stopName, 'Not recorded');
    },
  );

  test(
    'migration uniquely identifies user event, preserves history and validates real schedule',
    () {
      final sql = File(
        'supabase/migrations/20260907000000_bus_feedback_scheduled_event.sql',
      ).readAsStringSync();
      expect(
        sql,
        contains(
          '(user_id, route_id, stop_id, service_date, scheduled_departure_seconds)',
        ),
      );
      expect(
        sql,
        contains(
          'where service_date is not null and scheduled_departure_seconds is not null',
        ),
      );
      expect(sql, contains('before insert or update on public.bus_feedback'));
      expect(sql, contains('c.source_import_id = t.source_import_id'));
      expect(sql, contains('st.source_import_id = t.source_import_id'));
      expect(sql, contains('and route_id is not null and stop_id is not null'));
      expect(sql, contains('new.user_id is distinct from auth.uid()'));
      expect(sql, isNot(contains('public.gtfs_calendar_dates')));
      expect(
        sql,
        contains('st.departure_seconds = new.scheduled_departure_seconds'),
      );
      expect(sql, isNot(contains('create table')));
    },
  );
}
