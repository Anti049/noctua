import 'dart:math';

import 'package:dartx/dartx.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctua/src/core/utils/theming.dart';

const kEmptyFaces = [
  '(･o･;)',
  'Σ(ಠ_ಠ)',
  'ಥ_ಥ',
  '(˘･_･˘)',
  '(；￣Д￣)',
  '(･Д･。',
  '(╯︵╰,)',
  '૮(˶ㅠ︿ㅠ)ა',
  '(っ◞‸◟ c)',
  '｡°(°.◜ᯅ◝°)°｡',
  '(≥o≤)',
  '(╥﹏╥)',
  '(´；д；`)',
  '( •ө• )',
  '(·•᷄‎ࡇ•᷅ )',
];

class EmptyPlaceholder extends StatefulWidget {
  const EmptyPlaceholder({super.key, this.message, this.subtitle, this.actions, this.style});

  final String? message;
  final String? subtitle;
  final List<Widget>? actions;
  final TextStyle? style;

  @override
  State<EmptyPlaceholder> createState() => _EmptyPlaceholderState();
}

class _EmptyPlaceholderState extends State<EmptyPlaceholder> {
  int _errorIndex = -1;

  @override
  void initState() {
    super.initState();
    // Randomly select an index for the empty face
    _errorIndex = Random().nextInt(kEmptyFaces.length);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(kEmptyFaces[_errorIndex], style: widget.style ?? context.text.displayMedium?.copyWith(color: context.colors.secondary)),
            if (widget.message.isNotNullOrBlank)
              Baseline(
                baseline: 24.0,
                baselineType: TextBaseline.alphabetic,
                child: Text(
                  widget.message ?? '', // Fallback to empty string if null
                  style: context.text.titleLarge?.copyWith(color: context.colors.secondary),
                  textAlign: TextAlign.center,
                ),
              ),
            if (widget.subtitle.isNotNullOrBlank)
              Baseline(
                baseline: 24.0,
                baselineType: TextBaseline.alphabetic,
                child: Text(
                  widget.subtitle ?? '',
                  style: context.text.titleMedium?.copyWith(color: context.colors.secondary, fontWeight: FontWeight.normal),
                  textAlign: TextAlign.center,
                ),
              ),
            if (widget.actions?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: widget.actions ?? []),
              ),
          ],
        ),
      ),
    );
  }
}
