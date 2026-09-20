# Changelog

## Unreleased

### Changed

- `ContextEngineAssembly.makeSessionContext` now requires an injected persistent
  `SQLiteDatabase`. Callers must open a read-model writer and pass its database.
- Context query actions now require an availability reader. Callers must inject
  the read-model status store so queries reject stale or rebuilding indexes.
