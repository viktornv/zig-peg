# ⚡ zig-peg — Comptime Parsing Expression Grammar Library

A complete PEG (Parsing Expression Grammar) library for Zig with **comptime grammar compilation**, **packrat memoization**, **tree walker**, and **detailed error reporting**.

Grammars are written as strings, compiled at comptime into optimized rule tables, and executed at runtime with zero dynamic grammar overhead.

## Installation / Integration

Add dependency:

```bash
zig fetch --save https://github.com/viktornv/zig-peg.git
```

In your `build.zig`:

```zig
const peg_dep = b.dependency("peg", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("peg", peg_dep.module("peg"));
```

In Zig source:

```zig
const peg = @import("peg");
```

Note: package name is currently `.name = .peg` in `build.zig.zon`, so import key is `peg`.

## Quick Start

```zig
const peg = @import("peg");

const calc = peg.compile(
    \\expr   <- _ws sum _ws
    \\sum    <- number (_ws '+' _ws number)*
    \\number <- [0-9]+
    \\@silent _ws    <- [ \t]*
);

test "parse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try calc.parse(arena.allocator(), "expr", "1 + 2 + 3");
    // result.node — parse tree
    // result.pos  — how far input was consumed
    // If you use a non-arena allocator, free with:
    // peg.freeNode(allocator, result.node);
}
```

## Usage Paths

### Core path (default)

Use this for most grammars:

- `peg.compile(...)`
- `grammar.parse(...)` for full input parsing
- `peg.printTree(...)` or `Walker` when you need tree processing

### Advanced path (opt-in)

Use when debugging/tuning grammar behavior:

- `grammar.parseWithOptions(..., .{ .consume_mode = .partial, ... })` for prefix parsing
- `grammar.parseDetailed(...)` / `parseDetailedWithOptions(...)` for structured diagnostics
- `trace` / `trace_buffer`, `memo_mode`, `stats` for runtime introspection
- `peg.lint(...)` and `peg.compileWithOptions(..., .{ .lint_mode = ... })` for compile-time checks
- `peg.treeJsonAlloc(...)` / `peg.writeTreeJson(...)` for external tooling

## Grammar Cheatsheet

```text
rule      <- expr
'text'    / "text"      literals
'text'i                  case-insensitive literal
[a-z] / [^a-z] / .       classes, negated classes, any-char
e1 e2                    sequence
e1 / e2                  ordered choice (left-first)
e* e+ e?                 repetition
e{n} e{n,m} e{n,}        range repetition
!e / &e                  lookaheads (no consume)
(e)                      grouping
name                     rule reference
~"..." / ~'...'          regex-like lexical token primitive
```

Annotations:

- `@silent rule <- ...` hide helper/trivia rule from AST
- `@squashed rule <- ...` flatten wrapper AST node
- `@memo_on rule <- ...` / `@memo_off rule <- ...` per-rule memo override

Whitespace model:

- Whitespace is explicit in grammar (`_ws`/`_sp` helper rules).
- Keep `_ws` where it is a real separator (keyword boundaries, list separators, newline/indent logic).

## Examples

Complete runnable grammars are in `examples/*`:

- Data formats: JSON, INI, CSV, TOML, YAML, XML, URI
- Languages: BASIC, SQL, Ruby, Smalltalk, Component Pascal, 1C subset
- Protocols/APIs: GraphQL (+ strict), HTTP (+ strict)
- Expression demo: Python-like expr with left-recursive rewrite and `@memo_off`

## API Reference

Core constructors:

- `peg.compile(grammar) -> Grammar`
- `peg.compileWithOptions(grammar, options) -> Grammar`
- `peg.lint(grammar) -> []const LintDiagnostic`

Core parse entrypoints:

- `Grammar.parse(allocator, start_rule, input) -> !ParseSuccess`
- `Grammar.parseWithOptions(allocator, start_rule, input, options) -> !ParseSuccess`
- `Grammar.parseDetailed(allocator, start_rule, input) -> union{ok, err}`
- `Grammar.parseDetailedWithOptions(allocator, start_rule, input, options) -> union{ok, err}`

Tree/utility API:

- `peg.printTree(node, indent) -> void`
- `peg.writeTreeJson(writer, node) -> void`
- `peg.treeJsonAlloc(allocator, node) -> []const u8`
- `peg.freeNode(allocator, node) -> void`
- `peg.Walker(Result, Context) -> type`
- `peg.NodeIterator`

Critical runtime contracts:

- Parsing is full-consume by default (`consume_mode = .full`).
- `.partial` is explicit via `parseWithOptions(..., .{ .consume_mode = .partial })`.
- Repeats stop on zero-width iterations (infinite-loop guard).
- Detailed errors are byte-based (`line/col`) and include truncation metadata.
- Memo cache key position is `u32`; inputs over 4 GiB are rejected deterministically.

Detailed API guide (options, diagnostics, trace/lint examples):

- `docs/api.md`


## Building & Testing

```bash
zig build test
```

Runs all tests across all examples.

Run individual example suites:

```bash
zig build test-json
zig build test-ini
zig build test-lisp
zig build test-uri
zig build test-md
zig build test-basic
zig build test-css
zig build test-1c
zig build test-csv
zig build test-toml
zig build test-ruby
zig build test-yaml
zig build test-xml
zig build test-graphql
zig build test-http
zig build test-graphql-strict
zig build test-http-strict
zig build test-component-pascal
zig build test-smalltalk
zig build test-sql
zig build test-python-expr
```

Run core-only suite:

```bash
zig build test-main
```

## Benchmarks

```bash
zig build bench
zig build bench -- --runs 50 --case json
zig build bench -- --format csv --output bench.csv
```

## Additional Notes

- Documentation hub: `docs/index.md`
- Learning path: `docs/getting-started.md`
- Expanded API reference: `docs/api.md`
- Current simplification model: `docs/simplification-notes.md`
- Regex-like vs PEG style audit: `docs/regex-peg-guidelines.md`
- Parsimonious comparison snapshot: `docs/parsimonious-gap.md`
- Contribution guide: `CONTRIBUTING.md`
- Support channels: `SUPPORT.md`
- Security reporting policy: `SECURITY.md`

## Memory Ownership

- `Node.tag` points to grammar-owned memory (comptime data), do not free it.
- `Node.text` points to slices of the original input buffer; keep the input alive while using the tree.
- `Node.children` is heap-allocated by the parser; free it with `peg.freeNode(...)` unless you parse with an arena.

## License

MIT