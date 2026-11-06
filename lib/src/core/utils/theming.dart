import 'package:material_ui/material_ui.dart';

extension ThemeDataExtensions on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => theme.colorScheme;
  TextTheme get text => theme.textTheme;
  Brightness get brightness => theme.brightness;
  MediaQueryData get mediaQuery => MediaQuery.of(this);
}

extension BrightnessExtensions on Brightness {
  Brightness get inverted => this == Brightness.light ? Brightness.dark : Brightness.light;
}
