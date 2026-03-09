# Regex-like vs PEG Audit

Current policy and status for `examples/*`.

## Policy

- Use regex-like (`~"..."` / `~'...'`) only for lexical token shapes.
- Keep syntax structure in PEG composition (sequence/choice/lookahead/repeat/ref).
- Do not encode statement/grammar structure as a single regex-like token.
- Keep style consistent per file (avoid mixing styles for the same token family without reason).

## Current Status

Regex-like is currently used in:

- `examples/graphql/graphql.zig`
- `examples/graphql_strict/graphql_strict.zig`
- `examples/http/http.zig`
- `examples/http_strict/http_strict.zig`

All other examples are PEG-first.

## Change Guidance

- Token-level rewrites are acceptable in both directions (`~"..."` <-> PEG char class/sequence) if readability improves.
- Do not rewrite syntax-level rules during token-style cleanup.
- Preserve `_ws` boundaries and lookahead behavior.
- Preserve AST shape where tests assert tags/structure.

## Validation Checklist

After token-style changes:

- Run targeted suite for touched examples (for example `test-graphql`, `test-http`).
- Run `test-main` for core engine regressions.
- Run aggregate `test` when environment allows.
