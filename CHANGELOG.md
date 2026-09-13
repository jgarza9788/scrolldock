# Changelog

All notable changes to Scroll Dock are documented in this file.

## [Unreleased]

### Fixed
- `hyprctl` layout probe: the output-overflow handler could reset the
  already-armed `SIGKILL` deadline timer (`restart()` → `start()`), letting a
  wedged process that ignores `SIGTERM` while still emitting output push the
  hard kill deadline back by an extra grace period instead of being bounded
  by it.
- `hyprctl` layout probe: the 8KB output ceiling compared UTF-16 code-unit
  count against a value named/documented as a byte limit, undercounting
  multi-byte UTF-8 output by up to ~3x. Added a `utf8ByteLength()` helper so
  the ceiling now measures actual bytes.

### Changed
- `hyprctl` layout probe: the overflow path now guards its `SIGTERM` signal
  call with a `layoutProbe.running` check, matching the pattern already used
  by the deadline and kill timers, instead of relying on the process
  library's internal no-op behavior for an already-exited process.
