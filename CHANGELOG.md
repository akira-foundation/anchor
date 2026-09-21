# Changelog

## Unreleased

### Changed

- Context query reader protocols now require a `ContextCursorBinding` when
  paginating. Driver implementations and direct callers must pass the authorized
  workspace path and current read-model generation; version 1 cursors are no
  longer accepted.
- `ContextEngineAssembly.makeSessionContext` now requires an injected persistent
  `SQLiteDatabase`. Callers must open a read-model writer and pass its database.
- Context query actions now require an availability reader. Callers must inject
  the read-model status store so queries reject stale or rebuilding indexes.
