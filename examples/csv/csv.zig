const std = @import("std");
const peg = @import("peg");

const csv = peg.compile(
    \\csv       <- record (_nl record)* _nl?
    \\record    <- field (',' field)*
    \\field     <- quoted / unquoted / ''
    \\quoted   <- '"' qchar* '"'
    \\qchar     <- '""' / [^"]
    \\unquoted <- [^,\n\r"]+
    \\@silent _nl       <- '\r\n' / '\n'
);

fn expectParseAll(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try csv.parse(arena.allocator(), "csv", input);
    std.debug.print("  OK\n", .{});
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (csv.parse(arena.allocator(), "csv", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
        std.debug.print("  PARTIAL (ok), pos={}/{}\n", .{ r.pos, input.len });
    } else |_| {
        std.debug.print("  REJECTED (ok)\n", .{});
    }
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var count: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) count += 1;
    for (node.children) |child| count += countTag(child, tag);
    return count;
}

test "csv simple rows" {
    std.debug.print("\n-- csv: simple --\n", .{});
    try expectParseAll("a,b,c");
    try expectParseAll("1,2,3\n4,5,6");
    try expectParseAll("name,age\nalice,30\nbob,25");
}

test "csv empty fields" {
    std.debug.print("\n-- csv: empty fields --\n", .{});
    try expectParseAll("a,,c");
    try expectParseAll(",start,end,");
    try expectParseAll(",,");
}

test "csv quoted and escaped quotes" {
    std.debug.print("\n-- csv: quoted --\n", .{});
    try expectParseAll("\"a,b\",c");
    try expectParseAll("\"hello \"\"world\"\"\",42");
    try expectParseAll("\" spaced \",plain");
}

test "csv multiline quoted fields" {
    std.debug.print("\n-- csv: multiline --\n", .{});
    try expectParseAll("\"line1\nline2\",x\none,two");
    try expectParseAll("id,notes\n1,\"first\nsecond\nthird\"");
}

test "csv line endings" {
    std.debug.print("\n-- csv: line endings --\n", .{});
    try expectParseAll("a,b\r\nc,d\r\n");
    try expectParseAll("a,b\nc,d\n");
}

test "csv tree structure" {
    std.debug.print("\n-- csv: tree --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const input = "h1,h2,h3\nv1,\"v,2\",v3\nx,y,z";
    const result = try csv.parse(arena.allocator(), "csv", input);
    const record_count = countTag(result.node, "record");
    const field_count = countTag(result.node, "field");
    try std.testing.expectEqual(@as(usize, 3), record_count);
    try std.testing.expectEqual(@as(usize, 9), field_count);
    std.debug.print("  records={}, fields={}\n", .{ record_count, field_count });
}

test "csv invalid inputs" {
    std.debug.print("\n-- csv: invalid --\n", .{});
    try expectFail("\"unterminated,a,b");
    try expectFail("a,\"bad\"quote\",c");
    try expectFail("a,b\n\"x\"y,z");
}
