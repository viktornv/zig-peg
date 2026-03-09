const std = @import("std");
const peg = @import("peg");

const ini = peg.compile(
    \\file       <- (section / comment / blank)*
    \\section    <- header _nl (pair / comment / blank)*
    \\header     <- '[' _sp _name _sp ']'
    \\pair       <- _sp _name _sp '=' _sp _value _nl?
    \\@silent _name      <- [a-zA-Z_] [a-zA-Z0-9_]*
    \\@silent _value     <- [^\n]*
    \\comment    <- _sp _commentch [^\n]* _nl?
    \\@silent _commentch <- '#' / ';'
    \\blank      <- _sp _nl
    \\@silent _nl        <- '\r\n' / '\n'
    \\@silent _sp        <- [ \t]*
    \\@silent _ws        <- [ \t]*
);

fn expectParseFull(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try ini.parse(arena.allocator(), "file", input);
    std.debug.print("  OK\n", .{});
}

fn parseFile(allocator: std.mem.Allocator, input: []const u8) !peg.ParseSuccess {
    return ini.parse(allocator, "file", input);
}

fn countAll(node: peg.Node, tag: []const u8) usize {
    var count: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) count += 1;
    for (node.children) |child| count += countAll(child, tag);
    return count;
}

test "empty file" {
    std.debug.print("\n-- ini: empty --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try parseFile(arena.allocator(), "");
    try std.testing.expectEqualStrings("file", result.node.tag);
    std.debug.print("  OK: empty file\n", .{});
}

test "simple section" {
    std.debug.print("\n-- ini: simple section --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input = "[database]\nhost=localhost\nport=5432";
    const result = try parseFile(arena.allocator(), input);
    peg.printTree(result.node, 2);

    var found_section = false;
    for (result.node.children) |child| {
        if (std.mem.eql(u8, child.tag, "section")) {
            found_section = true;
            try std.testing.expect(countAll(child, "header") >= 1);
            try std.testing.expect(countAll(child, "pair") >= 2);
        }
    }
    try std.testing.expect(found_section);
    std.debug.print("  OK: simple section\n", .{});
}

test "multiple sections" {
    std.debug.print("\n-- ini: multiple sections --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input = "[server]\nhost=0.0.0.0\nport=8080\n\n[database]\nhost=localhost\nport=5432";
    const result = try parseFile(arena.allocator(), input);
    const section_count = countAll(result.node, "section");
    try std.testing.expectEqual(@as(usize, 2), section_count);
    std.debug.print("  OK: {} sections\n", .{section_count});
}

test "comments" {
    std.debug.print("\n-- ini: comments --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input = "# This is a comment\n; Another comment\n[section]\n# comment inside\nkey=value";
    const result = try parseFile(arena.allocator(), input);
    const comment_count = countAll(result.node, "comment");
    try std.testing.expect(comment_count >= 2);
    std.debug.print("  OK: {} comments\n", .{comment_count});
}

test "values with spaces" {
    std.debug.print("\n-- ini: values with spaces --\n", .{});
    try expectParseFull("[app]\nname = My Application\npath = /usr/local/bin");
}

test "empty values" {
    std.debug.print("\n-- ini: empty values --\n", .{});
    try expectParseFull("[section]\nkey=\nother=value");
}

test "blank lines" {
    std.debug.print("\n-- ini: blank lines --\n", .{});
    try expectParseFull("\n\n[section]\n\nkey=value\n\n");
}

test "underscore names" {
    std.debug.print("\n-- ini: underscore names --\n", .{});
    try expectParseFull("[my_section]\nmy_key=my_value\n_private=123");
}

test "complex ini" {
    std.debug.print("\n-- ini: complex --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input = "# App config\n\n[general]\nname = MyApp\nversion = 1.0.0\n\n[database]\n; DB settings\nhost = localhost\nport = 5432\nname = mydb\n\n[logging]\nlevel = info\nfile = /var/log/app.log";
    const result = try ini.parse(arena.allocator(), "file", input);
    const section_count = countAll(result.node, "section");
    try std.testing.expectEqual(@as(usize, 3), section_count);
    std.debug.print("  OK: complex ini ({} sections)\n", .{section_count});
}