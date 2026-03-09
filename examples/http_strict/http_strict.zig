const std = @import("std");
const peg = @import("peg");

// HTTP strict profile:
// - start line + headers + optional body
// - post-parse semantic checks:
//   * HTTP version must be 1.0 or 1.1
//   * Content-Length must be numeric
//   * Content-Length and Transfer-Encoding: chunked can't be combined
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

const StrictError = error{
    ParseFailed,
    InvalidHttpVersion,
    InvalidContentLength,
    ConflictingBodyHeaders,
};

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (std.ascii.toLower(a[i]) != std.ascii.toLower(b[i])) return false;
    }
    return true;
}

fn containsChunkedIgnoreCase(value: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, value, ", \t");
    while (it.next()) |tok| {
        if (eqlIgnoreCase(tok, "chunked")) return true;
    }
    return false;
}

fn parseStrictMessage(allocator: std.mem.Allocator, input: []const u8) StrictError!peg.ParseSuccess {
    const res = http.parse(allocator, "message", input) catch return error.ParseFailed;
    errdefer peg.freeNode(allocator, res.node);
    try validateSemantics(input);
    return res;
}

fn validateSemantics(input: []const u8) StrictError!void {
    const header_end_crlf = std.mem.indexOf(u8, input, "\r\n\r\n");
    const header_end_lf = std.mem.indexOf(u8, input, "\n\n");
    const header_end = if (header_end_crlf) |p|
        p
    else if (header_end_lf) |p|
        p
    else
        return error.ParseFailed;

    const header_block = input[0..header_end];
    const start_line = if (std.mem.indexOf(u8, header_block, "\r\n")) |p|
        header_block[0..p]
    else if (std.mem.indexOfScalar(u8, header_block, '\n')) |p|
        header_block[0..p]
    else
        header_block;
    if (std.mem.indexOf(u8, start_line, "HTTP/1.0") == null and std.mem.indexOf(u8, start_line, "HTTP/1.1") == null) {
        return error.InvalidHttpVersion;
    }

    var has_content_length = false;
    var has_chunked = false;

    if (std.mem.indexOf(u8, header_block, "\r\n") != null) {
        var it = std.mem.splitSequence(u8, header_block, "\r\n");
        _ = it.next(); // start-line
        while (it.next()) |line| {
            if (line.len == 0) break;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const key = std.mem.trim(u8, line[0..colon], " \t");
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");

            if (eqlIgnoreCase(key, "content-length")) {
                has_content_length = true;
                _ = std.fmt.parseInt(usize, value, 10) catch return error.InvalidContentLength;
            } else if (eqlIgnoreCase(key, "transfer-encoding")) {
                if (containsChunkedIgnoreCase(value)) has_chunked = true;
            }
        }
    } else {
        var it = std.mem.splitScalar(u8, header_block, '\n');
        _ = it.next(); // start-line
        while (it.next()) |line| {
            if (line.len == 0) break;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const key = std.mem.trim(u8, line[0..colon], " \t");
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");

            if (eqlIgnoreCase(key, "content-length")) {
                has_content_length = true;
                _ = std.fmt.parseInt(usize, value, 10) catch return error.InvalidContentLength;
            } else if (eqlIgnoreCase(key, "transfer-encoding")) {
                if (containsChunkedIgnoreCase(value)) has_chunked = true;
            }
        }
    }

    if (has_content_length and has_chunked) return error.ConflictingBodyHeaders;
}

fn expectParseStrict(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const res = try parseStrictMessage(arena.allocator(), input);
    peg.freeNode(arena.allocator(), res.node);
}

fn expectStrictFail(input: []const u8, expected: StrictError) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (parseStrictMessage(arena.allocator(), input)) |res| {
        peg.freeNode(arena.allocator(), res.node);
        return error.ShouldHaveFailed;
    } else |err| {
        try std.testing.expectEqual(expected, err);
    }
}

test "http strict accepts valid messages" {
    try expectParseStrict("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n");
    try expectParseStrict("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello");
    try expectParseStrict("POST /x HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n4\r\ntest\r\n0\r\n\r\n");
}

test "http strict invalid version" {
    try expectStrictFail("GET / HTTP/2.0\r\nHost: x\r\n\r\n", error.InvalidHttpVersion);
    try expectStrictFail("HTTP/9.9 200 OK\r\n\r\n", error.InvalidHttpVersion);
}

test "http strict invalid content length" {
    try expectStrictFail("HTTP/1.1 200 OK\r\nContent-Length: nope\r\n\r\n", error.InvalidContentLength);
}

test "http strict conflicting body headers" {
    try expectStrictFail("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\nhello", error.ConflictingBodyHeaders);
}
