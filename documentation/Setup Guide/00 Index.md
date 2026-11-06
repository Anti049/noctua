---
title: Building Noctua
tags:
  - noctua
  - noctua/guide
updated: 2026-11-06
---

# Building Noctua: a step-by-step guide

Noctua is a Flutter fanfiction library, browser and reader for Android, built like Mihon. This guide rebuilds it from an empty folder in 14 milestones, following Andrea Bizzotto's feature-first Riverpod architecture.

Start with [[01 Overview]] and [[02 Architecture]], then work through the milestones in order.

## Milestones

1. [[Milestone 01 - Project setup and the folder structure|Project setup and the folder structure]]: Folder structure, code generation
2. [[Milestone 02 - Release pipeline for beta and stable|Release pipeline for beta and stable]]: CI and releases
3. [[Milestone 03 - In-app updates|In-app updates]]: All four: `app_update`
4. [[Milestone 04 - Preferences and the local database|Preferences and the local database]]: Shared: database, preferences
5. [[Milestone 05 - Theming and the app shell|Theming and the app shell]]: Shared: theme, routing
6. [[Milestone 06 - The library|The library]]: `work`, `library`
7. [[Milestone 07 - Work details|Work details]]: `work`, `ai`
8. [[Milestone 08 - The reader and open works|The reader and open works]]: `tabs`, `reader`
9. [[Milestone 09 - Updates, History, Browse and sources|Updates, History, Browse and sources]]: `updates`, `history`, `browse`, `downloads`
10. [[Milestone 10 - Settings|Settings]]: `settings` and feature settings pages
11. [[Milestone 11 - Accounts and sync|Accounts and sync]]: All four: `auth`
12. [[Milestone 12 - Onboarding|Onboarding]]: `onboarding`
13. [[Milestone 13 - Errors, tablets and e-ink|Errors, tablets and e-ink]]: `errors`, crash guard, tablet, e-ink
14. [[Milestone 14 - The full test suite|The full test suite]]: Tests for every layer

When you are done: [[Release checklist and next steps]].
