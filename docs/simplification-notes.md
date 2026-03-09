# Simplification Notes

Predictable model for this PEG library: explicit behavior over implicit magic.

## Invariants

- Full-consume parsing is default: `parse(...)` and `parseDetailed(...)` behave as `.consume_mode = .full`.
- Prefix parsing is opt-in only: `parseWithOptions(..., .{ .consume_mode = .partial })`.
- Whitespace/trivia are grammar-authored (`_ws`, `_sp`, etc.); no implicit auto-whitespace.
- Rule visibility is explicit: `@silent` hides helper rules, visible by default.
- Memo policy is explicit: global `memo_mode` plus per-rule `@memo_on` / `@memo_off`.
- Left recursion handling is explicit: `.off | .lint | .rewrite`.
- `.rewrite` supports only lite direct-left form (`A <- A tail / base`); unsupported shapes fail at compile time.

## Runtime Contracts

- Repeats (`*`, `+`, `{n,m}`) stop on zero-width iterations (infinite-loop guard).
- `.full` fails on trailing input; `.partial` succeeds on prefix and returns boundary in `result.pos`.
- `max_recursion_depth` limits runtime recursion (`0` disables the guard).
- Memo key position uses `u32`; inputs above 4 GiB fail deterministically.
- `DetailedError.expected_items` reports up to 5 unique expectations; `expected_truncated` signals overflow.
- `DetailedError.line/col` are byte-based positions.

## Practical Path

- Default flow: `peg.compile(...)` -> `grammar.parse(...)` / `grammar.parseDetailed(...)`.
- Advanced flow: `parseWithOptions(...)`, `parseDetailedWithOptions(...)`, `compileWithOptions(...)`.

## Minimal Example

```zig
const g = peg.compile(
    \\expr <- _ws sum _ws
    \\sum <- number (_ws '+' _ws number)*
    \\number <- [0-9]+
    \\@silent _ws <- [ \t]*
);

_ = try g.parse(allocator, "expr", "1 + 2");
_ = try g.parseWithOptions(allocator, "expr", "1 + 2 trailing", .{
    .consume_mode = .partial,
});
```
