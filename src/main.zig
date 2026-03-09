const std = @import("std");
const peg = @import("peg.zig");

const calc = peg.compile(
    \\expr    <- _ws sum _ws
    \\sum     <- product (_ws op_add _ws product)*
    \\product <- atom (_ws op_mul _ws atom)*
    \\atom    <- number / '(' _ws sum _ws ')'
    \\number  <- [0-9]+
    \\op_add  <- '+' / '-'
    \\op_mul  <- '*' / '/'
    \\@silent _ws     <- [ \t]*
);

const Eval = peg.Walker(i64, void);

fn evalExpr(_: peg.Node, children: []const i64, _: void) anyerror!i64 {
    return children[0];
}

fn evalSum(node: peg.Node, children: []const i64, _: void) anyerror!i64 {
    if (children.len == 0) return 0;
    var result = children[0];
    var i: usize = 1;
    while (i + 1 < children.len) : (i += 2) {
        const op = node.children[i].text[0];
        const val = children[i + 1];
        if (op == '+') result += val else result -= val;
    }
    return result;
}

fn evalProduct(node: peg.Node, children: []const i64, _: void) anyerror!i64 {
    if (children.len == 0) return 0;
    var result = children[0];
    var i: usize = 1;
    while (i + 1 < children.len) : (i += 2) {
        const op = node.children[i].text[0];
        const val = children[i + 1];
        if (op == '*') result *= val else {
            if (val == 0) return error.DivisionByZero;
            result = @divTrunc(result, val);
        }
    }
    return result;
}

fn evalAtom(_: peg.Node, children: []const i64, _: void) anyerror!i64 {
    if (children.len > 0) return children[0];
    return 0;
}

fn evalNumber(node: peg.Node, _: []const i64, _: void) anyerror!i64 {
    return std.fmt.parseInt(i64, node.text, 10) catch 0;
}

fn evalOp(_: peg.Node, _: []const i64, _: void) anyerror!i64 {
    return 0;
}

fn makeEvaluator(allocator: std.mem.Allocator) Eval {
    return Eval{
        .actions = &.{
            .{ .tag = "expr", .func = evalExpr },
            .{ .tag = "sum", .func = evalSum },
            .{ .tag = "product", .func = evalProduct },
            .{ .tag = "atom", .func = evalAtom },
            .{ .tag = "number", .func = evalNumber },
            .{ .tag = "op_add", .func = evalOp },
            .{ .tag = "op_mul", .func = evalOp },
        },
        .allocator = allocator,
    };
}

fn expectEval(input: []const u8, expected: i64) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try calc.parse(arena.allocator(), "expr", input);
    const evaluator = makeEvaluator(arena.allocator());
    const value = try evaluator.walk(result.node, {});
    std.debug.print("  {s} = {}\n", .{ input, value });
    try std.testing.expectEqual(expected, value);
}

fn expectDivZero(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try calc.parse(arena.allocator(), "expr", input);
    const evaluator = makeEvaluator(arena.allocator());
    if (evaluator.walk(result.node, {})) |_| {
        return error.ShouldHaveFailed;
    } else |err| {
        if (err == error.DivisionByZero) {
            std.debug.print("  \"{s}\" => DivisionByZero (ok)\n", .{input});
            return;
        }
        return err;
    }
}

fn expectError(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (calc.parse(arena.allocator(), "expr", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
        std.debug.print("  \"{s}\" => partial parse (ok)\n", .{input});
    } else |_| {
        std.debug.print("  \"{s}\" => error (ok)\n", .{input});
    }
}

test "single numbers" {
    std.debug.print("\n", .{});
    try expectEval("0", 0);
    try expectEval("1", 1);
    try expectEval("9", 9);
    try expectEval("42", 42);
    try expectEval("100", 100);
    try expectEval("999999999", 999999999);
}

test "basic addition" {
    std.debug.print("\n", .{});
    try expectEval("2+3", 5);
    try expectEval("0+0", 0);
    try expectEval("0+5", 5);
    try expectEval("100+200", 300);
}

test "basic subtraction" {
    std.debug.print("\n", .{});
    try expectEval("10-3", 7);
    try expectEval("3-10", -7);
    try expectEval("0-0", 0);
    try expectEval("5-5", 0);
    try expectEval("100-1", 99);
}

test "basic multiplication" {
    std.debug.print("\n", .{});
    try expectEval("2*3", 6);
    try expectEval("0*100", 0);
    try expectEval("1*42", 42);
    try expectEval("7*7", 49);
}

test "basic division" {
    std.debug.print("\n", .{});
    try expectEval("10/3", 3);
    try expectEval("10/2", 5);
    try expectEval("0/5", 0);
    try expectEval("7/1", 7);
    try expectEval("100/10", 10);
}

test "operator priority" {
    std.debug.print("\n", .{});
    try expectEval("2+3*4", 14);
    try expectEval("10-2*3", 4);
    try expectEval("1+2*3+4", 11);
    try expectEval("2*3+4*5", 26);
    try expectEval("10-2+3*4", 20);
    try expectEval("1+2+3*4+5", 20);
}

test "parentheses" {
    std.debug.print("\n", .{});
    try expectEval("(42)", 42);
    try expectEval("(2+3)*4", 20);
    try expectEval("2*(3+4)", 14);
    try expectEval("(5-3)+2", 4);
    try expectEval("((1+2))", 3);
    try expectEval("(1+2)*(3+4)", 21);
    try expectEval("((((5))))", 5);
    try expectEval("(1+(2+(3+(4+5))))", 15);
}

test "addition chains" {
    std.debug.print("\n", .{});
    try expectEval("1+2+3+4+5", 15);
    try expectEval("1+1+1+1+1+1+1+1+1+1", 10);
}

test "subtraction chains" {
    std.debug.print("\n", .{});
    try expectEval("10-1-2-3", 4);
    try expectEval("100-50-25-10", 15);
    try expectEval("1-2-3", -4);
}

test "mixed add/sub chains" {
    std.debug.print("\n", .{});
    try expectEval("1+2-3+4-5", -1);
    try expectEval("10-5+3-2+1", 7);
    try expectEval("100+200-150+50", 200);
}

test "multiplication chains" {
    std.debug.print("\n", .{});
    try expectEval("2*3*4", 24);
    try expectEval("1*2*3*4*5", 120);
}

test "division chains" {
    std.debug.print("\n", .{});
    try expectEval("100/10/2", 5);
    try expectEval("1000/10/10/10", 1);
}

test "mixed mul/div chains" {
    std.debug.print("\n", .{});
    try expectEval("100/5/2*3", 30);
    try expectEval("2*3/2*4", 12);
    try expectEval("100/10*2/5", 4);
}

test "complex expressions" {
    std.debug.print("\n", .{});
    try expectEval("(1+2)-(3+(4-5))", 1);
    try expectEval("(10-5)*(2+3)", 25);
    try expectEval("((2+3)*4-10)/2", 5);
    try expectEval("(1+2)*(3+4)*(5+6)", 231);
    try expectEval("100/(2+3)+10", 30);
    try expectEval("(1+1)*(2+2)*(3+3)", 48);
}

test "whitespace handling" {
    std.debug.print("\n", .{});
    try expectEval("2 + 3 * 4", 14);
    try expectEval("( 2 + 3 ) * 4", 20);
    try expectEval("  1  +  2  ", 3);
    try expectEval("   42   ", 42);
    try expectEval("\t1\t+\t2\t", 3);
    try expectEval("  (  1  +  2  )  *  3  ", 9);
}

test "division by zero" {
    std.debug.print("\n", .{});
    try expectDivZero("10/0");
    try expectDivZero("1/(1-1)");
    try expectDivZero("(5+5)/(3-3)");
}

test "invalid expressions" {
    std.debug.print("\n", .{});
    try expectError("");
    try expectError("abc");
    try expectError("+");
    try expectError("*3");
    try expectError("()");
    try expectError("(+)");
}

test "partial parse (trailing garbage)" {
    std.debug.print("\n", .{});
    try expectError("3+");
    try expectError("3 4");
    try expectError("3++4");
    try expectError("3**4");
    try expectError("(3+4");
    try expectError("3+4)");
}

test "edge cases" {
    std.debug.print("\n", .{});
    try expectEval("0+0", 0);
    try expectEval("0*0", 0);
    try expectEval("1*1*1*1", 1);
    try expectEval("0+1+0+1", 2);
}

// --- New feature tests ---

const kw_test = peg.compile(
    \\stmt   <- select / insert
    \\select <- 'SELECT'i _ws _ident _ws 'FROM'i _ws _ident
    \\insert <- 'INSERT'i _ws 'INTO'i _ws _ident
    \\@silent _ident <- [a-zA-Z_]+
    \\@silent _ws    <- [ \t]+
);

test "case insensitive literals" {
    std.debug.print("\n-- case insensitive --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const tests = [_][]const u8{
        "SELECT name FROM users",
        "select name from users",
        "Select Name From Users",
        "sElEcT name fRoM users",
        "INSERT INTO users",
        "insert into users",
    };

    for (tests) |input| {
        const result = try kw_test.parse(arena.allocator(), "stmt", input);
        try std.testing.expect(result.pos == input.len);
        std.debug.print("  OK: {s}\n", .{input});
    }
}

const dq_test = peg.compile(
    \\greeting <- "hello" _ws "world"
    \\@silent _ws      <- [ ]+
);

test "double quote literals" {
    std.debug.print("\n-- double quote literals --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try dq_test.parse(arena.allocator(), "greeting", "hello world");
    try std.testing.expect(result.pos == 11);
    std.debug.print("  OK: hello world\n", .{});
}

const repeat_test = peg.compile(
    \\ipv4   <- octet '.' octet '.' octet '.' octet
    \\octet  <- _digit{1,3}
    \\hex4   <- _hex{4}
    \\hex24  <- _hex{2,4}
    \\@silent _digit <- [0-9]
    \\@silent _hex   <- [0-9a-fA-F]
);

test "range repeat" {
    std.debug.print("\n-- range repeat --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // IPv4
    const ipv4_tests = [_][]const u8{
        "192.168.1.1",
        "0.0.0.0",
        "255.255.255.255",
        "10.0.0.1",
    };
    for (ipv4_tests) |input| {
        const result = try repeat_test.parse(arena.allocator(), "ipv4", input);
        try std.testing.expect(result.pos == input.len);
        std.debug.print("  OK ipv4: {s}\n", .{input});
    }

    // Exact {4}
    const hex4_ok = [_][]const u8{ "abcd", "1234", "FFFF", "a0B1" };
    for (hex4_ok) |input| {
        const result = try repeat_test.parse(arena.allocator(), "hex4", input);
        try std.testing.expect(result.pos == 4);
        std.debug.print("  OK hex4: {s}\n", .{input});
    }

    // {2,4}
    const hex24_tests = [_]struct { input: []const u8, expect_len: usize }{
        .{ .input = "ab", .expect_len = 2 },
        .{ .input = "abc", .expect_len = 3 },
        .{ .input = "abcd", .expect_len = 4 },
        .{ .input = "abcde", .expect_len = 4 },
    };
    for (hex24_tests) |t| {
        const result = try repeat_test.parseWithOptions(
            arena.allocator(),
            "hex24",
            t.input,
            .{ .consume_mode = .partial },
        );
        try std.testing.expectEqual(t.expect_len, result.pos);
        std.debug.print("  OK hex{{2,4}}: {s} => {}\n", .{ t.input, result.pos });
    }

    // Too few
    if (repeat_test.parse(arena.allocator(), "hex24", "a")) |_| {
        return error.ShouldHaveFailed;
    } else |_| {
        std.debug.print("  OK hex{{2,4}}: 'a' rejected\n", .{});
    }
}

test "detailed errors" {
    std.debug.print("\n-- detailed errors --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = calc.parseDetailed(arena.allocator(), "expr", "3 + + 5");
    switch (result) {
        .ok => |_| return error.ShouldHaveFailed,
        .err => |e| {
            std.debug.print("  Error at line {}:{}\n", .{ e.line, e.col });
            std.debug.print("  Expected: {s}\n", .{e.expected});
            std.debug.print("  Context: \"{s}\"\n", .{e.context});
            try std.testing.expect(e.line == 1);
            try std.testing.expect(e.pos > 0);
            try std.testing.expect(e.expected_count >= 1);
        },
    }

    // Completely invalid
    const result2 = calc.parseDetailed(arena.allocator(), "expr", "abc");
    switch (result2) {
        .ok => return error.ShouldHaveFailed,
        .err => |e| {
            std.debug.print("  'abc' error at line {}:{}: expected {s}\n", .{ e.line, e.col, e.expected });
            try std.testing.expect(e.line == 1);
        },
    }

    // Multi-line
    const result3 = calc.parseDetailed(arena.allocator(), "expr", "(\n1+\n)");
    switch (result3) {
        .ok => return error.ShouldHaveFailed,
        .err => |e| {
            std.debug.print("  Multi-line error at line {}:{}: expected {s}\n", .{ e.line, e.col, e.expected });
            std.debug.print("  Context: \"{s}\"\n", .{e.context});
            try std.testing.expect(e.context.len > 0);
        },
    }
}

const multi_expected_test = peg.compile(
    \\start <- 'foo' / 'for' / 'if'
);

test "parseDetailed collects multi-expected alternatives at farthest pos" {
    const result = multi_expected_test.parseDetailed(std.testing.allocator, "start", "f");
    switch (result) {
        .ok => return error.ShouldHaveFailed,
        .err => |e| {
            try std.testing.expectEqual(@as(usize, 0), e.pos);
            try std.testing.expect(e.expected_count >= 2);
            var has_foo = false;
            var has_for = false;
            for (0..e.expected_count) |i| {
                if (std.mem.eql(u8, e.expected_items[i], "foo")) has_foo = true;
                if (std.mem.eql(u8, e.expected_items[i], "for")) has_for = true;
            }
            try std.testing.expect(has_foo);
            try std.testing.expect(has_for);
        },
    }
}

const snippet_test = peg.compile(
    \\start <- 'A' '\n' 'B' '\n' 'C'
);

test "parseDetailed provides neighboring context lines for multiline failures" {
    const result = snippet_test.parseDetailed(std.testing.allocator, "start", "A\nX\nC");
    switch (result) {
        .ok => return error.ShouldHaveFailed,
        .err => |e| {
            try std.testing.expectEqual(@as(usize, 2), e.line);
            try std.testing.expectEqualStrings("A", e.context_prev);
            try std.testing.expectEqualStrings("X", e.context);
            try std.testing.expectEqualStrings("C", e.context_next);
        },
    }
}

const neg_test = peg.compile(
    \\line    <- [^\n]+ '\n'
    \\notab   <- [^ab]+
);

test "negated char class" {
    std.debug.print("\n-- negated char class --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try neg_test.parse(arena.allocator(), "line", "hello world\n");
    try std.testing.expect(result.pos == 12);
    std.debug.print("  OK: line matched {}\n", .{result.pos});

    const result2 = try neg_test.parse(arena.allocator(), "notab", "xyz123");
    try std.testing.expect(result2.pos == 6);
    std.debug.print("  OK: notab matched {}\n", .{result2.pos});

    // Stops at 'a'
    const result3 = try neg_test.parseWithOptions(
        arena.allocator(),
        "notab",
        "xyza",
        .{ .consume_mode = .partial },
    );
    try std.testing.expect(result3.pos == 3);
    std.debug.print("  OK: notab stops at 'a', pos={}\n", .{result3.pos});

    // Starts with excluded char
    if (neg_test.parse(arena.allocator(), "notab", "abc")) |_| {
        return error.ShouldHaveFailed;
    } else |_| {
        std.debug.print("  OK: 'abc' rejected by notab\n", .{});
    }
}

test "freeNode releases parse tree memory" {
    const input = "1 + 2 * 3";
    const result = try calc.parse(std.testing.allocator, "expr", input);
    defer peg.freeNode(std.testing.allocator, result.node);
    try std.testing.expectEqual(input.len, result.pos);
}

test "parse failure does not leak temporary allocations" {
    if (calc.parse(std.testing.allocator, "expr", "+")) |_| {
        return error.ShouldHaveFailed;
    } else |err| {
        try std.testing.expectEqual(error.ParseFailed, err);
    }
}

test "parseDetailed distinguishes out of memory" {
    var tiny: [1]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&tiny);
    const detailed = calc.parseDetailed(fba.allocator(), "expr", "12345+67890+42");
    switch (detailed) {
        .ok => return error.ShouldHaveFailed,
        .err => |e| try std.testing.expectEqualStrings("out of memory", e.expected),
    }
}

test "parseDetailed OOM reports best-effort position/context" {
    const input = "1 + 2\n+ 3\n+ 4";
    var found_oom = false;

    var cap: usize = 1;
    while (cap <= 256) : (cap += 1) {
        const buf = try std.testing.allocator.alloc(u8, cap);
        defer std.testing.allocator.free(buf);

        var fba = std.heap.FixedBufferAllocator.init(buf);
        const detailed = calc.parseDetailed(fba.allocator(), "expr", input);
        switch (detailed) {
            .ok => {},
            .err => |e| {
                if (e.class == .oom) {
                    try std.testing.expectEqualStrings("out of memory", e.expected);
                    try std.testing.expect(e.line >= 1);
                    try std.testing.expect(e.col >= 1);
                    if (e.pos > 0) {
                        try std.testing.expect(e.context.len > 0 or e.context_prev.len > 0 or e.context_next.len > 0);
                    }
                    found_oom = true;
                    break;
                }
            },
        }
    }

    try std.testing.expect(found_oom);
}

const many_expected = peg.compile(
    \\start <- 'a' / 'b' / 'c' / 'd' / 'e' / 'f' / 'g'
);

test "parseDetailed reports expected truncation marker" {
    const detailed = many_expected.parseDetailed(std.testing.allocator, "start", "z");
    switch (detailed) {
        .ok => return error.ShouldHaveFailed,
        .err => |e| {
            try std.testing.expect(e.expected_count == 5);
            try std.testing.expect(e.expected_truncated);
            const formatted = try e.formatAlloc(std.testing.allocator);
            defer std.testing.allocator.free(formatted);
            try std.testing.expect(std.mem.indexOf(u8, formatted, "...") != null);
        },
    }
}

test "parseDetailed respects recursion depth limit" {
    var buf = try std.ArrayList(u8).initCapacity(std.testing.allocator, 0);
    defer buf.deinit(std.testing.allocator);
    try buf.appendNTimes(std.testing.allocator, '(', 96);
    try buf.append(std.testing.allocator, '1');
    try buf.appendNTimes(std.testing.allocator, ')', 96);
    const input = buf.items;

    const detailed = calc.parseDetailedWithOptions(std.testing.allocator, "expr", input, .{
        .max_recursion_depth = 32,
    });
    switch (detailed) {
        .ok => |ok| {
            peg.freeNode(std.testing.allocator, ok.node);
            return error.ShouldHaveFailed;
        },
        .err => |e| {
            try std.testing.expectEqual(peg.ParseErrorClass.syntax, e.class);
            try std.testing.expectEqualStrings("recursion depth limit", e.expected);
        },
    }
}

test "max_recursion_depth = 0 disables recursion guard" {
    var buf = try std.ArrayList(u8).initCapacity(std.testing.allocator, 0);
    defer buf.deinit(std.testing.allocator);
    try buf.appendNTimes(std.testing.allocator, '(', 96);
    try buf.append(std.testing.allocator, '1');
    try buf.appendNTimes(std.testing.allocator, ')', 96);

    const detailed = calc.parseDetailedWithOptions(std.testing.allocator, "expr", buf.items, .{
        .max_recursion_depth = 0,
    });
    switch (detailed) {
        .ok => |ok| {
            peg.freeNode(std.testing.allocator, ok.node);
        },
        .err => |e| {
            // Any syntax/OOM is acceptable in constrained env, but recursion guard must not trigger.
            try std.testing.expect(!std.mem.eql(u8, e.expected, "recursion depth limit"));
        },
    }
}

test "parseAll rejects trailing garbage" {
    if (calc.parse(std.testing.allocator, "expr", "1 + 2 xyz")) |_| {
        return error.ShouldHaveFailed;
    } else |err| {
        try std.testing.expectEqual(error.ParseFailed, err);
    }
}

test "parseWithOptions supports disabling memoization" {
    const res = try calc.parseWithOptions(
        std.testing.allocator,
        "expr",
        "12 + 34 * 2",
        .{ .memo_mode = .off },
    );
    defer peg.freeNode(std.testing.allocator, res.node);
    try std.testing.expectEqual(@as(usize, 11), res.pos);
}

test "parse telemetry collects memo stats" {
    var stats_on: peg.ParseStats = .{};
    const res_on = try calc.parseWithOptions(
        std.testing.allocator,
        "expr",
        "1 + 2 + 3 + 4",
        .{ .memo_mode = .on, .stats = &stats_on },
    );
    defer peg.freeNode(std.testing.allocator, res_on.node);
    try std.testing.expect(stats_on.memo_entries > 0);
    try std.testing.expect(stats_on.memo_puts > 0);

    var stats_off: peg.ParseStats = .{};
    const res_off = try calc.parseWithOptions(
        std.testing.allocator,
        "expr",
        "1 + 2 + 3 + 4",
        .{ .memo_mode = .off, .stats = &stats_off },
    );
    defer peg.freeNode(std.testing.allocator, res_off.node);
    try std.testing.expectEqual(@as(usize, 0), stats_off.memo_entries);
    try std.testing.expectEqual(@as(usize, 0), stats_off.memo_puts);
}

const boundary_test = peg.compile(
    \\start <- text / symbol
    \\text <- 'hello <- world'
    \\symbol <- [<\-]+
);

test "rule-boundary hardening with arrow-like tokens" {
    const r1 = try boundary_test.parse(std.testing.allocator, "start", "hello <- world");
    defer peg.freeNode(std.testing.allocator, r1.node);
    const r2 = try boundary_test.parse(std.testing.allocator, "start", "<<<---");
    defer peg.freeNode(std.testing.allocator, r2.node);
}

test "node iterator traverses without recursion" {
    const res = try calc.parse(std.testing.allocator, "expr", "2+3*4");
    defer peg.freeNode(std.testing.allocator, res.node);

    var it = try peg.NodeIterator.init(std.testing.allocator, res.node);
    defer it.deinit();

    var seen: usize = 0;
    while (try it.next()) |_| {
        seen += 1;
    }
    try std.testing.expect(seen > 0);
}

test "node iterator surfaces OOM instead of silent termination" {
    const leaf = peg.Node{ .tag = "leaf", .text = "x", .children = &.{} };
    const child_slice = try std.testing.allocator.alloc(peg.Node, 3);
    child_slice[0] = leaf;
    child_slice[1] = leaf;
    child_slice[2] = leaf;
    const root = peg.Node{ .tag = "root", .text = "x", .children = child_slice };
    defer peg.freeNode(std.testing.allocator, root);

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var it = try peg.NodeIterator.init(failing.allocator(), root);
    defer it.deinit();

    const first = it.next();
    if (first) |maybe_node| {
        _ = maybe_node orelse return error.ShouldHaveFailed;
        try std.testing.expectError(error.OutOfMemory, it.next());
    } else |err| switch (err) {
        error.OutOfMemory => {},
        else => return err,
    }
}

test "parseDetailed provides error class" {
    const bad_start = calc.parseDetailed(std.testing.allocator, "missing_rule", "1+2");
    switch (bad_start) {
        .ok => return error.ShouldHaveFailed,
        .err => |e| try std.testing.expectEqual(peg.ParseErrorClass.start_rule, e.class),
    }
}

const trace_test = peg.compile(
    \\start <- _ws item (_ws ',' _ws item)* _ws
    \\item  <- [a-z]+
    \\@silent _ws   <- [ \t]*
);

test "trace mode logs rule entry, exit and backtrack" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var trace_buf: std.ArrayListUnmanaged(u8) = .{};
    defer trace_buf.deinit(arena.allocator());

    _ = try trace_test.parseWithOptions(
        arena.allocator(),
        "start",
        "a, b, c",
        .{ .trace = true, .trace_buffer = &trace_buf },
    );

    try std.testing.expect(trace_buf.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, trace_buf.items, "-> start @") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace_buf.items, "<- start ok") != null);
}

const trace_backtrack_test = peg.compile(
    \\start <- 'ab' / 'ac'
);

test "trace mode logs backtrack points" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var trace_buf: std.ArrayListUnmanaged(u8) = .{};
    defer trace_buf.deinit(arena.allocator());

    _ = try trace_backtrack_test.parseWithOptions(
        arena.allocator(),
        "start",
        "ac",
        .{ .trace = true, .trace_buffer = &trace_buf },
    );

    try std.testing.expect(std.mem.indexOf(u8, trace_buf.items, "backtrack choice alt#0") != null);
}

const lint_diags = peg.lint(
    \\start <- item
    \\item <- [a-z]*
    \\unused <- 'x'
    \\never <- 'n'
    \\literal_shadow <- 'a' / 'ab'
);

test "lint diagnostics report unused, unreachable, nullable and shadowed choice" {
    try std.testing.expect(lint_diags.len >= 4);

    var saw_unused = false;
    var saw_unreachable = false;
    var saw_nullable = false;
    var saw_shadow = false;
    for (lint_diags) |d| {
        switch (d.kind) {
            .unused_rule => saw_unused = true,
            .unreachable_rule => saw_unreachable = true,
            .nullable_rule => saw_nullable = true,
            .suspicious_choice_order => saw_shadow = true,
            .direct_left_recursion => {},
        }
    }
    try std.testing.expect(saw_unused);
    try std.testing.expect(saw_unreachable);
    try std.testing.expect(saw_nullable);
    try std.testing.expect(saw_shadow);
}

const lint_nullable_chain_diags = peg.lint(
    \\start <- a
    \\a <- b
    \\b <- ''
);
const lint_shadow_diags = peg.lint(
    \\start <- 'a' / 'ab'
);
const lint_repeat_nullable_diags = peg.lint(
    \\start <- item*
    \\item <- '' / 'x'
);
const lint_leftrec_table_diags = peg.lint(
    \\expr <- expr '+' term / term
    \\term <- [0-9]+
);
const lint_negative_baseline_diags = peg.lint(
    \\start <- number ('+' number)*
    \\number <- [0-9]+
);

test "lint table covers nullable/shadow/repeat-leftrec patterns" {
    const cases = .{
        .{ .name = "nullable chain", .diags = lint_nullable_chain_diags, .kind = peg.LintKind.nullable_rule, .rule = "start", .msg = "may match empty" },
        .{ .name = "choice shadowing", .diags = lint_shadow_diags, .kind = peg.LintKind.suspicious_choice_order, .rule = "start", .msg = "choice may shadow" },
        .{ .name = "repeat nullable risk", .diags = lint_repeat_nullable_diags, .kind = peg.LintKind.nullable_rule, .rule = "item", .msg = "may match empty" },
        .{ .name = "direct left recursion", .diags = lint_leftrec_table_diags, .kind = peg.LintKind.direct_left_recursion, .rule = "expr", .msg = "direct left recursion" },
    };

    inline for (cases) |c| {
        var found = false;
        for (c.diags) |d| {
            if (d.kind == c.kind and std.mem.eql(u8, d.rule, c.rule) and std.mem.indexOf(u8, d.message, c.msg) != null) {
                found = true;
                break;
            }
        }
        if (!found) std.debug.print("missing lint case: {s}\n", .{c.name});
        try std.testing.expect(found);
    }
}

test "lint table negative baseline has no target diagnostics" {
    for (lint_negative_baseline_diags) |d| {
        try std.testing.expect(d.kind != .nullable_rule);
        try std.testing.expect(d.kind != .suspicious_choice_order);
        try std.testing.expect(d.kind != .direct_left_recursion);
    }
}

const left_rec_diags = peg.lint(
    \\expr <- expr '+' term / term
    \\term <- [0-9]+
);

test "lint diagnostics report direct left recursion" {
    var saw_direct_left = false;
    for (left_rec_diags) |d| {
        if (d.kind == .direct_left_recursion and std.mem.eql(u8, d.rule, "expr")) {
            saw_direct_left = true;
        }
    }
    try std.testing.expect(saw_direct_left);
}

const left_rec_lite = peg.compileWithOptions(
    \\expr <- expr '+' term / term
    \\term <- _ws [0-9]+ _ws
    \\@silent _ws  <- [ \t]*
, .{ .left_recursion_mode = .rewrite });

test "left recursion lite rewrites expression chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try left_rec_lite.parse(arena.allocator(), "expr", "1 + 2 + 3");
    try std.testing.expectEqual(@as(usize, 9), result.pos);
}

const lint_warn_mode_compile = peg.compileWithOptions(
    \\start <- [a-z]*
    \\unused <- 'x'
, .{ .lint_mode = .warn });

test "compileWithOptions supports lint warn mode" {
    const res = try lint_warn_mode_compile.parse(std.testing.allocator, "start", "abc");
    defer peg.freeNode(std.testing.allocator, res.node);
    try std.testing.expectEqual(@as(usize, 3), res.pos);
}

const memo_override_on = peg.compile(
    \\start <- item item item
    \\@memo_on item <- 'a'
);

test "per-rule memo on overrides global off" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var stats: peg.ParseStats = .{};
    const res = try memo_override_on.parseWithOptions(arena.allocator(), "start", "aaa", .{
        .memo_mode = .off,
        .stats = &stats,
    });
    try std.testing.expectEqual(@as(usize, 3), res.pos);
    try std.testing.expect(stats.memo_puts >= 1);
}

const memo_override_off = peg.compile(
    \\start <- item item
    \\@memo_off item <- 'a'
);

test "per-rule memo off disables memo for rule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var stats: peg.ParseStats = .{};
    const res = try memo_override_off.parseWithOptions(arena.allocator(), "start", "aa", .{
        .memo_mode = .on,
        .stats = &stats,
    });
    try std.testing.expectEqual(@as(usize, 2), res.pos);
    // Only `start` itself is memoized in this parse.
    try std.testing.expectEqual(@as(usize, 1), stats.memo_puts);
}

const calc_clean = peg.compile(
    \\expr    <- _ws sum _ws
    \\sum     <- product (_ws op_add _ws product)*
    \\product <- atom (_ws op_mul _ws atom)*
    \\atom    <- number / '(' _ws sum _ws ')'
    \\number  <- [0-9]+
    \\op_add  <- '+' / '-'
    \\op_mul  <- '*' / '/'
    \\@silent _ws     <- [ \t]*
);

test "manual ws grammar parses spaced expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try calc_clean.parse(arena.allocator(), "expr", " ( 2 + 3 ) * 4 ");
    const evaluator = makeEvaluator(arena.allocator());
    const value = try evaluator.walk(result.node, {});
    try std.testing.expectEqual(@as(i64, 20), value);
}

const auto_ws_atomic = peg.compile(
    \\start   <- ident _ws ident
    \\ident  <- [a-z]+
    \\@silent _ws     <- [ \t]*
);

test "manual ws separates identifiers explicitly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try auto_ws_atomic.parse(arena.allocator(), "start", "a b");

    try std.testing.expectEqual(@as(usize, 2), result.node.children.len);
    try std.testing.expectEqualStrings("a", result.node.children[0].text);
    try std.testing.expectEqualStrings("b", result.node.children[1].text);
}

const opt_ws_test = peg.compile(
    \\start <- 'A' (_ws opt)?
    \\opt   <- 'B'
    \\@silent _ws   <- [ \t]+
);

test "optional with manual ws separator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try opt_ws_test.parse(arena.allocator(), "start", "A");
    _ = try opt_ws_test.parse(arena.allocator(), "start", "A B");
}

const repeat_ws_test = peg.compile(
    \\start <- item (_ws item){1,2}
    \\item  <- '[' word ',' word ']'
    \\word  <- [a-z]+
    \\@silent _ws   <- [ \t\n\r]+
);

test "repeat range with manual ws between iterations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try repeat_ws_test.parse(arena.allocator(), "start", "[a,b] [c,d]");
    _ = try repeat_ws_test.parse(arena.allocator(), "start", "[a,b]\n[c,d]\n[e,f]");

    const partial = try repeat_ws_test.parseWithOptions(
        arena.allocator(),
        "start",
        "[a,b] [c,d] [e,f] [g,h]",
        .{ .consume_mode = .partial },
    );
    try std.testing.expectEqual(@as(usize, 17), partial.pos);
}

const lookahead_ws_test = peg.compile(
    \\start <- key _ws ':' _ws value
    \\key   <- &[_a-zA-Z] [a-zA-Z_]+
    \\value <- !'null' [a-z]+ / 'null'
    \\@silent _ws   <- [ \t]*
);

test "lookahead predicates remain stable with manual ws" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try lookahead_ws_test.parse(arena.allocator(), "start", "name: value");
    _ = try lookahead_ws_test.parse(arena.allocator(), "start", "name : null");

    if (lookahead_ws_test.parse(arena.allocator(), "start", "name : 123")) |_| {
        return error.ShouldHaveFailed;
    } else |err| {
        try std.testing.expectEqual(error.ParseFailed, err);
    }
}

const atomic_ws_test = peg.compile(
    \\start   <- token _ws ',' _ws number
    \\token  <- [a-z]+
    \\number  <- [0-9]+
    \\@silent _ws     <- [ \t]*
);

test "token still disallows internal spaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try atomic_ws_test.parse(arena.allocator(), "start", "abc, 123");
    if (atomic_ws_test.parse(arena.allocator(), "start", "ab c, 123")) |_| {
        return error.ShouldHaveFailed;
    } else |err| {
        try std.testing.expectEqual(error.ParseFailed, err);
    }
}

const opt_seq_ws_test = peg.compile(
    \\start <- 'A' (_ws maybe_tail)?
    \\maybe_tail <- 'B' 'C'
    \\@silent _ws <- [ \t]+
);

test "optional(sequence) uses manual ws boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try opt_seq_ws_test.parse(arena.allocator(), "start", "A");
    _ = try opt_seq_ws_test.parse(arena.allocator(), "start", "A BC");
}

const repeat_seq_ws_test = peg.compile(
    \\start <- pair (_ws pair)*
    \\pair <- '(' item ',' item ')'
    \\item <- [a-z]+
    \\@silent _ws <- [ \t\n\r]+
);

test "repeat(sequence) uses manual ws boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try repeat_seq_ws_test.parse(arena.allocator(), "start", "(a,b) (c,d) (e,f)");
}

const choice_ws_test = peg.compile(
    \\start <- ((maybe_kw _ws) / '') ident
    \\maybe_kw <- 'LET'i / 'VAR'i
    \\ident <- [a-z]+
    \\@silent _ws <- [ \t]+
);

test "choice wrapper uses manual ws boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try choice_ws_test.parse(arena.allocator(), "start", "LET item");
    _ = try choice_ws_test.parse(arena.allocator(), "start", "item");
}

const predicate_guard_test = peg.compile(
    \\start <- key _ws ':' _ws value
    \\key <- [a-z]+
    \\value <- !'null' [a-z]+ / 'null'
    \\@silent _ws <- [ \t]*
);

test "predicates remain sensitive with manual ws" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try predicate_guard_test.parse(arena.allocator(), "start", "name: value");
    _ = try predicate_guard_test.parse(arena.allocator(), "start", "name : null");
}

const regex_primitive_test = peg.compile(
    \\start <- method _sp version
    \\method <- ~"[A-Z]+"
    \\version <- ~"HTTP/[0-9]+[.][0-9]+"
    \\@silent _sp <- ~"[ \t]+"
);

test "regex-like primitive matches token patterns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try regex_primitive_test.parse(arena.allocator(), "start", "GET HTTP/1.1");
    _ = try regex_primitive_test.parse(arena.allocator(), "start", "POST\tHTTP/1.0");

    if (regex_primitive_test.parse(arena.allocator(), "start", "get HTTP/1.1")) |_| {
        return error.ShouldHaveFailed;
    } else |err| {
        try std.testing.expectEqual(error.ParseFailed, err);
    }
}

const squashed_rule_test = peg.compile(
    \\start <- pair
    \\@squashed pair <- key ':' value
    \\key <- ~"[a-z]+"
    \\value <- ~"[0-9]+"
    \\@silent _ws <- [ \t]*
);

test "squashed rule flattens intermediate node" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const res = try squashed_rule_test.parse(arena.allocator(), "start", "foo:123");
    try std.testing.expectEqual(@as(usize, 2), res.node.children.len);
    try std.testing.expectEqualStrings("key", res.node.children[0].tag);
    try std.testing.expectEqualStrings("value", res.node.children[1].tag);
}

test "treeJsonAlloc exports parse tree as json" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const res = try calc.parse(arena.allocator(), "expr", "2+3");
    const json = try peg.treeJsonAlloc(arena.allocator(), res.node);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tag\":\"expr\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"children\"") != null);
}