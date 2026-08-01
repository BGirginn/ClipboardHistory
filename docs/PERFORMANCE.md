# Performance report

The release thresholds are measured in optimized Release after warm-up, at least ten repetitions, and reported at p95. They include 5,000-item write <=100 ms, read <=50 ms, ViewModel load <=100 ms, filter <=50 ms, first layout <=50 ms, panel visible p95 <=120 ms, idle median CPU <1%, stable RSS <75 MB, and an eight-hour soak with <10% post-warm-up growth.

## Current automated evidence

On 2026-08-01, `scripts/verify-performance.sh` passed the optimized arm64 Release benchmark after warm-up with ten repetitions and p95 assertions for the 5,000-item write/read, ViewModel load, filtering, and panel-layout operations.

This closes the automated numeric benchmark gate. Actual panel-visible latency, idle CPU, RSS, long-scroll frame pacing, large-payload stress, Instruments traces, and the eight-hour soak remain required external evidence.

## Earlier provisional observation

On 2026-07-31, the Debug XCTest benchmark on the local macOS 26.5 arm64 host reported:

| Operation | Observed |
|---|---:|
| 5,000-item SQLite batch write | 64.653 ms |
| 5,000-item SQLite read | 38.342 ms |
| ViewModel load | 83.750 ms |
| Search/filter | 37.166 ms |
| SwiftUI panel render construction | 17.930 ms |

These older values are retained only as a baseline. The current automated p95 result above supersedes them; startup, panel-visible latency, scroll frame pacing, CPU/RSS, large payload stress, Instruments, and soak gates remain pending.
