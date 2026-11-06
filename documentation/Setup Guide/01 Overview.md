---
title: "Overview"
tags:
  - noctua
  - noctua/guide
updated: 2026-11-06
---
# Overview

This guide rebuilds Noctua from an empty folder in 14 milestones, release pipeline first. [[Milestone 02 - Release pipeline for beta and stable|Milestone 2]] sets up GitHub Actions to publish beta and stable builds, and [[Milestone 03 - In-app updates|milestone 3]] adds in-app updates, so test users install Noctua Beta once and receive every later milestone as an update. [[Milestone 04 - Preferences and the local database|Milestone 4]] adds the preferences everything else reads, [[Milestone 05 - Theming and the app shell|milestone 5]] the theme and app shell, and the rest build one feature each. Each milestone uses only what earlier milestones built.

Noctua is a fanfiction library, browser and reader for Android, built like Mihon: works from AO3, SpaceBattles and FanFiction.net sit in a categorized library, open as browser-style tabs, and read in a configurable reader. A sync server holds the library, progress, open tabs and settings across devices.

| Layer | Package | Why this one |
| --- | --- | --- |
| UI | Flutter 3.35+ (Dart 3.9+), Material 3 | One codebase, M3 components, good tablet support |
| State | flutter\_riverpod 3 + riverpod\_annotation / riverpod\_generator | Providers written as annotated functions and classes; the generator names and wires them |
| Models | freezed + freezed\_annotation | Immutable data classes with `==`, `copyWith` and `toString` generated |
| Navigation | auto\_route 10 | Typed routes with arguments, nested tabs for the shell |
| Local database | drift 2 + drift\_flutter | Typed SQLite for preferences and open tabs, with migrations |
| Networking | dio | One configured client for GitHub releases now and the sync API later |
| Theming | flex\_color\_scheme 8, dynamic\_color | Fixed schemes (Catppuccin, Mihon, E-ink) plus Material You’s wallpaper colours on Android 12+ |
| Layout | responsive\_framework | Named window sizes (compact to large) that the shell and library switch on |
| App identity | flutter\_flavorizr, flutter\_launcher\_icons, flutter\_native\_splash | Stable and beta flavors, each with its own icon and splash screen |
| Fonts and icons | google\_fonts, material\_symbols\_icons | Inter for UI, 12 reading fonts, rounded Material Symbols |
| Updates | ota\_update, package\_info\_plus, device\_info\_plus | Download, verify and install releases from GitHub |
| Secrets | flutter\_secure\_storage | Sync token kept out of the database |

The code follows Andrea Bizzotto's [Riverpod app architecture](https://codewithandrea.com/articles/flutter-app-architecture-riverpod-introduction/): **feature-first** folders under `lib/src/features/`, each split into presentation, application, domain and data layers. The next section explains the layers once; every milestone then says which layer each new file belongs to.

How to use it:

- Work through the milestones in order. Later ones assume the files from earlier ones exist, and no milestone uses a file from a later one. When a finished file contains lines for a later milestone, the walkthrough says what to leave out for now.
- Each milestone lists the files it adds, then a **Code walkthrough** that goes through the code step by step, and ends with a **Checkpoint**: what to run and what you should see. Skim the list for the shape of the milestone; follow the walkthrough when you write the code.
- The screenshots come from the finished project's widget tests, run at a 412 × 915 phone size (tablet shots at 1280 × 800), so they show the real Flutter UI rather than mockups.
- Walkthrough code is copied from the finished project, so it compiles as shown. Logic files appear whole; long screens are shown in their important parts, with the rest described. The finished project zip is the reference for anything not shown.
- All data is sample data served by repositories until the sync server and sources exist. Swapping a repository's method bodies for real calls leaves every screen unchanged; [[Milestone 11 - Accounts and sync|milestone 11]] shows it for accounts.

---
[[00 Index|Index]] · [[02 Architecture]] →
