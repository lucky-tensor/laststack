# Benchmarks
Run: 2026-03-04T18:01:28Z

| scenario | rps | p95_latency_s |
|---|---:|---:|
| single_vu | 3538.344391733374 | 0.14839385 |
| 1000_vus | 8906.643100971558 | 18.492462649999997 |

## Previous runs
# Benchmarks

This file is updated by CI (k6 smoke + load scenarios) and uploaded as the `k6-summary/benchmark.md` artifact. It is also kept in-repo for quick reference.

## Current snapshot (placeholder until CI runs)
| scenario | rps | p95_latency_s |
|---|---:|---:|
| single_vu | _pending CI_ | _pending CI_ |
| 1000_vus | _pending CI_ | _pending CI_ |

## Notes
- CI runs two scenarios against the demo server: 1 VU for 10s, and 1000 VUs for 10s.
- Metrics come from `k6 run --summary-export` JSON (`http_reqs.rate`, `http_req_duration p(95)`).
- Raw JSON summaries are published as artifacts (`k6-single.json`, `k6-1000.json`).
