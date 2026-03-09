# API Guide

This document contains the expanded API reference for `src/peg.zig`.

## Compile-Time API

### `peg.compile(grammar) -> Grammar`

Compiles a PEG grammar string at comptime and returns `Grammar`.

### `peg.compileWithOptions(grammar, options) -> Grammar`

Compile with lint/rewrite controls:

- `lint_mode = .off | .warn | .strict`
  - `.off`: no lint pass
  - `.warn`: collect diagnostics (non-failing)
  - `.strict`: fail compilation on lint findings
- `left_recursion_mode = .off | .lint | .rewrite`
  - `.rewrite` supports lite direct-left recursion (`A <- A tail / base`)
  - unsupported direct-left-recursive shapes fail with explicit compile error in rewrite mode

### `peg.lint(grammar) -> []const LintDiagnostic`

Collect compile-time diagnostics without strict compilation mode.

Current lint kinds include:

- `unused_rule`
- `unreachable_rule`
- `nullable_rule`
- `suspicious_choice_order`
- `direct_left_recursion`

## Runtime Parse API

### `Grammar.parse(allocator, start_rule, input) -> !ParseSuccess`

Parse from a named start rule. Returns:

- `node`: parse tree root
- `pos`: consumed byte boundary

### `Grammar.parseWithOptions(allocator, start_rule, input, options) -> !ParseSuccess`

Parse with runtime options:

- `consume_mode = .full | .partial`
- `memo_mode = .on | .off`
- `stats = &ParseStats`
- `trace = true | false`
- `trace_buffer = &std.ArrayListUnmanaged(u8)`
- `max_recursion_depth = usize` (`0` disables depth guard)

### `Grammar.parseDetailed(allocator, start_rule, input) -> union{ok, err}`

Detailed parse result for diagnostics. Byte-based `line/col`.

### `Grammar.parseDetailedWithOptions(allocator, start_rule, input, options) -> union{ok, err}`

Detailed parse with runtime options (`memo_mode`, `stats`, `trace`, `trace_buffer`, recursion guard).

## Error/Diagnostic Contracts

- Default parse contract is full-input consumption.
- `.partial` must be explicitly selected.
- Repeats (`*`, `+`, `{n,m}`) stop when iteration consumes zero bytes.
- Memo cache key position uses `u32`; positions above 4 GiB fail deterministically.
- Detailed errors include:
  - `class`: `syntax | start_rule | oom | internal`
  - `expected`, plus `expected_items[0..expected_count]` (up to 5 unique)
  - `expected_truncated` when more than 5 items exist
  - `context_prev`, `context`, `context_next`

## Tree API

### `peg.printTree(node, indent) -> void`

Debug tree printing.

### `peg.writeTreeJson(writer, node) -> void`

Write tree JSON (`tag`, `text`, `children`) to writer.

### `peg.treeJsonAlloc(allocator, node) -> []const u8`

Allocate JSON tree string.

### `peg.freeNode(allocator, node) -> void`

Recursively release materialized child arrays for non-arena allocators.

## Traversal/Evaluation Helpers

### `peg.Walker(Result, Context) -> type`

Create a typed walker for tree evaluation/transforms.

### `peg.NodeIterator`

Non-recursive DFS iterator:

```zig
var it = try peg.NodeIterator.init(allocator, result.node);
defer it.deinit();
while (try it.next()) |node| {
    _ = node;
}
```

## Practical Snippets

Lint + rewrite:

```zig
const grammar = peg.compileWithOptions(src, .{
    .lint_mode = .warn,
    .left_recursion_mode = .rewrite,
});
```

Trace mode:

```zig
var trace_buf: std.ArrayListUnmanaged(u8) = .{};
defer trace_buf.deinit(allocator);

_ = try grammar.parseWithOptions(allocator, "start", input, .{
    .trace = true,
    .trace_buffer = &trace_buf,
});
```

Prefix parse:

```zig
const prefix = try grammar.parseWithOptions(allocator, "expr", "1+2 tail", .{
    .consume_mode = .partial,
});
_ = prefix;
```
