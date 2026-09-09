import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/bus_feedback/data/bus_feedback.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/journey_comparison.dart';
import 'departure_recommendation_test.dart' as f;

void main() {
  test('recent issues filter routes and time and decode multiple issues', () {
    final now = DateTime.utc(2026, 9, 10);
    BusFeedback report(String route, int days, String issue) => BusFeedback(
      userId: 'owner',
      routeId: route,
      stopId: 'stop',
      issueType: issue,
      comment: '',
      createdAt: now.subtract(Duration(days: days)),
    );
    final reports = [
      report('J15', 1, '["Bus was late","Bus overcrowded"]'),
      report('J10', 2, 'Bus was late'),
      report('other', 1, 'Unrelated'),
      report('J15', 8, 'Old'),
      report('J15', -1, 'Future'),
    ];
    expect(recentJourneyIssues(reports, f.transferRecommendation, now), {
      'Bus was late': 2,
      'Bus overcrowded': 1,
    });
    expect(recentJourneyIssues(reports, f.directRecommendation, now), {
      'Bus was late': 1,
      'Bus overcrowded': 1,
    });
  });

  testWidgets(
    'comparison preserves best choice and real values through rotation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: JourneyComparison(
                journeys: [
                  f.directRecommendation,
                  f.transferRecommendation,
                  f.directRecommendation,
                  f.directRecommendation,
                  f.directRecommendation,
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Journey Comparison'));
      await tester.pumpAndSettle();
      for (final size in [const Size(320, 640), const Size(844, 390)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(find.text('BEST CHOICE'), findsOneWidget);
        expect(find.text('ALTERNATIVES'), findsOneWidget);
        expect(find.textContaining('Option '), findsNothing);
        expect(find.text('3:55 PM \u2192 4:25 PM'), findsNWidgets(3));
        expect(find.text('30 min'), findsNWidgets(3));
        expect(
          find.text('Transfer at City Square \u00b7 8 min wait'),
          findsOneWidget,
        );
        expect(find.textContaining('Reliability'), findsNothing);
        expect(find.textContaining('%'), findsNothing);
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widgetList<Scrollable>(find.byType(Scrollable))
              .every((s) => s.axisDirection == AxisDirection.down),
          isTrue,
        );
      }
    },
  );
}
