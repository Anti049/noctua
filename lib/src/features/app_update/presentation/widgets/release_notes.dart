import 'package:flutter/material.dart';
import 'package:noctua/src/core/utils/theming.dart';

/// Renders the small Markdown subset GitHub release notes use: headings,
/// bullets and paragraphs. Links keep their text; "by @user in https://…"
/// credits from generated notes are trimmed so lines stay readable.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes(this.markdown, {super.key, this.maxItems});
  final String markdown;

  /// Show at most this many bullet points (null = all).
  final int? maxItems;

  static String clean(String s) => s
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
      .replaceAll(RegExp(r' by @[\w-]+ in https?://\S+'), '')
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .trim();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final children = <Widget>[];
    var bullets = 0;
    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty || line.startsWith('**Full Changelog**')) continue;
      final heading = RegExp(r'^#{1,6}\s+(.*)').firstMatch(line);
      final bullet = RegExp(r'^\s*[*-]\s+(.*)').firstMatch(line);
      if (heading != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(clean(heading[1]!), style: context.text.titleSmall?.copyWith(color: c.primary)),
          ),
        );
      } else if (bullet != null) {
        if (maxItems != null && bullets >= maxItems!) continue;
        bullets++;
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 10),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                  ),
                ),
                Expanded(child: Text(clean(bullet[1]!), style: context.text.bodyMedium)),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(clean(line), style: context.text.bodyMedium),
          ),
        );
      }
    }
    if (children.isEmpty) {
      children.add(Text('No release notes.', style: context.text.bodyMedium?.copyWith(color: c.onSurfaceVariant)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
