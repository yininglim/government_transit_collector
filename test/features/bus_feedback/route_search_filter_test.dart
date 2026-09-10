import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/bus_feedback/data/feedback_reference_repository.dart';
import 'feedback_test_support.dart';

void main() {
  test(
    'route search keeps special input in values and preserves the union and order',
    () async {
      const cases = <String, String>{
        ' J50 ': 'J50',
        '': '',
        'x,"route_id".neq.x': r'x,"route\_id".neq.x',
        'x),or(route_id.neq.x': r'x),or(route\_id.neq.x',
        'a,b': 'a,b',
        '"quoted"': '"quoted"',
        '(station)': '(station)',
        'eq.neq.or.and': 'eq.neq.or.and',
        r'50%_\': r'50\%\_\\',
        "'); DROP TABLE profiles; --": "'); DROP TABLE profiles; --",
        'no matches': 'no matches',
      };
      for (final entry in cases.entries) {
        final searchedColumns = <String>[];
        var resultRequests = 0;
        Object? requestError;
        StackTrace? requestStack;
        final client = await feedbackClient((request) async {
          try {
            final params = request.url.queryParameters;
            expect(request.method, 'GET');
            expect(request.url.path, '/rest/v1/gtfs_routes');
            expect(params.keys, isNot(contains('or')));
            expect(params.keys, isNot(contains('and')));
            if (params['select'] == 'route_id') {
              final column = [
                'route_short_name',
                'route_long_name',
                'route_id',
              ].singleWhere(params.containsKey);
              searchedColumns.add(column);
              expect(params[column], 'ilike.%${entry.value}%');
              expect(params.keys.toSet(), {
                'select',
                column,
                'order',
                'offset',
                'limit',
              });
              expect(params['order'], 'route_id.desc.nullslast');
              if (entry.key == 'no matches') {
                return jsonResponse([]);
              }
              return jsonResponse([
                {'route_id': 'r1'},
                if (column == 'route_long_name') {'route_id': 'r2'},
                if (column == 'route_id') {'route_id': 'r3'},
              ]);
            }
            resultRequests++;
            expect(
              params['select'],
              'route_id,route_short_name,route_long_name',
            );
            expect(
              params['order'],
              'route_short_name.desc.nullslast,route_id.desc.nullslast',
            );
            expect(params['limit'], '100');
            if (entry.value.isEmpty) {
              expect(params.containsKey('route_id'), isFalse);
            } else {
              expect(params['route_id'], 'in.("r1","r2","r3")');
            }
            return jsonResponse([
              {
                'route_id': 'r1',
                'route_short_name': 'J50',
                'route_long_name': 'Station',
              },
              {
                'route_id': 'r2',
                'route_short_name': 'J10',
                'route_long_name': 'Station',
              },
              {
                'route_id': 'r3',
                'route_short_name': null,
                'route_long_name': 'Station',
              },
            ]);
          } catch (error, stack) {
            requestError = error;
            requestStack = stack;
            rethrow;
          }
        }, signIn: false);
        try {
          final result = await SupabaseFeedbackReferenceRepository(
            client: client,
          ).searchRoutes(entry.key);
          expect(
            searchedColumns,
            entry.value.isEmpty
                ? isEmpty
                : ['route_short_name', 'route_long_name', 'route_id'],
          );
          expect(
            result.map((r) => r.id),
            entry.key == 'no matches' ? isEmpty : ['r1', 'r2', 'r3'],
          );
          expect(resultRequests, entry.key == 'no matches' ? 0 : 1);
        } catch (_) {
          if (requestError != null) {
            Error.throwWithStackTrace(requestError!, requestStack!);
          }
          rethrow;
        } finally {
          await client.dispose();
        }
      }
    },
  );
}
