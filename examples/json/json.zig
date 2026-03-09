const std = @import("std");
const peg = @import("peg");

const json = peg.compile(
    \\value   <- _ws (object / array / string / number / bool / null) _ws
    \\object  <- '{' _ws (pair (_ws ',' _ws pair)*)? _ws '}'
    \\pair    <- string _ws ':' _ws value
    \\array   <- '[' _ws (value (_ws ',' _ws value)*)? _ws ']'
    \\string <- '"' _strchar* '"'
    \\number <- _minus? _int _frac? _exp?
    \\bool   <- 'true' / 'false'
    \\null   <- 'null'
    \\@silent _strchar <- _escaped / [^"\\]
    \\@silent _escaped <- '\\' ["\\/bfnrt]
    \\@silent _minus  <- '-'
    \\@silent _int    <- '0' / [1-9] [0-9]*
    \\@silent _frac   <- '.' [0-9]+
    \\@silent _exp    <- [eE] [+\-]? [0-9]+
    \\@silent _ws     <- [ \t\n\r]*
);

const lint_demo = peg.compileWithOptions(
    \\start  <- item*
    \\item   <- 'ab' / 'a'
    \\unused <- 'x'
,
    .{ .lint_mode = .warn },
);

const lint_diagnostics = peg.lint(
    \\start  <- item*
    \\item   <- 'ab' / 'a'
    \\unused <- 'x'
);

fn expectParse(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try json.parse(arena.allocator(), "value", input);
    std.debug.print("  OK: {s}\n", .{input});
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (json.parse(arena.allocator(), "value", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
        std.debug.print("  REJECTED: {s} (partial)\n", .{input});
    } else |_| {
        std.debug.print("  REJECTED: {s}\n", .{input});
    }
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var count: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) count += 1;
    for (node.children) |child| count += countTag(child, tag);
    return count;
}

test "null and bool" {
    std.debug.print("\n-- null/bool --\n", .{});
    try expectParse("null");
    try expectParse("true");
    try expectParse("false");
}

test "integers" {
    std.debug.print("\n-- integers --\n", .{});
    try expectParse("0");
    try expectParse("42");
    try expectParse("-1");
    try expectParse("-0");
    try expectParse("123456789");
    try expectParse("-999");
}

test "floats" {
    std.debug.print("\n-- floats --\n", .{});
    try expectParse("3.14");
    try expectParse("-0.5");
    try expectParse("0.0");
    try expectParse("100.001");
    try expectParse("-123.456");
}

test "exponents" {
    std.debug.print("\n-- exponents --\n", .{});
    try expectParse("1e10");
    try expectParse("2.5E-3");
    try expectParse("1E+2");
    try expectParse("0e0");
    try expectParse("-1e5");
    try expectParse("1.5e10");
    try expectParse("3E0");
}

test "invalid numbers" {
    std.debug.print("\n-- invalid numbers --\n", .{});
    try expectFail("+1");
    try expectFail(".5");
    try expectFail("01");
    try expectFail("1.");
    try expectFail("e5");
    try expectFail("1e");
}

test "simple strings" {
    std.debug.print("\n-- simple strings --\n", .{});
    try expectParse("\"hello\"");
    try expectParse("\"\"");
    try expectParse("\"hello world\"");
    try expectParse("\"abc123\"");
    try expectParse("\"   spaces   \"");
}

test "string escapes" {
    std.debug.print("\n-- string escapes --\n", .{});
    try expectParse("\"line\\nbreak\"");
    try expectParse("\"tab\\there\"");
    try expectParse("\"escaped\\\"quote\"");
    try expectParse("\"back\\\\slash\"");
    try expectParse("\"carriage\\rreturn\"");
    try expectParse("\"\\b\\f\\/\"");
    try expectParse("\"all: \\\" \\\\ \\/ \\b \\f \\n \\r \\t\"");
}

test "invalid strings" {
    std.debug.print("\n-- invalid strings --\n", .{});
    try expectFail("\"unterminated");
    try expectFail("'single quotes'");
    try expectFail("no quotes");
}

test "arrays" {
    std.debug.print("\n-- arrays --\n", .{});
    try expectParse("[]");
    try expectParse("[1]");
    try expectParse("[1, 2, 3]");
    try expectParse("[1, \"two\", true, null]");
    try expectParse("[[1, 2], [3, 4]]");
    try expectParse("[[], [], []]");
    try expectParse("[[[[1]]]]");
    try expectParse("[1, [2, [3, [4]]]]");
}

test "invalid arrays" {
    std.debug.print("\n-- invalid arrays --\n", .{});
    try expectFail("[");
    try expectFail("[1,]");
    try expectFail("[,1]");
    try expectFail("[1,,2]");
}

test "objects" {
    std.debug.print("\n-- objects --\n", .{});
    try expectParse("{}");
    try expectParse("{\"a\": 1}");
    try expectParse("{\"a\": 1, \"b\": 2}");
    try expectParse("{\"name\": \"John\", \"age\": 30, \"active\": true}");
    try expectParse("{\"key\": null}");
    try expectParse("{\"x\": [1, 2, 3]}");
    try expectParse("{\"nested\": {\"a\": 1}}");
}

test "invalid objects" {
    std.debug.print("\n-- invalid objects --\n", .{});
    try expectFail("{");
    try expectFail("{key: 1}");
    try expectFail("{\"a\": 1,}");
    try expectFail("{\"a\"}");
    try expectFail("{: 1}");
}

test "deep nesting" {
    std.debug.print("\n-- deep nesting --\n", .{});
    try expectParse("{\"users\": [{\"name\": \"Alice\"}, {\"name\": \"Bob\"}]}");
    try expectParse("{\"a\": {\"b\": {\"c\": 1}}}");
    try expectParse("[{\"x\": [1, 2]}, {\"y\": [3, 4]}]");
    try expectParse("{\"a\": [{\"b\": [{\"c\": [1]}]}]}");
    try expectParse("[[{\"x\": 1}, {\"y\": 2}], [{\"z\": 3}]]");
}

test "whitespace" {
    std.debug.print("\n-- whitespace --\n", .{});
    try expectParse("  null  ");
    try expectParse("  42  ");
    try expectParse("  \"hello\"  ");
    try expectParse("  true  ");
    try expectParse("  [  1  ,  2  ,  3  ]  ");
    try expectParse("  {  \"a\"  :  1  }  ");
    try expectParse("  {  \"a\"  :  [  1  ,  2  ]  }  ");
    try expectParse("{\n  \"name\": \"test\",\n  \"value\": 42\n}");
    try expectParse("[\n  1,\n  2,\n  3\n]");
}

test "edge cases" {
    std.debug.print("\n-- edge cases --\n", .{});
    try expectParse("[{}]");
    try expectParse("{\"a\": []}");
    try expectParse("[{}, {}, {}]");
    try expectParse("0");
    try expectParse("-0");
    try expectParse("\"\"");
    try expectParse("false");
    try expectParse("[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]");
    try expectParse("{\"a\": 1, \"b\": 2, \"c\": 3, \"d\": 4, \"e\": 5}");
}

test "complete invalid" {
    std.debug.print("\n-- complete invalid --\n", .{});
    try expectFail("");
    try expectFail("abc");
    try expectFail("nul");
    try expectFail("tru");
    try expectFail("fals");
    try expectFail("NULL");
    try expectFail("True");
    try expectFail("FALSE");
    try expectFail("undefined");
    try expectFail("NaN");
    try expectFail("Infinity");
}

test "tree" {
    std.debug.print("\n-- tree --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input = "{\"name\": \"test\", \"value\": 42}";
    std.debug.print("  Tree for: {s}\n", .{input});
    const result = try json.parse(arena.allocator(), "value", input);
    peg.printTree(result.node, 2);
}

test "tree structure" {
    std.debug.print("\n-- tree structure --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try json.parse(arena.allocator(), "value", "{\"a\": 1, \"b\": 2}");
    try std.testing.expectEqualStrings("value", result.node.tag);
    try std.testing.expect(result.node.children.len >= 1);
    var object: ?peg.Node = null;
    for (result.node.children) |child| {
        if (std.mem.eql(u8, child.tag, "object")) { object = child; break; }
    }
    try std.testing.expect(object != null);
    try std.testing.expect(countTag(object.?, "pair") == 2);
    std.debug.print("  OK: tree structure\n", .{});
}

test "array tree structure" {
    std.debug.print("\n-- array tree --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try json.parse(arena.allocator(), "value", "[1, \"hello\", true]");
    peg.printTree(result.node, 2);
    var array: ?peg.Node = null;
    for (result.node.children) |child| {
        if (std.mem.eql(u8, child.tag, "array")) { array = child; break; }
    }
    try std.testing.expect(array != null);
    try std.testing.expect(countTag(array.?, "value") == 3);
    std.debug.print("  OK: array tree\n", .{});
}

test "trace mode demo" {
    std.debug.print("\n-- trace mode demo --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var trace_buf: std.ArrayListUnmanaged(u8) = .{};
    defer trace_buf.deinit(arena.allocator());

    _ = try json.parseWithOptions(
        arena.allocator(),
        "value",
        "{\"a\": 1}",
        .{ .trace = true, .trace_buffer = &trace_buf },
    );

    try std.testing.expect(trace_buf.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, trace_buf.items, "value") != null);
}

test "tree json export demo" {
    std.debug.print("\n-- tree json demo --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const parsed = try json.parse(arena.allocator(), "value", "{\"ok\": true}");
    const tree_json = try peg.treeJsonAlloc(arena.allocator(), parsed.node);
    try std.testing.expect(std.mem.indexOf(u8, tree_json, "\"tag\":\"value\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, tree_json, "\"children\"") != null);
}

test "lint api demo" {
    std.debug.print("\n-- lint api demo --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try lint_demo.parse(arena.allocator(), "start", "ab");

    try std.testing.expect(lint_diagnostics.len >= 1);
}

test "detailed error context and expected set" {
    std.debug.print("\n-- detailed error context demo --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const bad_input =
        \\{
        \\  "a": 1,
        \\  "b":
        \\  "c": 3
        \\}
    ;
    const detailed = json.parseDetailed(arena.allocator(), "value", bad_input);
    switch (detailed) {
        .ok => |_| return error.ShouldHaveFailed,
        .err => |e| {
            try std.testing.expect(e.expected_count >= 2);
            try std.testing.expect(e.context_prev.len > 0);
            try std.testing.expect(e.context_next.len > 0);
        },
    }
}