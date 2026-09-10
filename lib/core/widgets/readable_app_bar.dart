import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:government_transit_collector/core/theme/app_theme.dart';

AppBar readableAppBar(
  BuildContext context, {
  required Text title,
  List<Widget>? actions,
  bool automaticallyImplyLeading = true,
}) {
  final theme = Theme.of(context);
  final media = MediaQuery.of(context);
  final hasBackNavigation = automaticallyImplyLeading &&
      (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);
  final baseStyle = theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge!;
  final style = hasBackNavigation
      ? baseStyle.copyWith(color: AppTheme.shellColorScheme.onPrimary)
      : baseStyle;
  final width = math.max(
    1.0,
    media.size.width - media.padding.horizontal - 32 -
        (automaticallyImplyLeading ? kToolbarHeight : 0) -
        (actions?.length ?? 0) * kMinInteractiveDimension,
  );
  final painter = TextPainter(
    text: TextSpan(text: title.data, style: style),
    textDirection: Directionality.of(context),
    textScaler: media.textScaler,
  )..layout(maxWidth: width);
  final height = math.max(kToolbarHeight, painter.height + 16);
  final lines = math.max(1, painter.computeLineMetrics().length);
  painter.dispose();
  return AppBar(
    backgroundColor: hasBackNavigation ? AppTheme.shellColorScheme.primary : null,
    foregroundColor: hasBackNavigation ? AppTheme.shellColorScheme.onPrimary : null,
    surfaceTintColor: hasBackNavigation ? Colors.transparent : null,
    automaticallyImplyLeading: automaticallyImplyLeading,
    actions: actions,
    toolbarHeight: height,
    title: Text(
      title.data!,
      style: style,
      softWrap: true,
      maxLines: lines,
      overflow: TextOverflow.visible,
    ),
  );
}
