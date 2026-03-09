# PEG vs Parsimonious: Snapshot

Reference: [Parsimonious](https://github.com/erikrose/parsimonious)

## Feature Comparison

| Area | This PEG repo | Parsimonious | Note |
|---|---|---|---|
| Core PEG ops + ranges | yes | yes | parity |
| Explicit whitespace model | yes | partial | grammar-authored (`_ws`) |
| Rule visibility shaping | yes | partial | `@silent`, `@squashed` |
| Regex-like lexical primitive | yes | yes | lexical scope only |
| Left recursion support | partial | no | lite direct rewrite |
| Memo control | yes | partial | global + per-rule |
| Compile-time lint | yes | no | static diagnostics |
| Runtime trace/stats | yes | partial | explicit trace/stats APIs |
| Detailed errors | yes | yes | includes truncation marker |
| Tree traversal sugar | partial | yes | `Walker`, `NodeIterator` minimal |

## Key Differences

- This repo prefers explicit contracts over implicit parser behavior.
- Whitespace handling is explicit (more boilerplate, fewer hidden rules).
- Lint/trace/memo controls are stronger but introduce more knobs.

## Current Scope

- Input mode is text/bytes only (no token-stream mode).
- Regex-like primitive is intentionally limited to lexical use-cases.
