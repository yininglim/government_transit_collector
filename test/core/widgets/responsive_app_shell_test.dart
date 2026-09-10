import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/core/theme/app_theme.dart';
import 'package:government_transit_collector/core/widgets/responsive_app_shell.dart';

void main() {
  for (final labels in [
    ['Home', 'Plan', 'Live', 'Reports', 'My Trips'],
    ['Home', 'AI', 'Performance', 'Peak', 'Reports'],
  ]) {
    testWidgets('${labels[1]} role keeps selection, content and actions through rotation', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      var profileCalls = 0;
      var logoutCalls = 0;
      var selected = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: StatefulBuilder(builder: (context, setState) => ResponsiveAppShell(
          items: [for (final label in labels) AppNavigationItem(label: label, icon: Icons.route)],
          selectedIndex: selected,
          onSelected: (value) => setState(() => selected = value),
          navigationKeyPrefix: 'test-nav',
          actions: [
            IconButton(tooltip: 'Profile', onPressed: () => profileCalls++, icon: const Icon(Icons.person_outline)),
            IconButton(tooltip: 'Sign out', onPressed: () => logoutCalls++, icon: const Icon(Icons.logout)),
          ],
          child: IndexedStack(index: selected, children: [
            for (var i = 0; i < labels.length; i++) _StatefulPage(key: ValueKey(i)),
          ]),
        )),
      ));
      await tester.tap(find.byKey(Key('test-nav-${labels[1]}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Retained input');
      final state = tester.state(find.byType(_StatefulPage));
      for (final size in [const Size(320, 640), const Size(844, 390), const Size(568, 240), const Size(768, 1024)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final landscape = size.width > size.height;
        final bottom = find.byKey(const Key('app-bottom-navigation'));
        final side = find.byKey(const Key('app-side-navigation'));
        expect(bottom, landscape ? findsNothing : findsOneWidget);
        expect(side, landscape ? findsOneWidget : findsNothing);
        expect(selected, 1);
        expect(tester.state(find.byType(_StatefulPage)), same(state));
        expect(find.text('Retained input'), findsOneWidget);
        final title = find.text('Government Transit Collector');
        expect(title, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(title);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.widget<Text>(title).overflow, isNot(TextOverflow.ellipsis));
        final header = find.byKey(const Key('app-header'));
        final colors = Theme.of(tester.element(header)).colorScheme;
        expect(tester.widget<Material>(header).color, AppTheme.shellColorScheme.primary);
        final selectedButton = tester.widget<TextButton>(
          find.byKey(Key('test-nav-${labels[1]}')),
        );
        expect(selectedButton.style!.backgroundColor!.resolve({}), AppTheme.shellColorScheme.primary);
        expect(selectedButton.style!.foregroundColor!.resolve({}), AppTheme.shellColorScheme.onPrimary);
        final inactiveButton = tester.widget<TextButton>(
          find.byKey(Key('test-nav-${labels[0]}')),
        );
        expect(inactiveButton.style!.foregroundColor!.resolve({}), colors.onSurfaceVariant);
        final contentAction = find.widgetWithText(FilledButton, 'Content action');
        final button = tester.widget<FilledButton>(contentAction);
        final contentFill = button.defaultStyleOf(tester.element(contentAction))
            .backgroundColor!.resolve({});
        expect(contentFill, AppTheme.shellColorScheme.secondary);
        expect(contentFill, isNot(AppTheme.shellColorScheme.primary));
        expect(colors.surface, AppTheme.shellColorScheme.surface);
        final headerRect = tester.getRect(header);
        expect(headerRect.contains(tester.getTopLeft(title)), isTrue);
        expect(headerRect.contains(tester.getBottomRight(title) - const Offset(1, 1)), isTrue);
        if (landscape) {
          expect(headerRect.left, greaterThanOrEqualTo(tester.getRect(side).right));
        } else {
          expect(tester.getRect(bottom).top, greaterThan(headerRect.bottom));
        }
        for (final label in labels) {
          final item = find.byKey(Key('test-nav-$label'));
          expect(item, findsOneWidget);
          await tester.ensureVisible(item);
          expect(item.hitTestable(), findsOneWidget);
        }
        await tester.tap(find.byTooltip('Profile'));
        await tester.tap(find.byTooltip('Sign out'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(profileCalls, 4);
      expect(logoutCalls, 4);
    });
  }
}

class _StatefulPage extends StatefulWidget {
  const _StatefulPage({super.key});

  @override
  State<_StatefulPage> createState() => _StatefulPageState();
}

class _StatefulPageState extends State<_StatefulPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(children: [
    TextField(controller: _controller),
    FilledButton(onPressed: () {}, child: const Text('Content action')),
  ]);
}
