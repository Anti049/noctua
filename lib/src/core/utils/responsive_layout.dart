import 'package:material_ui/material_ui.dart' show BuildContext;
import 'package:noctua/src/core/constants/responsive_layout.dart';
import 'package:responsive_framework/responsive_framework.dart';

abstract final class WindowSize {
  static const breakpoints = [
    Breakpoint(start: kCompactStart, end: kCompactEnd, name: kCompact),
    Breakpoint(start: kMediumStart, end: kMediumEnd, name: kMedium),
    Breakpoint(start: kExpandedStart, end: kExpandedEnd, name: kExpanded),
    Breakpoint(start: kLargeStart, end: kLargeEnd, name: kLarge),
    Breakpoint(start: kExtraLargeStart, end: kExtraLargeEnd, name: kExtraLarge),
  ];
}

extension WindowSizeX on BuildContext {
  ResponsiveBreakpointsData get _bp => ResponsiveBreakpoints.of(this);

  // Matching breakpoint checks
  bool get isCompact => _bp.breakpoint.name == kCompact;
  bool get isMedium => _bp.breakpoint.name == kMedium;
  bool get isExpanded => _bp.breakpoint.name == kExpanded;
  bool get isLarge => _bp.breakpoint.name == kLarge;
  bool get isExtraLarge => _bp.breakpoint.name == kExtraLarge;

  // Minimum breakpoint checks
  bool get atLeastCompact => _bp.largerOrEqualTo(kCompact);
  bool get atLeastMedium => _bp.largerOrEqualTo(kMedium);
  bool get atLeastExpanded => _bp.largerOrEqualTo(kExpanded);
  bool get atLeastLarge => _bp.largerOrEqualTo(kLarge);
  bool get atLeastExtraLarge => _bp.largerOrEqualTo(kExtraLarge);
}
