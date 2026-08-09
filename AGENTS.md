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
- Never commit Superpowers, Graphify, brainstorm, plan, spec, or AI context artifacts. They are ignored in `.gitignore` and must never be force-added. Verify what is about to be committed first: `jj diff --name-only` under jujutsu, `git diff --cached --name-only` under git. Using the wrong one reports an empty set rather than an error, so the check passes while the artifacts go through.

<!-- init-jj:start -->

## Version Control: Jujutsu

This repository uses Jujutsu (`jj`) as the primary local VCS interface for
agents. Git remains the backend: remotes, GitHub, CI and external Git tooling
all keep working against the same `.git` directory.

    local agent interface = jj
    backend and interoperability = git

Detection is automatic. `jj root` succeeding means jujutsu, even though `.git`
is also present, because a colocated repository always carries both, and its index is
not the change `jj` commits.

### Use jj for local work

Inspect with `jj status`, `jj diff`, `jj log`.

Rewrite local history with `jj split`, `jj squash`, `jj rebase`, `jj edit`,
`jj abandon`.

Do not reach for the Git equivalents `git rebase`, `git commit --amend`,
`git reset`. They rewrite the same commits from the other side, and the two
views then disagree. Do not mix the two in one piece of work.

Reaching for Git out of habit is the failure to watch for, because in a
colocated repository the Git command usually succeeds and simply answers
about the wrong thing. Every inspection has a jj form:

    git status                  ->  jj status
    git diff                    ->  jj diff
    git diff --cached           ->  jj diff          (jj writes no index)
    git diff --name-only        ->  jj diff --name-only
    git log                     ->  jj log
    git rev-parse --short HEAD  ->  jj log -r @- --no-graph -T 'commit_id.short(7)'
    git branch                  ->  jj bookmark list
    git ls-remote origin        ->  jj bookmark list --all-remotes
    git fetch                   ->  jj git fetch
    git push                    ->  jj git push

The index queries are the dangerous ones. `git diff --cached` under jujutsu
returns an empty set rather than an error, because jj never writes the index.
Any check built on it reports success while missing everything, which is the
worst way for a safety check to fail.

### Identity must be configured before the first commit

A fresh jj installation has no user name or email, and a repository
initialized before they are set produces commits with an empty identity that
no remote will accept. The failure appears at push time, long after the
commit.

    jj config get user.name
    jj config get user.email

If either is missing, set them from the Git identity the repository already
uses, then repair any commit already made with the empty one:

    jj config set --user user.name "<name>"
    jj config set --user user.email "<email>"
    jj metaedit --update-author -r <revision>

Setting the config alone does not fix commits that already exist. jj says so
when it happens; the repair is the second step.

### Every finalized commit

Inspect `jj status` and `jj diff` before finalizing. If the working-copy
change covers more than one concern, `jj split` it first: one logical concern
per commit, independently understandable, reviewable and revertible.

Finalize with `jj commit -m "<message>"`. There is no separate wrapper
command: commit-guard gates `jj commit`, `jj describe` and `jj squash`
directly, so a failed validation stops the commit. `jj split` is deliberately
left open, because splitting is how a non-atomic change gets fixed.

Messages follow Conventional Commits:

    feat(storage): add the iCloud storage driver
    fix(sync): prevent duplicate synchronization
    feat(api)!: replace the authentication contract

A breaking change MUST carry `!` before the colon. A `BREAKING CHANGE:` footer
may explain the break; it does not declare one. Semver reads the subject:

    fix   -> PATCH
    feat  -> MINOR
    !     -> MAJOR   (outranks the type)

### Bookmarks are not branches

A Git branch follows you: commit, and it advances. A jj bookmark does not. It
is a named pointer at one commit, and it stays there until it is moved by
hand.

    jj bookmark create <name> -r @-      create at the last finalized commit
    jj bookmark move <name> --to @-      move it forward after committing again
    jj git push --bookmark <name>        publish it
    jj bookmark list --all-remotes       see local, @git and @origin at once

Point a bookmark at `@-`, not `@`. The working copy `@` is itself a commit,
usually empty and undescribed, so a bookmark on `@` publishes that empty
commit instead of the work.

This is the mistake to expect from anyone arriving from Git: finalize three
changes, push, and discover only the first one went, because the bookmark
never moved. After every `jj commit` that should end up on a published
bookmark, move the bookmark before pushing, or use:

    jj git push --change @-

which derives the bookmark from the change id and publishes in one step.

Bookmarks are ordinary Git refs in a colocated repository, so any Git-side
branch convention the repository already enforces keeps working unchanged.
Only the command that creates them differs.

### Track the trunk once, or it never follows the remote

The same standing-still rule applies to the trunk, and it bites harder because
it is silent.

The trap belongs to `jj git init --colocate` over a repository that already
has a remote, which is how an existing project adopts jujutsu. It prints a
hint that the remote bookmark has no local counterpart and does nothing about
it. `jj git clone` tracks on its own and is unaffected.

Left untracked, the local trunk never advances:

    main: ksrmrvtt 957eaa0d          (empty) Merge pull request #2
    main@origin: xyuyytqs fc45dde4   (empty) Merge pull request #3

The listing shows it: an untracked remote bookmark sits at the left margin as
`name@remote`, while a tracked one is indented as `@remote` under its local
name. After a fetch, `main@origin` carries the merge that just landed and
`main` still points at the previous one. Nothing errors, and work started from
the local trunk is based on a stale commit.

Fix it once, per repository, and every later fetch advances the local bookmark
on its own:

    jj bookmark track main@origin

`/init-jj` now runs this during initialization, so an adopted repository
arrives already tracked. Do it by hand only where that did not run.

### After a pull request merges

    jj git fetch                     bring the merge down
    jj bookmark list --all-remotes   confirm local, @git and @origin agree
    jj new main                      start the next change on the merged trunk

The forge usually deletes the feature bookmark when it merges, so the fetch
removes it locally too and there is nothing to clean up by hand. Check the
listing rather than assuming either way.

Starting the next change with `jj new <trunk>` matters: the working copy is
otherwise still a child of the pre-merge commit, and the next change is built
on the wrong base without any warning.

### Pull requests

Jujutsu has no pull request command. `jj git` covers clone, colocation,
export, fetch, import, init, push, remote and root, and nothing more: a pull
request is a forge concept, not a VCS one.

Publish the bookmark with `jj git push`, then open the request with the forge
CLI, `gh` for GitHub. Everything up to that point stays in jj.

### Never

Never bypass validation: no `--no-verify`, no disabled tests, no suppressed
failures, no hand-written commit-guard marker, no re-running a blocked command
unchanged.

Never push without the validation this repository requires.

Commits, pushes, bookmarks, branches and pull requests still require explicit
user authorization, exactly as before.
<!-- init-jj:end -->
