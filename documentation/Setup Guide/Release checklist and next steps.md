---
title: "Release checklist and next steps"
tags:
  - noctua
  - noctua/guide
updated: 2026-11-06
---
# Release checklist and next steps

Before the first public beta:

- [ ] Upload key created, backed up, and the four secrets added ([[Milestone 02 - Release pipeline for beta and stable|milestone 2]])
- [ ] `githubOwner` and `githubRepoName` in `lib/src/constants/app_config.dart` point at the real repository ([[Milestone 03 - In-app updates|milestone 3]])
- [ ] First tester invite sent with the [[Milestone 03 - In-app updates|milestone 3]] beta; everything after arrives in-app
- [ ] Google button uses Google’s official “G” asset, and the OAuth client matches the upload key’s SHA-1
- [ ] Bookerly either licensed and bundled, or removed from the font list
- [ ] Launcher icons and splash screens for both flavors (mauve for Noctua, peach for Noctua Beta), regenerated after any change to `assets/branding/`
- [ ] Mihon’s licence shipped with the theme port, and Inter/Literata OFL notices in the licences page
- [ ] `flutter test` green on `main`, then set `pubspec.yaml` to 1.0.0 on `develop` and tag `v1.0.0` on `main` once its betas hold up

What comes after this guide, in the order that unblocks the most:

1. **Sync server.** Switch `authRepositoryProvider` to the real `AuthRepository`, then give the other repositories (`LibraryRepository`, `TabsRepository`, `WorksRepository`, a new `ProgressRepository`) method bodies that call the server instead of serving samples. Controllers and screens don’t change.
2. **Real sources.** An AO3 source behind `ChaptersRepository` and a `SourceRepository` in `browse/data/`, with request pacing, then SpaceBattles, then the extension loader. Make the fetch methods return `Future`s and the providers `FutureProvider`s, as `chapterTextProvider` already is.
3. **Real reader pagination** that measures text against the viewport instead of three paragraphs per page.
4. **Google Play**, if wanted: a workflow that builds the app bundle with `--dart-define=PLAY_STORE=true` (updater off) and removes `REQUEST_INSTALL_PACKAGES`, then uploads to the beta or production track.
5. **JSON for the domain models** (`json_serializable` alongside Freezed) once the server’s responses are fixed; the repositories do the mapping, so the models stay plain.

---
← [[Milestone 14 - The full test suite]] · [[00 Index|Index]]
