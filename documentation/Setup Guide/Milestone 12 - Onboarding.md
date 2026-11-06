---
title: "Milestone 12: Onboarding"
tags:
  - noctua
  - noctua/guide
  - noctua/milestone
milestone: 12
aliases:
  - Milestone 12
updated: 2026-11-06
---
# Milestone 12: Onboarding

New accounts and guests go through a five-step setup, a six-page tour, and coach marks on the library. Everything can be skipped, and the tour can be replayed. Onboarding is presentation only: each step reads and writes preferences (`setupDone`, `tourDone`, `coachPending`) and calls existing controllers.

1. **`onboarding/presentation/setup_page.dart`:** five steps with a progress bar: pick a look, download location, sources (sign in or install), notifications, and import. Finishing sets `setupDone` and replaces the stack with the tour.
2. **`onboarding/presentation/tour_page.dart`:** a `PageView` of six pages: library, open works, the reader, updates, offline and sync, and “Written by people”. The last page embeds `AiChoices` from the `ai` feature: hide AI-generated works, warn about likely AI works, and AI features (off unless turned on). The same widget appears in Settings › AI and content.
3. **`onboarding/presentation/widgets/coach_marks.dart`:** an overlay that dims everything except one control, found through a `GlobalKey`, with a card explaining it. The library adds keys to the category tabs, filter button, tab counter and search, and shows `CoachMarks` while `coachPending` is set.

   ```dart
   if (ref.pref(Prefs.coachPending))
     Positioned.fill(
       child: CoachMarks(
         onDone: () => ref.setPref(Prefs.coachPending, false),
         steps: [
           CoachStep(_tabsKey, 'Categories', 'Swipe between your categories…'),
           CoachStep(_filterKey, 'Filter and display', 'Filter by tags, fandoms and status…'),
         ],
       ),
     ),
   ```
4. **`onboarding/presentation/replay_tour.dart`:** resets `tourDone` and pushes the tour; More › Help and feature tour and About call it.

## Code walkthrough: milestone 12

Onboarding is three pieces chained by preferences: setup sets `setupDone`, the tour sets `tourDone` and `coachPending`, and the library shows coach marks while `coachPending` is true. `NoctuaApp`'s start route ([[Milestone 05 - Theming and the app shell|milestone 5]], step 10) reads the first two, so killing the app mid-onboarding resumes at the right screen.

**Step 1: setup.** Five steps in one page, with a segmented progress bar. The step titles are a list of records, and the body is a `switch` on the step index:

```dart
class _SetupPageState extends ConsumerState<SetupPage> {
  int _step = 0;
  String _storage = 'internal';
  final _signedIn = <String>{};
  bool _ffn = false;

  static const _steps = [
    ('Pick a look', 'You can change any of this later.'),
    ('Where should downloads go?', 'Downloaded chapters are readable offline and can be exported as EPUB.'),
    ('Your sources', 'AO3 and SpaceBattles are built in. More sources come as extensions.'),
    ('Stay in the loop', 'Noctua checks for new chapters in the background and can let you know.'),
    ('Bring your library', 'Already have fics saved somewhere? Bring them in now.'),
  ];

  void _finish() {
    ref.setPref(Prefs.setupDone, true);
    context.router.replaceAll([const TourRoute()]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (title, lead) = _steps[_step];
    final last = _step == _steps.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < _steps.length; i++)
                          Expanded(
                            child: Container(
                              height: 4,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: i <= _step ? c.primary : c.outlineVariant,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _finish, child: const Text('Skip setup')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('STEP ${_step + 1} OF ${_steps.length}', style: context.text.labelSmall?.copyWith(color: c.primary)),
                  const SizedBox(height: 4),
                  Text(title, style: context.text.headlineMedium),
                  const SizedBox(height: 8),
                  Text(lead, style: context.text.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                ],
              ),
            ),
            Expanded(child: SingleChildScrollView(child: _body(context))),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  if (_step > 0) TextButton(onPressed: () => setState(() => _step--), child: const Text('Back')),
                  const Spacer(),
                  Flexible(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(140, 48)),
                      onPressed: last ? _finish : () => setState(() => _step++),
                      child: Text(
                        last ? 'Finish and take the tour' : (_step == 3 ? 'Allow notifications' : 'Next'),
                        textAlign: TextAlign.center,
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
```

- `final (title, lead) = _steps[_step];` destructures the current step's record into two variables.
- The progress bar is five `Expanded` containers in a `Row`, colored up to the current step.
- "Skip setup" and "Finish" both call `_finish`, which marks setup done and `replaceAll`s the stack with the tour, so back can't return to setup.
- The button's `Flexible` wrapper and `textAlign: TextAlign.center` let a long label ("Finish and take the tour") wrap at large font sizes instead of overflowing.

Each step's controls write preferences directly, so choices apply immediately. The first step reuses the theme cards' idea in a compact form:

```dart
class _LookStep extends ConsumerWidget {
  const _LookStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.pref(Prefs.appTheme);
    final dark = ref.pref(Prefs.darkMode);
    final options = [
      ('System', 'catppuccin', 'system', mochaScheme),
      ('Mocha', 'catppuccin', 'dark', mochaScheme),
      ('Latte', 'catppuccin', 'light', latteScheme),
      ('E-ink', 'eink', 'light', einkScheme),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        for (final (label, id, mode, s) in options)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              ref.setPref(Prefs.appTheme, id);
              ref.setPref(Prefs.darkMode, mode);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: s.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme == id && dark == mode ? context.colors.primary : context.colors.outlineVariant,
                  width: theme == id && dark == mode ? 3 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 8,
                    width: 60,
                    decoration: BoxDecoration(color: s.onSurface, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(color: s.primaryContainer, borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(color: s.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(color: s.onSurface, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

`RadioGroup` (Flutter 3.35+) owns the selected value for every `RadioListTile` inside it, replacing the older per-tile `groupValue` and `onChanged`.

**Step 2: the tour.** A `PageView` of six pages from a list of records `(title, body, icon)`, with dots and Next/Skip:

```dart
@RoutePage()
class TourPage extends ConsumerStatefulWidget {
  const TourPage({super.key});

  @override
  ConsumerState<TourPage> createState() => _TourPageState();
}

class _TourPageState extends ConsumerState<TourPage> {
  final _pages = PageController();
  int _i = 0;

  static const _content = [
    (
      'Your library, your way',
      'Sort works into categories, browse them as covers, a list or detail cards, and narrow them down by tags, fandoms and characters.',
      Symbols.collections_bookmark_rounded,
    ),
    (
      'Keep several works open',
      'Like browser tabs: jump between works mid-chapter without losing your place. The counter in the top bar shows how many are open.',
      Symbols.tab_rounded,
    ),
    (
      'A reader that fits you',
      'Twelve reading fonts, page colors from Mocha to Sepia, paged or scrolling, an e-ink mode, and read-aloud when your eyes need a break.',
      Symbols.auto_stories_rounded,
    ),
    (
      'Know when the next chapter lands',
      'Updates collects new chapters from everything you follow, and learns each author’s rhythm to guess when the next one is due.',
      Symbols.event_upcoming_rounded,
    ),
    (
      'Offline, and on every device',
      'Download chapters to read anywhere. Sign in to sync your library, progress and open works between your phone, tablet and e-reader.',
      Symbols.cloud_sync_rounded,
    ),
    ('Written by people', 'Noctua is made for fiction people wrote. Here’s how it handles AI.', Symbols.edit_note_rounded),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }
```

`_done` sets `coachPending`, which the library page watches ([[Milestone 06 - The library|milestone 6]], step 6): the first time the library appears, the coach marks run over it. The last tour page is the AI choices from the `ai` feature, embedded as a widget, so the same switches appear in Settings › AI and content.

The tour can be replayed from More and About:

```dart
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noctua/src/preferences/pref.dart';
import 'package:noctua/src/preferences/preferences_repository.dart';
import 'package:noctua/src/routing/app_router.gr.dart';

/// Replays the first-run tour (from More and About).
void replayTour(BuildContext context, WidgetRef ref) {
  ref.setPref(Prefs.tourDone, false);
  context.router.push(const TourRoute());
}
```

**Step 3: coach marks.** An overlay that dims everything except one control, with a card explaining it. Each step points at a widget through a `GlobalKey`:

```dart
import 'package:flutter/material.dart';
import 'package:noctua/src/theme/palettes.dart';

class CoachStep {
  const CoachStep(this.target, this.title, this.body);
  final GlobalKey target;
  final String title;
  final String body;
}

/// Dims the screen except for one control at a time, with a short explanation.
class CoachMarks extends StatefulWidget {
  const CoachMarks({super.key, required this.steps, required this.onDone});
  final List<CoachStep> steps;
  final VoidCallback onDone;

  @override
  State<CoachMarks> createState() => _CoachMarksState();
}

class _CoachMarksState extends State<CoachMarks> {
  int _i = 0;

  @override
  void initState() {
    super.initState();
    // Targets are measured from the previous frame, so rebuild once they're laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final overlay = context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return (topLeft & box.size).inflate(4);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final last = _i == widget.steps.length - 1;
    return LayoutBuilder(
      builder: (context, box) {
        final rect = _rectOf(step.target) ?? Rect.fromCenter(center: box.biggest.center(Offset.zero), width: 0, height: 0);
        final below = rect.center.dy < box.maxHeight / 2;
        final c = context.colors;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {},
                child: CustomPaint(painter: _SpotlightPainter(rect, c.primary)),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: below ? rect.bottom + 12 : null,
              bottom: below ? null : box.maxHeight - rect.top + 12,
              child: Material(
                color: c.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_i + 1} of ${widget.steps.length}', style: context.text.labelSmall?.copyWith(color: c.primary)),
                      const SizedBox(height: 4),
                      Text(step.title, style: context.text.titleLarge),
                      const SizedBox(height: 4),
                      Text(step.body, style: context.text.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      // Wraps onto two lines with large text instead of overflowing.
                      OverflowBar(
                        alignment: MainAxisAlignment.spaceBetween,
                        overflowAlignment: OverflowBarAlignment.end,
                        children: [
                          TextButton(onPressed: widget.onDone, child: const Text('Skip tour')),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_i > 0) TextButton(onPressed: () => setState(() => _i--), child: const Text('Back')),
                              FilledButton(
                                onPressed: last ? widget.onDone : () => setState(() => _i++),
                                child: Text(last ? 'Start reading' : 'Next'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.hole, this.ring);
  final Rect hole;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(hole, const Radius.circular(16));
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(r);
    canvas.drawPath(scrim, Paint()..color = const Color(0xC711111B));
    canvas.drawRRect(
      r,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole || old.ring != ring;
}
```

- `_rectOf` finds the target's `RenderBox` through its key, and converts its position into the overlay's coordinates with `localToGlobal(Offset.zero, ancestor: overlay)`. `inflate(4)` leaves a little room around the control.
- Positions only exist after layout, so `initState` schedules one rebuild after the first frame. If a target isn't laid out yet, the spotlight collapses to a zero-size rect in the centre rather than crashing.
- The card goes below the target when the target is in the top half of the screen, and above it otherwise.
- `_SpotlightPainter` draws a full-screen rectangle and the rounded target rectangle into one `Path` with `PathFillType.evenOdd`: where the shapes overlap, the fill cancels out, leaving a hole. A stroked rounded rectangle on top draws the ring.
- The `GestureDetector` with an empty `onTap` swallows taps on the dimmed area, so the user can't accidentally press something behind the overlay.
- `OverflowBar` lays out "Skip tour" and Back/Next on one line, and stacks them when there isn't room.

In the library, the overlay sits in a `Stack` above the scaffold:

```dart
if (coach)
  Positioned.fill(
    child: CoachMarks(
      onDone: () => ref.setPref(Prefs.coachPending, false),
      steps: [
        CoachStep(_tabsKey, 'Categories', 'Swipe between your categories. Long-press a work to select several and move them.'),
        CoachStep(_filterKey, 'Filter and display', 'Filter by tags, fandoms and status, sort, and switch between covers, list and cards.'),
        CoachStep(_tabCountKey, 'Open works', 'Works you’re reading stay open like browser tabs. Tap to switch between them.'),
        CoachStep(_searchKey, 'Search everything', 'Find works by title, tag or author, and passages inside downloaded chapters.'),
      ],
    ),
  ),
```

`KeyedSubtree(key: _tabCountKey, child: const TabCountButton())` attaches a key to a widget that doesn't take one, so it can be spotlighted too.

**Step 4: routes.** Register `SetupRoute` and `TourRoute`. Neither belongs inside the home shell: they replace the whole stack.

> [!success] Checkpoint
> register a new account. You go through setup, the tour ending on the three AI switches, then land on the library with the first coach mark highlighting the categories.

![[noctua-m12-onboarding.png]]
*Milestone 12: setup, the last tour page and the first coach mark*

---
← [[Milestone 11 - Accounts and sync]] · [[00 Index|Index]] · [[Milestone 13 - Errors, tablets and e-ink]] →
