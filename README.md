# Anchor

Anchor is a persistent, cross-device context layer for AI-assisted software development across Apple devices.

## Status

Early development. This repository currently contains the project scaffold only: the workspace, application targets, Swift package boundaries, and their tests. No product feature is implemented yet.

Everything under "Planned" below is a target, not a shipped capability.

## Platforms

| Client | Platform | Role |
| --- | --- | --- |
| AnchorMac | macOS 26+ | Primary development client |
| AnchorMobile | iOS 26+, iPadOS 26+ | Companion client, one adaptive target for iPhone and iPad |

## Planned

Anchor is intended to integrate with Claude Code, Codex, MCP, and iCloud, and to synchronize project context, sessions, knowledge, conflicts, and timeline across devices. None of these integrations exist in the repository today, and none of their behavior has been implemented or assumed.

## Repository layout

```
Apps/
  AnchorMac/        macOS application target
  AnchorMobile/     iOS and iPadOS application target
Packages/
  AnchorFoundation  cross-cutting primitives
  AnchorDomain      pure business domain
  AnchorApplication use cases and actions
  AnchorPersistence persistence contracts
  AnchorStorage     storage contracts
  AnchorSync        synchronization contracts
  AnchorSearch      search contracts
  AnchorKnowledge   knowledge extraction contracts
  AnchorSharedUI    shared SwiftUI presentation components
Scripts/            verification scripts
Anchor.xcworkspace
```

## Package dependency graph

```
AnchorFoundation
    ├── AnchorDomain
    │       ├── AnchorApplication
    │       │       └── AnchorSync
    │       ├── AnchorPersistence
    │       ├── AnchorStorage
    │       ├── AnchorSearch
    │       └── AnchorKnowledge
    └── AnchorSharedUI
```

Dependencies point inward only. `AnchorDomain` depends on nothing but `AnchorFoundation` and imports no UI framework.

## Requirements

- Xcode 26.6 or later
- Swift 6.3

## Building and testing

Open `Anchor.xcworkspace`, or run the full verification from the repository root:

```bash
./Scripts/verify-scaffold.sh
```

Formatting is enforced by `swift format` against `.swift-format`:

```bash
./Scripts/format.sh
```

Pass `--lint` to check without rewriting, which is what CI runs.

Every push to `main` and every pull request runs formatting, the nine package
test suites in parallel, the dependency boundary check, and both application
builds.

## Dependencies

None. The scaffold uses only the Swift standard library and Apple frameworks.

## Engineering contract

`AGENTS.md` defines the mandatory engineering rules for this repository. Read it before contributing.
