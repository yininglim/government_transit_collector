import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/theme/app_theme.dart';

class AppNavigationItem {
  const AppNavigationItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData? selectedIcon;
}

class ResponsiveAppShell extends StatelessWidget {
  const ResponsiveAppShell({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.navigationKeyPrefix,
    required this.actions,
    required this.child,
    this.showHeader = true,
    super.key,
  });

  final List<AppNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String navigationKeyPrefix;
  final List<Widget> actions;
  final Widget child;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (landscape)
              SizedBox(
                key: const Key('app-side-navigation'),
                width: 112,
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Column(children: _buttons(context)),
                  ),
                ),
              ),
            Expanded(
              key: const ValueKey('app-content'),
              child: Column(
                children: [
                  if (showHeader) _AppHeader(actions: actions),
                  Expanded(key: const ValueKey('app-pages'), child: child),
                  if (!landscape)
                    Material(
                      key: const Key('app-bottom-navigation'),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final button in _buttons(context))
                              Expanded(child: button),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buttons(BuildContext context) {
    final theme = Theme.of(context);
    return [
      for (var index = 0; index < items.length; index++)
        Semantics(
          selected: selectedIndex == index,
          child: TextButton(
            key: Key('$navigationKeyPrefix-${items[index].label}'),
            onPressed: () => onSelected(index),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 64),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
              backgroundColor: selectedIndex == index
                  ? AppTheme.shellColorScheme.primary
                  : null,
              foregroundColor: selectedIndex == index
                  ? AppTheme.shellColorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selectedIndex == index
                        ? items[index].selectedIcon ?? items[index].icon
                        : items[index].icon,
                    size: 22,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[index].label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selectedIndex == index
                          ? AppTheme.shellColorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({required this.actions});
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('app-header'),
      color: AppTheme.shellColorScheme.primary,
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: AppTheme.shellColorScheme.onPrimary,
            disabledForegroundColor:
                AppTheme.shellColorScheme.onPrimary.withValues(alpha: 0.6),
          ),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Government Transit Collector',
                      softWrap: true,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppTheme.shellColorScheme.onPrimary,
                        fontSize: constraints.maxWidth < 400 ? 18 : 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ...actions,
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
