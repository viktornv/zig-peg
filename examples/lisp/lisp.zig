const std = @import("std");
const peg = @import("peg");

const lisp = peg.compile(
    \\program  <- _ws expr (_ws expr)* _ws
    \\expr     <- _ws (list / quote / atom) _ws
    \\list     <- '(' _ws (expr (_ws expr)*)? _ws ')'
    \\quote    <- '\'' _ws expr
    \\atom     <- number / string / symbol
    \\number  <- _sign? _digit+
    \\string  <- '"' _strch* '"'
    \\symbol  <- _symstart _symrest*
    \\@silent _sign    <- '-'
    \\@silent _digit   <- [0-9]
    \\@silent _strch   <- '\\' . / [^"\\]
    \\@silent _symstart <- [a-zA-Z_+\-*/=<>!?]
    \\@silent _symrest  <- [a-zA-Z0-9_+\-*/=<>!?]
    \\@silent _ws      <- [ \t\n\r]*
);

const Eval = peg.Walker(i64, void);

fn evalProgram(_: peg.Node, children: []const i64, _: void) anyerror!i64 {
    if (children.len == 0) return 0;
    return children[children.len - 1];
}

fn evalExpr(_: peg.Node, children: []const i64, _: void) anyerror!i64 {
    if (children.len > 0) return children[0];
    return 0;
}

fn evalList(node: peg.Node, children: []const i64, _: void) anyerror!i64 {
    if (node.children.len == 0) return 0;

    const op_text = findSymbol(node.children[0]);

    if (op_text.len == 0) {
        if (children.len > 0) return children[0];
        return 0;
    }

    if (std.mem.eql(u8, op_text, "+")) {
        var sum: i64 = 0;
        for (children[1..]) |v| sum += v;
        return sum;
    }
    if (std.mem.eql(u8, op_text, "-")) {
        if (children.len < 2) return 0;
        var result = children[1];
        for (children[2..]) |v| result -= v;
        return result;
    }
    if (std.mem.eql(u8, op_text, "*")) {
        var product: i64 = 1;
        for (children[1..]) |v| product *= v;
        return product;
    }
    if (std.mem.eql(u8, op_text, "/")) {
        if (children.len < 2) return 0;
        var result = children[1];
        for (children[2..]) |v| {
            if (v == 0) return error.DivisionByZero;
            result = @divTrunc(result, v);
        }
        return result;
    }

    if (children.len > 0) return children[0];
    return 0;
}

fn findSymbol(node: peg.Node) []const u8 {
    if (std.mem.eql(u8, node.tag, "symbol")) return node.text;
    for (node.children) |child| {
        const s = findSymbol(child);
        if (s.len > 0) return s;
    }
    return "";
}

fn evalQuote(_: peg.Node, _: []const i64, _: void) anyerror!i64 {
    return 0;
}

fn evalAtom(_: peg.Node, children: []const i64, _: void) anyerror!i64 {
    if (children.len > 0) return children[0];
    return 0;
}

fn evalNumber(node: peg.Node, _: []const i64, _: void) anyerror!i64 {
    return std.fmt.parseInt(i64, node.text, 10) catch 0;
}

fn evalSymbol(_: peg.Node, _: []const i64, _: void) anyerror!i64 {
    return 0;
}

fn evalString(_: peg.Node, _: []const i64, _: void) anyerror!i64 {
    return 0;
}

fn makeEvaluator(allocator: std.mem.Allocator) Eval {
    return Eval{
        .actions = &.{
            .{ .tag = "program", .func = evalProgram },
            .{ .tag = "expr", .func = evalExpr },
            .{ .tag = "list", .func = evalList },
            .{ .tag = "quote", .func = evalQuote },
            .{ .tag = "atom", .func = evalAtom },
            .{ .tag = "number", .func = evalNumber },
            .{ .tag = "symbol", .func = evalSymbol },
            .{ .tag = "string", .func = evalString },
        },
        .allocator = allocator,
    };
}

fn expectEval(input: []const u8, expected: i64) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try lisp.parse(arena.allocator(), "program", input);
    const evaluator = makeEvaluator(arena.allocator());
    const value = try evaluator.walk(result.node, {});
    std.debug.print("  {s} => {}\n", .{ input, value });
    try std.testing.expectEqual(expected, value);
}

fn expectParse(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try lisp.parse(arena.allocator(), "program", input);
    std.debug.print("  OK: {s}\n", .{input});
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (lisp.parse(arena.allocator(), "program", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
        std.debug.print("  PARTIAL: \"{s}\"\n", .{input});
    } else |_| {
        std.debug.print("  REJECTED: \"{s}\"\n", .{input});
    }
}

test "atoms" {
    std.debug.print("\n-- lisp: atoms --\n", .{});
    try expectParse("42");
    try expectParse("-7");
    try expectParse("hello");
    try expectParse("x");
    try expectParse("+");
    try expectParse("-");
    try expectParse("*");
    try expectParse("nil?");
    try expectParse("set!");
}

test "strings" {
    std.debug.print("\n-- lisp: strings --\n", .{});
    try expectParse("\"hello\"");
    try expectParse("\"hello world\"");
    try expectParse("\"escaped\\\"quote\"");
    try expectParse("\"line\\nbreak\"");
}

test "simple lists" {
    std.debug.print("\n-- lisp: simple lists --\n", .{});
    try expectParse("()");
    try expectParse("(+ 1 2)");
    try expectParse("(* 3 4)");
    try expectParse("(- 10 3)");
    try expectParse("(/ 10 2)");
    try expectParse("(list 1 2 3)");
}

test "nested lists" {
    std.debug.print("\n-- lisp: nested --\n", .{});
    try expectParse("(+ 1 (+ 2 3))");
    try expectParse("(* (+ 1 2) (- 5 3))");
    try expectParse("((()))");
    try expectParse("(a (b (c (d))))");
    try expectParse("(define (square x) (* x x))");
}

test "quotes" {
    std.debug.print("\n-- lisp: quotes --\n", .{});
    try expectParse("'x");
    try expectParse("'(1 2 3)");
    try expectParse("'(+ 1 2)");
    try expectParse("''x");
}

test "multiple exprs" {
    std.debug.print("\n-- lisp: multiple --\n", .{});
    try expectParse("1 2 3");
    try expectParse("(+ 1 2) (* 3 4)");
    try expectParse("x y z");
}

test "string in list" {
    std.debug.print("\n-- lisp: string in list --\n", .{});
    try expectParse("(print \"hello\")");
    try expectParse("(concat \"a\" \"b\")");
}

test "whitespace" {
    std.debug.print("\n-- lisp: whitespace --\n", .{});
    try expectParse("  42  ");
    try expectParse("  ( +   1    2 )  ");
    try expectParse("(\n+ 1\n  2\n)");
    try expectParse("(+\t1\t2)");
}

test "tree debug" {
    std.debug.print("\n-- lisp: tree debug --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try lisp.parse(arena.allocator(), "program", "(+ 1 2)");
    peg.printTree(result.node, 2);
}

test "eval arithmetic" {
    std.debug.print("\n-- lisp: eval --\n", .{});
    try expectEval("(+ 1 2)", 3);
    try expectEval("(+ 1 2 3 4 5)", 15);
    try expectEval("(- 10 3)", 7);
    try expectEval("(* 2 3 4)", 24);
    try expectEval("(/ 100 10)", 10);
}

test "eval nested" {
    std.debug.print("\n-- lisp: eval nested --\n", .{});
    try expectEval("(+ 1 (+ 2 3))", 6);
    try expectEval("(* (+ 1 2) (+ 3 4))", 21);
    try expectEval("(- (+ 10 5) (* 2 3))", 9);
    try expectEval("(/ (* 4 5) (+ 1 1))", 10);
}

test "eval number" {
    std.debug.print("\n-- lisp: eval number --\n", .{});
    try expectEval("42", 42);
    try expectEval("-7", -7);
    try expectEval("0", 0);
}

test "eval last expr" {
    std.debug.print("\n-- lisp: eval last --\n", .{});
    try expectEval("1 2 3", 3);
    try expectEval("(+ 1 2) (* 3 4)", 12);
}

test "invalid" {
    std.debug.print("\n-- lisp: invalid --\n", .{});
    try expectFail("");
    try expectFail("(");
    try expectFail(")");
    try expectFail("(+ 1");
}

test "deep nesting" {
    std.debug.print("\n-- lisp: deep nesting --\n", .{});
    try expectParse("(+ 1 (+ 2 (+ 3 (+ 4 5))))");
    try expectEval("(+ 1 (+ 2 (+ 3 (+ 4 5))))", 15);
}