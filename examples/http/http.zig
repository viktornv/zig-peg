const std = @import("std");
const peg = @import("peg");

// Practical HTTP/1.x parser:
// - request/response start lines
// - headers
// - optional message body
const http = peg.compile(
    \\message        <- request / response
    \\
    \\@squashed request <- request_line headers _nl body?
    \\request_line   <- method _sp request_target _sp http_version _nl
    \\
    \\@squashed response <- status_line headers _nl body?
    \\@squashed status_line <- http_version _sp status_code _sp reason_phrase _nl
    \\
    \\@squashed headers <- header*
    \\header         <- field_name ':' _ows field_value _nl
    \\field_name    <- ~"[A-Za-z0-9-]+"
    \\field_value   <- ~"[^\r\n]*"
    \\
    \\method        <- ~"[A-Z]+"
    \\request_target <- ~"[^ \r\n]+"
    \\http_version  <- ~"HTTP/[0-9]+[.][0-9]+"
    \\status_code   <- ~"[0-9]{3}"
    \\reason_phrase <- ~"[^\r\n]+"
    \\body          <- ~"[\x00-\xFF]*"
    \\
    \\@silent _sp            <- ' '+
    \\@silent _ows           <- ' '*
    \\@silent _nl            <- '\r\n' / '\n'
);

fn expectParseAll(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try http.parse(arena.allocator(), "message", input);
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (http.parse(arena.allocator(), "message", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
    } else |_| {}
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var count: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) count += 1;
    for (node.children) |child| count += countTag(child, tag);
    return count;
}

test "http requests" {
    try expectParseAll("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n");
    try expectParseAll("POST /api/items HTTP/1.1\r\nHost: api.local\r\nContent-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"a\":1,\"b\":2}");
    try expectParseAll("DELETE /v1/users/42 HTTP/1.0\nHost: localhost\n\n");
}

test "http responses" {
    try expectParseAll("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello");
    try expectParseAll("HTTP/1.0 404 Not Found\r\nServer: test\r\n\r\n");
    try expectParseAll("HTTP/1.1 500 Internal Server Error\nContent-Type: text/plain\n\nboom");
}

test "http headers and whitespace" {
    try expectParseAll("GET /x HTTP/1.1\r\nX-Test: value\r\nX-Empty:\r\nX-Spaces:   value with spaces\r\n\r\n");
    try expectParseAll("HTTP/1.1 204 No Content\r\nDate: Sat, 07 Mar 2026 10:00:00 GMT\r\n\r\n");
}

test "http invalid cases" {
    try expectFail("");
    try expectFail("GET / HTTP/1.1\r\nHost: example.com\r\n"); // no empty line
    try expectFail("GET / HTTP/1.1\r\nBad Header\r\n\r\n");
    try expectFail("HTTP/1.1 OK\r\n\r\n");
    try expectFail("GET  HTTP/1.1\r\n\r\n");
    try expectFail("http/1.1 200 OK\r\n\r\n");
}

test "http tree structure smoke" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const input = "GET /api?q=zig HTTP/1.1\r\nHost: example.com\r\nAccept: */*\r\n\r\n";
    const res = try http.parse(arena.allocator(), "message", input);

    try std.testing.expectEqualStrings("message", res.node.tag);
    try std.testing.expect(countTag(res.node, "request_line") >= 1);
    try std.testing.expect(countTag(res.node, "header") == 2);
    try std.testing.expect(countTag(res.node, "method") == 1);
}
