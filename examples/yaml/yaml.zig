const std = @import("std");
const peg = @import("peg");

// Practical YAML subset focused on docker-compose-like files.
// Supports:
// - key: value
// - key: (nested map/list)
// - list items: - value
// - 2-space indentation up to 3 nested levels
// - quoted and bare scalars
const yaml = peg.compile(
    \\document <- (_line0 (_nl _line0)*)? _nl?
    \\@silent _line0   <- pair0 / comment0
    \\pair0    <- key ':' (_sp value / _nl block1)?
    \\block1   <- _line1 (_nl _line1)*
    \\@silent _line1   <- _i1 (pair1 / list1 / comment1)
    \\pair1    <- key ':' (_sp value / _nl block2)?
    \\list1    <- '-' _sp value
    \\block2   <- _line2 (_nl _line2)*
    \\@silent _line2   <- _i2 (pair2 / list2 / comment2)
    \\pair2    <- key ':' (_sp value / _nl block3)?
    \\list2    <- '-' _sp value
    \\block3   <- _line3 (_nl _line3)*
    \\@silent _line3   <- _i3 (pair3 / list3 / comment3)
    \\pair3    <- key ':' (_sp value)?
    \\list3    <- '-' _sp value
    \\value    <- quoted / bare
    \\quoted  <- '"' [^"\n]* '"' / '\'' [^'\n]* '\''
    \\bare    <- [^#\n][^#\n]*
    \\key     <- [a-zA-Z_][a-zA-Z0-9_\-]*
    \\comment0 <- '#' [^\n]*
    \\comment1 <- '#' [^\n]*
    \\comment2 <- '#' [^\n]*
    \\comment3 <- '#' [^\n]*
    \\@silent _i1      <- '  '
    \\@silent _i2      <- '    '
    \\@silent _i3      <- '      '
    \\@silent _sp      <- [ \t]+
    \\@silent _nl      <- '\r\n' / '\n'
    \\@silent _ws      <- [ \t\r]*
);

fn expectParseAll(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try yaml.parse(arena.allocator(), "document", input);
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (yaml.parse(arena.allocator(), "document", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
    } else |_| {}
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var count: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) count += 1;
    for (node.children) |child| count += countTag(child, tag);
    return count;
}

test "yaml simple key values" {
    try expectParseAll("version: \"3.9\"");
    try expectParseAll("name: app");
    try expectParseAll("restart: always");
    try expectParseAll("db_data:");
}

test "yaml lists and comments" {
    try expectParseAll(
        \\ports:
        \\  - "80:80"
        \\  - "443:443"
    );
    try expectParseAll(
        \\# compose file
        \\services:
        \\  # app service
        \\  web:
        \\    image: nginx:latest
    );
}

test "yaml docker compose sample" {
    try expectParseAll(
        \\version: "3.9"
        \\services:
        \\  web:
        \\    image: nginx:latest
        \\    ports:
        \\      - "80:80"
        \\      - "443:443"
        \\    environment:
        \\      - DEBUG=true
        \\      - LOG_LEVEL=info
        \\  db:
        \\    image: postgres:16
        \\    volumes:
        \\      - db_data:/var/lib/postgresql/data
        \\volumes:
        \\  db_data:
    );
}

test "yaml mapping nesting" {
    try expectParseAll(
        \\services:
        \\  api:
        \\    build: .
        \\    depends_on:
        \\      - db
        \\      - redis
        \\  db:
        \\    image: postgres
    );
}

test "yaml tree counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const pair = try yaml.parse(arena.allocator(), "pair0", "image: nginx");
    try std.testing.expectEqualStrings("pair0", pair.node.tag);
    try std.testing.expect(countTag(pair.node, "key") >= 1);
    try std.testing.expect(countTag(pair.node, "value") >= 1);

    const list = try yaml.parse(arena.allocator(), "list3", "- \"80:80\"");
    try std.testing.expectEqualStrings("list3", list.node.tag);
    try std.testing.expect(countTag(list.node, "value") >= 1);
}

test "yaml invalid cases" {
    try expectFail("services");
    try expectFail("services:\n web:");
    try expectFail("services:\n  -");
    try expectFail("services:\n  web\n    image: nginx");
}
