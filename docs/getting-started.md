# Getting Started

This guide provides a practical path from a minimal grammar to diagnostics and runtime tuning.

## Step 1: Minimal parse

Start with `compile` + `parse`:

```zig
const peg = @import("peg");

const grammar = peg.compile(
    \\expr <- _ws number _ws
    \\number <- [0-9]+
    \\@silent _ws <- [ \t]*
);

const result = try grammar.parse(allocator, "expr", " 42 ");
_ = result.node;
_ = result.pos;
```

`result.pos` is the consumed byte boundary.

## Step 2: Explicit whitespace and tree shape

Whitespace is modeled in grammar rules. Use `@silent` for helper/trivia rules and `@squashed` for wrapper rules:

```zig
const grammar = peg.compile(
    \\expr <- _ws @squashed sum _ws
    \\sum <- number (_ws '+' _ws number)*
    \\number <- [0-9]+
    \\@silent _ws <- [ \t]*
);
```

## Step 3: Parse modes

- Default parse is full-consume.
- Use `.partial` when you intentionally accept prefixes.

```zig
const prefix = try grammar.parseWithOptions(allocator, "expr", "1+2 tail", .{
    .consume_mode = .partial,
});
_ = prefix.pos;
```

## Step 4: Diagnostics

Use `parseDetailed` when you need structured parse errors:

```zig
const detailed = grammar.parseDetailed(allocator, "expr", "1 + + 2");
switch (detailed) {
    .ok => |_| {},
    .err => |e| {
        _ = e.class;
        _ = e.line;
        _ = e.col;
        _ = e.expected;
        _ = e.expected_items;
        _ = e.expected_truncated;
    },
}
```

`line/col` are byte-based positions.

## Step 5: Compile-time checks

Run lint diagnostics directly or compile with policy options:

```zig
const diags = peg.lint(src);
_ = diags;

const checked = peg.compileWithOptions(src, .{
    .lint_mode = .warn,
    .left_recursion_mode = .rewrite,
});
_ = checked;
```

## Step 6: Runtime tuning and debug

Tune parser behavior with runtime options and per-rule annotations:

```zig
var stats: peg.ParseStats = .{};
var trace_buf: std.ArrayListUnmanaged(u8) = .{};
defer trace_buf.deinit(allocator);

_ = try grammar.parseWithOptions(allocator, "expr", "1+2+3", .{
    .memo_mode = .on,
    .stats = &stats,
    .trace = true,
    .trace_buffer = &trace_buf,
    .max_recursion_depth = 4096,
});
```

Per-rule memo override is declared in grammar: `@memo_on rule <- ...` / `@memo_off rule <- ...`.

## Step 7: Next references

- Expanded API reference: `docs/api.md`
- Core contracts: `docs/simplification-notes.md`
- Regex-like style rules: `docs/regex-peg-guidelines.md`
- Examples: `examples/*`
