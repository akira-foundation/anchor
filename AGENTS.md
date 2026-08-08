# Engineering contract

These rules are mandatory for every change to this repository, human or agent authored. They are not stylistic preferences.

## Design principles

- **SOLID.** Single responsibility per type. Depend on abstractions, not concretions.
- **KISS.** The simplest design that satisfies the requirement wins.
- **DRY.** One authoritative definition per concept.
- **YAGNI.** Do not build for a requirement that does not exist yet.
- **Composition over inheritance.** Do not create `BaseProvider`, `BaseService`, `BaseRepository`, or similar hierarchies unless an Apple framework requires subclassing. Build behavior by composing focused types behind protocols.
- **Protocol-driven design.** Small protocols with few requirements. A protocol with many unrelated requirements is at least two protocols.
- **Contract / Driver pattern.** Contracts are declared as protocols in the owning package; concrete drivers are supplied by the composing target.
- **Action pattern.** Application use cases conform to `Action` and are named for the operation they carry out.
- **Pipeline / composition pipeline.** Compose multi-stage operations from independently testable stages.
- **Value objects.** Model domain values as immutable types with validating initializers.
- **Immutability by default.** Prefer `let`. Introduce mutable state only where required, and confine it in an `actor`.
- **Guard clauses.** Reject invalid input at the top of a function. Do not nest the happy path.

## Explicit naming

Names must describe exactly what they do.

Banned as function names: `sync`, `process`, `handle`, `execute`, `get`.

Banned as variable names: `data`, `item`, `result`, `object`, `obj`, `tmp`, `value`, `manager`, `helper`, `utils`.

Preferred:

```swift
func resolveProjectIdentity(...)
func synchronizePendingArtifactRevisions(...)
func loadConversationMessages(...)
func createArtifactRevision(...)
func buildProjectResumeContext(...)

let projectRepositoryURL: URL
let canonicalProjectIdentifier: ProjectIdentifier
let pendingSyncOperation: SyncOperation
let conversationSession: AgentSession
let remoteArtifactRevision: ArtifactRevision
```

Do not abbreviate unless the abbreviation is universally understood in the domain.

## Dependency injection

No service locator. No unjustified singleton. The following are banned for application business dependencies:

```swift
App.shared
ServiceLocator.shared
Container.resolve(...)
```

Each application target owns an explicit composition root (`AnchorMacCompositionRoot`, `AnchorMobileCompositionRoot`), the only place concrete dependencies are constructed and wired. Dependencies must be visible in initializers.

Do not introduce `DependencyManager`, `ServiceManager`, or `GlobalContainer`.

## Swift concurrency

Prefer `async`/`await`, `AsyncSequence`, `actor`, and `Sendable`. Avoid callback chains except when adapting a framework API that requires them. Do not introduce concurrency without a concrete reason.

## Platform independence

Shared core packages must compile without SwiftUI, AppKit, UIKit, FSEvents, macOS process APIs, or `MenuBarExtra`.

`AnchorDomain` is platform-independent and must never depend on `AnchorStorage`, `AnchorPersistence`, `AnchorSync`, or any UI framework. Dependencies point inward only; the dependency graph must stay acyclic.

Platform-specific frameworks belong in application targets.

## No business logic in SwiftUI

SwiftUI views render state and forward user intent. They do not make decisions, perform I/O, or contain domain rules. `AnchorSharedUI` may import SwiftUI and must not reach iCloud, SQLite, the filesystem, Claude, Codex, Superpowers, or Graphify.

## No dumping grounds

`AnchorFoundation` holds cross-cutting primitives only. Domain concepts such as `Project`, `Artifact`, and `Session` belong in `AnchorDomain`. Do not create generic `Helpers`, `Utils`, `Extensions`, or `Common` modules.

## Test-driven development

Write the failing test first, watch it fail, make it pass, then refactor. Every behavioral change ships with a test that would fail without it.

Do not write tests that only inflate the test count. Do not remove or disable a test without approval.

## External behavior is never invented

If the behavior of an external system is unknown, investigate it before implementing against it. The behavior of Claude Code, Codex, Superpowers, Graphify, MCP, and iCloud must never be assumed, guessed, or inferred from a plausible-sounding API. Cite the source that establishes the behavior, or do not implement it.

## Process

- No automatic architectural changes. A deviation from the agreed architecture is proposed and approved before it is written.
- No automatic commits, pushes, or pull requests. The user decides when work is committed.
- No new third-party dependency without explicit approval.
- Never commit Superpowers, Graphify, brainstorm, plan, spec, or AI context artifacts. They are ignored in `.gitignore` and must never be force-added. Verify staged paths with `git diff --cached --name-only` before committing.
