const std = @import("std");
const peg = @import("peg");

const toml = peg.compile(
    \\document    <- _ws (item _ws)*
    \\@squashed item <- table / pair / comment
    \\table       <- '[' _ws dotted_key _ws ']'
    \\pair        <- key _ws '=' _ws value
    \\@squashed key <- dotted_key / quoted_key / bare_key
    \\@squashed dotted_key <- key_part (_ws '.' _ws key_part)*
    \\@squashed key_part <- bare_key / quoted_key
    \\bare_key    <- [a-zA-Z0-9_\-]+
    \\@squashed quoted_key <- string
    \\@squashed value <- datetime / float / integer / bool / array / string
    \\string     <- '"' _strchar* '"'
    \\@silent _strchar    <- _escaped / [^"\\]
    \\@silent _escaped    <- '\\' ['"\\nrt]
    \\datetime    <- [0-9]{4} '-' [0-9]{2} '-' [0-9]{2} 'T' [0-9]{2} ':' [0-9]{2} ':' [0-9]{2} 'Z'
    \\float       <- '-'? [0-9]+ '.' [0-9]+
    \\integer     <- '-'? [0-9]+
    \\bool        <- 'true' / 'false'
    \\@squashed array <- '[' _ws (value (_ws ',' _ws value)*)? _ws ']'
    \\comment     <- '#' [^\n]*
    \\@silent _ws         <- [ \t\n\r]*
);

fn expectParseAll(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try toml.parse(arena.allocator(), "document", input);
    std.debug.print("  OK\n", .{});
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    if (toml.parse(arena.allocator(), "document", input)) |r| {
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

test "toml scalars" {
    std.debug.print("\n-- toml: scalars --\n", .{});
    try expectParseAll("title=\"TOML\"");
    try expectParseAll("enabled=true");
    try expectParseAll("count=42");
    try expectParseAll("ratio=3.14");
    try expectParseAll("when=2026-03-07T10:30:00Z");
}

test "toml arrays" {
    std.debug.print("\n-- toml: arrays --\n", .{});
    try expectParseAll("nums=[1,2,3]");
    try expectParseAll("mixed=[1,true,\"x\",3.5]");
    try expectParseAll("empty=[]");
}

test "toml dotted keys and tables" {
    std.debug.print("\n-- toml: dotted/table --\n", .{});
    try expectParseAll("[server]\nhost=\"localhost\"\nport=8080");
    try expectParseAll("[database.main]\nmax_connections=100");
    try expectParseAll("\"service.name\"=\"api\"");
}

test "toml comments and whitespace" {
    std.debug.print("\n-- toml: comments/ws --\n", .{});
    try expectParseAll(
        \\# top level
        \\title = "My App"
        \\
        \\[server]
        \\# bind address
        \\host = "0.0.0.0"
        \\port = 8080
    );
}

test "toml tree structure" {
    std.debug.print("\n-- toml: tree --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const input =
        \\[server]
        \\host="localhost"
        \\port=8080
        \\[database.main]
        \\enabled=true
    ;
    const result = try toml.parse(arena.allocator(), "document", input);
    const table_count = countTag(result.node, "table");
    const pair_count = countTag(result.node, "pair");
    try std.testing.expectEqual(@as(usize, 2), table_count);
    try std.testing.expectEqual(@as(usize, 3), pair_count);
    std.debug.print("  tables={}, pairs={}\n", .{ table_count, pair_count });
}

test "toml invalid inputs" {
    std.debug.print("\n-- toml: invalid --\n", .{});
    try expectFail("key");
    try expectFail("[table");
    try expectFail("name=\"unterminated");
    try expectFail("enabled=TRUE");
    try expectFail("nums=[1,2,]");
}
