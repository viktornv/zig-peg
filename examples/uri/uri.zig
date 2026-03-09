const std = @import("std");
const peg = @import("peg");

const uri = peg.compile(
    \\uri       <- scheme '://' authority path_abempty ('?' query)? ('#' fragment)?
    \\scheme    <- _alpha (_alpha / _digit / '+' / '-' / '.')*
    \\authority <- (userinfo '@')? host (':' port)?
    \\@squashed userinfo <- (_unreserved / _pct / _subdelim / ':')*
    \\host      <- ip_literal / ipv4 / reg_name
    \\ip_literal <- '[' _ipvchar+ ']'
    \\ipv4      <- _decnum '.' _decnum '.' _decnum '.' _decnum
    \\@squashed reg_name <- (_unreserved / _pct / _subdelim)*
    \\port      <- _digit+
    \\path_abempty <- ('/' segment)*
    \\@squashed segment <- _pchar*
    \\query     <- (_pchar / '/' / '?')*
    \\fragment  <- (_pchar / '/' / '?')*
    \\@silent _pchar    <- _unreserved / _pct / _subdelim / ':' / '@'
    \\@silent _unreserved <- _alpha / _digit / '-' / '.' / '_' / '~'
    \\@silent _pct      <- '%' _hexdig _hexdig
    \\@silent _subdelim <- [!$&'()*+,;=]
    \\@silent _alpha    <- [a-zA-Z]
    \\@silent _digit    <- [0-9]
    \\@silent _hexdig   <- [0-9a-fA-F]
    \\@silent _decnum   <- [0-9]+
    \\@silent _ipvchar  <- [0-9a-fA-F:.]
);

fn expectFull(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try uri.parse(arena.allocator(), "uri", input);
    try std.testing.expect(result.pos == input.len);
    std.debug.print("  OK: {s}\n", .{input});
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (uri.parse(arena.allocator(), "uri", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
        std.debug.print("  PARTIAL: \"{s}\"\n", .{input});
    } else |_| {
        std.debug.print("  REJECTED: \"{s}\"\n", .{input});
    }
}

test "http basic" {
    std.debug.print("\n-- uri: http --\n", .{});
    try expectFull("http://example.com");
    try expectFull("https://example.com");
    try expectFull("http://www.example.com");
}

test "with path" {
    std.debug.print("\n-- uri: paths --\n", .{});
    try expectFull("http://example.com/");
    try expectFull("http://example.com/path");
    try expectFull("http://example.com/path/to/resource");
    try expectFull("http://example.com/a/b/c/d/e");
}

test "with port" {
    std.debug.print("\n-- uri: port --\n", .{});
    try expectFull("http://example.com:80");
    try expectFull("http://localhost:8080");
    try expectFull("http://example.com:443/path");
    try expectFull("https://example.com:3000/api");
}

test "with query" {
    std.debug.print("\n-- uri: query --\n", .{});
    try expectFull("http://example.com?q=hello");
    try expectFull("http://example.com/search?q=hello&lang=en");
    try expectFull("http://example.com/path?a=1&b=2&c=3");
    try expectFull("http://example.com?key=value");
}

test "with fragment" {
    std.debug.print("\n-- uri: fragment --\n", .{});
    try expectFull("http://example.com#section");
    try expectFull("http://example.com/page#top");
    try expectFull("http://example.com/path?q=1#result");
}

test "with userinfo" {
    std.debug.print("\n-- uri: userinfo --\n", .{});
    try expectFull("http://user@example.com");
    try expectFull("http://user:pass@example.com");
    try expectFull("ftp://admin:secret@ftp.example.com/files");
}

test "various schemes" {
    std.debug.print("\n-- uri: schemes --\n", .{});
    try expectFull("ftp://ftp.example.com/file");
    try expectFull("ssh://server.com");
    try expectFull("mailto://user@example.com");
    try expectFull("custom+scheme://host");
}

test "ip addresses" {
    std.debug.print("\n-- uri: IPs --\n", .{});
    try expectFull("http://192.168.1.1");
    try expectFull("http://127.0.0.1:8080");
    try expectFull("http://10.0.0.1/path");
    try expectFull("http://0.0.0.0:3000");
}

test "ipv6" {
    std.debug.print("\n-- uri: IPv6 --\n", .{});
    try expectFull("http://[::1]");
    try expectFull("http://[::1]:8080");
    try expectFull("http://[2001:db8::1]/path");
    try expectFull("http://[fe80::1]:443/secure");
}

test "percent encoding" {
    std.debug.print("\n-- uri: percent --\n", .{});
    try expectFull("http://example.com/path%20with%20spaces");
    try expectFull("http://example.com?q=hello%20world");
    try expectFull("http://user%40name@example.com");
}

test "complex uris" {
    std.debug.print("\n-- uri: complex --\n", .{});
    try expectFull("https://user:pass@example.com:8443/api/v1/users?active=true&role=admin#results");
    try expectFull("ftp://anonymous@ftp.example.com:21/pub/files/readme.txt");
    try expectFull("http://192.168.1.100:9090/dashboard?tab=overview#widgets");
}

test "tree structure" {
    std.debug.print("\n-- uri: tree --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try uri.parse(arena.allocator(), "uri", "https://user@example.com:443/path?q=1#top");
    peg.printTree(result.node, 2);

    var found_scheme = false;
    var found_authority = false;
    var found_path = false;
    var found_query = false;
    var found_fragment = false;
    for (result.node.children) |child| {
        if (std.mem.eql(u8, child.tag, "scheme")) found_scheme = true;
        if (std.mem.eql(u8, child.tag, "authority")) found_authority = true;
        if (std.mem.eql(u8, child.tag, "path_abempty")) found_path = true;
        if (std.mem.eql(u8, child.tag, "query")) found_query = true;
        if (std.mem.eql(u8, child.tag, "fragment")) found_fragment = true;
    }
    try std.testing.expect(found_scheme);
    try std.testing.expect(found_authority);
    try std.testing.expect(found_path);
    try std.testing.expect(found_query);
    try std.testing.expect(found_fragment);
    std.debug.print("  OK: all components found\n", .{});
}

test "invalid uris" {
    std.debug.print("\n-- uri: invalid --\n", .{});
    try expectFail("");
    try expectFail("not a uri");
    try expectFail("://missing.scheme");
    try expectFail("http//no-colon.com");
}