import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/core/theme/app_theme.dart';
import 'package:government_transit_collector/core/widgets/readable_app_bar.dart';

void main() {
  for (final title in [
    'Bus Frequency Recommendations',
    'Route & Bus Stop Recommendations',
    'Cost Estimation Report',
    'Recommendation Management',
    'Saved Operational Reports',
    'Peak Operation Analysis',
    'Departure Recommendation',
    'Select destination stop',
    'My Travel Profile',
    'Change Email Password',
    'Verify Your Email',
    'Email Not Verified',
  ]) {
    testWidgets('$title stays visible through rotation and keeps Back', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var actionCalls = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                appBar: readableAppBar(
                  context,
                  title: Text(title),
                  actions: [IconButton(
                    tooltip: 'Existing action',
                    onPressed: () => actionCalls++,
                    icon: const Icon(Icons.refresh),
                  )],
                ),
                body: const SingleChildScrollView(child: Text('Existing page content')),
              ),
            )),
            child: const Text('Open detail'),
          ),
        )),
      ));
      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();
      for (final size in [const Size(320, 640), const Size(390, 844), const Size(844, 390)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final text = find.text(title);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.widget<Text>(text).overflow, isNot(TextOverflow.ellipsis));
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.backgroundColor, AppTheme.shellColorScheme.primary);
        expect(appBar.foregroundColor, Colors.white);
        expect(appBar.surfaceTintColor, Colors.transparent);
        expect(tester.widget<Text>(text).style!.color, Colors.white);
        expect(Theme.of(tester.element(text)).colorScheme.primary, AppTheme.contentBlue);
        final bar = tester.getRect(find.byType(AppBar));
        expect(bar.contains(tester.getTopLeft(text)), isTrue);
        expect(bar.contains(tester.getBottomRight(text) - const Offset(1, 1)), isTrue);
        expect(find.byType(BackButton).hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Existing action'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(actionCalls, 3);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Open detail'), findsOneWidget);
    });
  }

  for (final allowBack in [false, true]) {
    testWidgets('header without Back keeps its styling when allowBack=$allowBack', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(builder: (context) => Scaffold(
          appBar: readableAppBar(
            context,
            title: const Text('Existing page'),
            automaticallyImplyLeading: allowBack,
          ),
        )),
      ));
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, isNull);
      expect(appBar.foregroundColor, isNull);
      expect(find.byType(BackButton), findsNothing);
    });
  }

  testWidgets('long validation messages wrap in the existing form style', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    const message = 'Please check your email address and enter a valid address before continuing.';
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: Padding(
        padding: EdgeInsets.all(24),
        child: TextField(decoration: InputDecoration(errorText: message)),
      )),
    ));
    await tester.pumpAndSettle();
    expect(tester.renderObject<RenderParagraph>(find.text(message)).didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });
}
