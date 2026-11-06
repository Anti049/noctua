import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctua/src/core/utils/theming.dart';

class ThemedLogo extends StatelessWidget {
  const ThemedLogo({super.key, this.size = 128.0, this.color, this.padding});

  final double size;
  final Color? color;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final logoColor = color ?? context.colors.primary;

    return Container(
      padding: padding,
      alignment: Alignment.center,
      child: SvgPicture.asset(
        'assets/images/logo.svg',
        colorFilter: ColorFilter.mode(logoColor, BlendMode.srcIn),
        width: size,
        height: size,
      ),
    );
  }
}
