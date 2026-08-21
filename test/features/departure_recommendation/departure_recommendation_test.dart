import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_recommendation_page.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/departure_validation.dart';

const larkin = DepartureStop(id: 'larkin', name: 'Larkin Sentral');
const jbSentral = DepartureStop(id: 'jb', name: 'JB Sentral');

class FakeDepartureStopRepository implements DepartureStopRepository {
  @override
  Future<List<DepartureStop>> searchStops(String query) async {
    final normalized = query.toLowerCase();
    return [
      larkin,
      jbSentral,
    ].where((stop) => stop.name.toLowerCase().contains(normalized)).toList();
  }
}

void main() {
  group('departure stop validation', () {
    test('rejects missing origin', () {
      expect(
        validateDepartureStops(origin: null, destination: jbSentral),
        'Please select an origin stop.',
      );
    });

    test('rejects missing destination', () {
      expect(
        validateDepartureStops(origin: larkin, destination: null),
        'Please select a destination stop.',
      );
    });

    test('rejects the same origin and destination', () {
      expect(
        validateDepartureStops(origin: larkin, destination: larkin),
        'Origin and destination must be different stops.',
      );
    });

    test('accepts a valid origin and destination', () {
      expect(
        validateDepartureStops(origin: larkin, destination: jbSentral),
        isNull,
      );
    });
  });

  group('departure recommendation page', () {
    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DepartureRecommendationPage(
            repository: FakeDepartureStopRepository(),
          ),
        ),
      );
    }

    Future<void> selectStop(
      WidgetTester tester, {
      required Key fieldKey,
      required DepartureStop stop,
    }) async {
      await tester.tap(find.byKey(fieldKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('stop-${stop.id}')));
      await tester.pumpAndSettle();
    }

    testWidgets('selects an origin stop', (tester) async {
      await pumpPage(tester);

      await selectStop(
        tester,
        fieldKey: const Key('origin-field'),
        stop: larkin,
      );

      expect(find.text('Larkin Sentral'), findsOneWidget);
    });

    testWidgets('selects a destination stop', (tester) async {
      await pumpPage(tester);

      await selectStop(
        tester,
        fieldKey: const Key('destination-field'),
        stop: jbSentral,
      );

      expect(find.text('JB Sentral'), findsOneWidget);
    });

    testWidgets('shows validation when origin is missing', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const Key('journey-search-button')));
      await tester.pump();

      expect(find.text('Please select an origin stop.'), findsOneWidget);
    });

    testWidgets('shows validation when destination is missing', (tester) async {
      await pumpPage(tester);
      await selectStop(
        tester,
        fieldKey: const Key('origin-field'),
        stop: larkin,
      );

      await tester.tap(find.byKey(const Key('journey-search-button')));
      await tester.pump();

      expect(find.text('Please select a destination stop.'), findsOneWidget);
    });

    testWidgets('confirms a valid origin and destination', (tester) async {
      await pumpPage(tester);
      await selectStop(
        tester,
        fieldKey: const Key('origin-field'),
        stop: larkin,
      );
      await selectStop(
        tester,
        fieldKey: const Key('destination-field'),
        stop: jbSentral,
      );

      await tester.tap(find.byKey(const Key('journey-search-button')));
      await tester.pump();

      expect(
        find.text('Selected journey: Larkin Sentral → JB Sentral'),
        findsOneWidget,
      );
    });
  });
}
