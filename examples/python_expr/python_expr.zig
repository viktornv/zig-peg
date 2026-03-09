const std = @import("std");
const peg = @import("peg");

const python_expr = peg.compileWithOptions(
    \\start          <- _ws expr _ws
    \\expr           <- comparison
    \\comparison     <- additive (_ws cmp_op _ws additive)?
    \\cmp_op         <- '==' / '!=' / '<=' / '>=' / '<' / '>'
    \\additive       <- additive _ws add_op _ws multiplicative / multiplicative
    \\add_op         <- '+' / '-'
    \\multiplicative <- multiplicative _ws mul_op _ws unary / unary
    \\mul_op         <- '*' / '/' / '%'
    \\unary          <- _ws (('+' / '-') _ws unary / primary) _ws
    \\primary        <- number / ident / '(' _ws expr _ws ')'
    \\@memo_off number <- _digits ('.' _digits)?
    \\ident          <- _ident_start _ident_rest*
    \\@silent _ident_start   <- [a-zA-Z_]
    \\@silent _ident_rest    <- [a-zA-Z0-9_]
    \\@silent _digits        <- [0-9]+
    \\@silent _ws            <- [ \t\n\r]*
,
    .{ .left_recursion_mode = .rewrite },
);

const python_expr_default_memo = peg.compileWithOptions(
    \\start          <- _ws expr _ws
    \\expr           <- comparison
    \\comparison     <- additive (_ws cmp_op _ws additive)?
    \\cmp_op         <- '==' / '!=' / '<=' / '>=' / '<' / '>'
    \\additive       <- additive _ws add_op _ws multiplicative / multiplicative
    \\add_op         <- '+' / '-'
    \\multiplicative <- multiplicative _ws mul_op _ws unary / unary
    \\mul_op         <- '*' / '/' / '%'
    \\unary          <- _ws (('+' / '-') _ws unary / primary) _ws
    \\primary        <- number / ident / '(' _ws expr _ws ')'
    \\number         <- _digits ('.' _digits)?
    \\ident          <- _ident_start _ident_rest*
    \\@silent _ident_start   <- [a-zA-Z_]
    \\@silent _ident_rest    <- [a-zA-Z0-9_]
    \\@silent _digits        <- [0-9]+
    \\@silent _ws            <- [ \t\n\r]*
,
    .{ .left_recursion_mode = .rewrite },
);

fn expectParse(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try python_expr.parse(arena.allocator(), "start", input);
    std.debug.print("  OK: {s}\n", .{input});
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (python_expr.parse(arena.allocator(), "start", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
        std.debug.print("  PARTIAL (ok), pos={}/{}\n", .{ r.pos, input.len });
    } else |_| {
        std.debug.print("  REJECTED (ok)\n", .{});
    }
}

test "python expr precedence and grouping" {
    std.debug.print("\n-- python-expr: precedence --\n", .{});
    const cases = [_][]const u8{
        "1 + 2 * 3",
        "(1 + 2) * 3",
        "a + b * c - d",
        "x % 2 + 10 / 5",
        "-x + 5",
        "+(+1)",
    };
    for (cases) |input| try expectParse(input);
}

test "python expr comparisons" {
    std.debug.print("\n-- python-expr: comparisons --\n", .{});
    const cases = [_][]const u8{
        "x == 1",
        "x != y",
        "total >= limit",
        "(a + b) < c * 10",
        "count <= 100",
    };
    for (cases) |input| try expectParse(input);
}

test "python expr invalid cases" {
    std.debug.print("\n-- python-expr: invalid --\n", .{});
    try expectFail("1 +");
    try expectFail("(1 + 2");
    try expectFail("x ==");
}

test "left recursive form works via rewrite mode" {
    std.debug.print("\n-- python-expr: left recursion rewrite --\n", .{});
    try expectParse("a + b + c + d");
    try expectParse("2 * 3 * 4");
    try expectParse("1 + 2 * 3 + 4");
}

test "@memo_off reduces memo traffic for lexical number rule" {
    std.debug.print("\n-- python-expr: memo override --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const input = "123 + 456 * (78 - 9) + value1";

    var stats_default: peg.ParseStats = .{};
    _ = try python_expr_default_memo.parseWithOptions(
        arena.allocator(),
        "start",
        input,
        .{ .memo_mode = .on, .stats = &stats_default },
    );

    var stats_memo_off: peg.ParseStats = .{};
    _ = try python_expr.parseWithOptions(
        arena.allocator(),
        "start",
        input,
        .{ .memo_mode = .on, .stats = &stats_memo_off },
    );

    try std.testing.expect(stats_memo_off.memo_puts < stats_default.memo_puts);
}
