import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/bus_feedback/presentation/passenger_reports_page.dart';
import 'package:government_transit_collector/features/bus_feedback/presentation/bus_feedback_page.dart';
import 'report_form_test.dart' show ReportsFake, ReferenceFake;

void main() {
  testWidgets(
    'Reports opens existing general report form in both orientations',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: PassengerReportsPage(
            userId: 'owner',
            repository: ReportsFake(),
            referenceRepository: ReferenceFake(),
          ),
        ),
      );
      for (final size in [const Size(320, 640), const Size(844, 390)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(find.text('My Reports'), findsOneWidget);
        final button = find.byKey(const Key('general-feedback-button'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<BusFeedbackPage>(find.byType(BusFeedbackPage))
              .hasJourneyContext,
          isFalse,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
