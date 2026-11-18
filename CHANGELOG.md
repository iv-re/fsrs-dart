## 0.2.0

- **Breaking**: `FsrsReviewLog.stability` and `FsrsReviewLog.difficulty` now record pre-review values (matching `due`, `state`, and `ts-fsrs`) and include `step` and `lastReview` for lossless `rollback`.
- **Breaking (FFI ABI)**: Simplified native FFI surface (`fsrs_next_states` and `fsrs_compute_parameters` now write into caller-allocated buffers; added `fsrs_decay`; removed unused C exports).
- Fixed allocator layout mismatch UB in `fsrs_parameters_free` and null/empty slice safety in Rust FFI.
- Fixed `Fsrs` constructor native memory leak when scheduler argument validation fails.
- Fixed `rollback` to restore `memoryState`, `lastReview`, and `step` across all card states.
- Fixed `forget` to reset `step` to `0` and `lastReview` to `null`.
- Fixed `enableShortTerm: false` not incrementing `lapses` on `FsrsRating.again` for review cards.
- Fixed `_applyFuzz` throwing `ArgumentError` when `maximumInterval == 1`, and avoided unnecessary RNG draws in `reviewCard`.
- Fixed `getRetrievability` / `currentRetrievability` to use the model's configured `decay` parameter and fractional elapsed days.
- Fixed `reschedule` manual entries to preserve sub-day intervals and reset `step` appropriately.
- Fixed `FsrsRescheduleResult.==` and added `@immutable`, `==`, and `hashCode` to all model classes.
- Fixed `hook/build.dart` prebuilt cache collision across architectures (e.g. iOS Simulator arm64/x64), added hook dependency tracking, timeouts, and temp-file cleanup.
- Fixed `src/build.rs` to avoid rewriting `fsrs_dart.h` when unchanged, and excluded `src/rust-toolchain.toml` from published archives.
- Moved `logging` to `dev_dependencies` and added CI workflow.

## 0.1.0

- Initial release.
