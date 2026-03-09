const std = @import("std");
const peg = @import("peg");

const json_grammar = peg.compile(
    \\value    <- _ws (object / array / string / number / bool / null) _ws
    \\object   <- '{' _ws (pair (_ws ',' _ws pair)*)? _ws '}'
    \\pair     <- string _ws ':' _ws value
    \\array    <- '[' _ws (value (_ws ',' _ws value)*)? _ws ']'
    \\string   <- '"' _strchar* '"'
    \\number   <- _minus? _int _frac? _exp?
    \\bool     <- 'true' / 'false'
    \\null     <- 'null'
    \\@silent _strchar <- _escaped / [^"\\]
    \\@silent _escaped <- '\\' ["\\/bfnrt]
    \\@silent _minus   <- '-'
    \\@silent _int     <- '0' / [1-9] [0-9]*
    \\@silent _frac    <- '.' [0-9]+
    \\@silent _exp     <- [eE] [+\-]? [0-9]+
    \\@silent _ws      <- [ \t\n\r]*
);

const expr_grammar = peg.compile(
    \\expr    <- _ws sum _ws
    \\sum     <- product (_ws op_add _ws product)*
    \\product <- atom (_ws op_mul _ws atom)*
    \\atom    <- number / '(' _ws expr _ws ')'
    \\number  <- [0-9]+
    \\op_add  <- '+' / '-'
    \\op_mul  <- '*' / '/'
    \\@silent _ws     <- [ \t]*
);

const python_expr_grammar = peg.compileWithOptions(
    \\start          <- expr
    \\expr           <- comparison
    \\comparison     <- additive (cmp_op additive)?
    \\cmp_op         <- '==' / '!=' / '<=' / '>=' / '<' / '>'
    \\additive       <- additive add_op multiplicative / multiplicative
    \\add_op         <- '+' / '-'
    \\multiplicative <- multiplicative mul_op unary / unary
    \\mul_op         <- '*' / '/' / '%'
    \\unary          <- ('+' / '-') unary / primary
    \\primary        <- number / ident / '(' expr ')'
    \\number         <- _digits ('.' _digits)?
    \\ident          <- _ident_start _ident_rest*
    \\@silent _ident_start   <- [a-zA-Z_]
    \\@silent _ident_rest    <- [a-zA-Z0-9_]
    \\@silent _digits        <- [0-9]+
    \\@silent _ws            <- [ \t\n\r]*
,
    .{ .left_recursion_mode = .rewrite },
);

const python_expr_memo_off_grammar = peg.compileWithOptions(
    \\start          <- expr
    \\expr           <- comparison
    \\comparison     <- additive (cmp_op additive)?
    \\cmp_op         <- '==' / '!=' / '<=' / '>=' / '<' / '>'
    \\additive       <- additive add_op multiplicative / multiplicative
    \\add_op         <- '+' / '-'
    \\multiplicative <- multiplicative mul_op unary / unary
    \\mul_op         <- '*' / '/' / '%'
    \\unary          <- ('+' / '-') unary / primary
    \\primary        <- number / ident / '(' expr ')'
    \\@memo_off number <- _digits ('.' _digits)?
    \\ident          <- _ident_start _ident_rest*
    \\@silent _ident_start   <- [a-zA-Z_]
    \\@silent _ident_rest    <- [a-zA-Z0-9_]
    \\@silent _digits        <- [0-9]+
    \\@silent _ws            <- [ \t\n\r]*
,
    .{ .left_recursion_mode = .rewrite },
);

const graphql_grammar = peg.compile(
    \\document        <- _ws definition+ _ws
    \\definition      <- operation_def / fragment_def
    \\operation_def   <- selection_set / operation_type name? variable_defs? directives? selection_set
    \\operation_type  <- 'query' / 'mutation' / 'subscription'
    \\fragment_def    <- 'fragment' _req_ws name _req_ws 'on' _req_ws type_name directives? selection_set
    \\selection_set   <- '{' selection+ '}'
    \\selection       <- field / fragment_spread / inline_fragment
    \\field           <- alias? name arguments? directives? selection_set?
    \\alias           <- name ':'
    \\arguments       <- '(' argument* ')'
    \\argument        <- name ':' value
    \\fragment_spread <- '...' name directives?
    \\inline_fragment <- '...' ('on' _req_ws type_name)? directives? selection_set
    \\directives      <- directive+
    \\directive       <- '@' name arguments?
    \\variable_defs   <- '(' variable_def* ')'
    \\variable_def    <- variable ':' type_ref default_value?
    \\default_value   <- '=' value
    \\type_ref        <- non_null_type / list_type / named_type
    \\named_type      <- name
    \\list_type       <- '[' type_ref ']'
    \\non_null_type   <- (named_type / list_type) '!'
    \\type_name       <- name
    \\value           <- variable / float / int / string / bool / null / enum / list / object
    \\variable        <- '$' name
    \\list            <- '[' value* ']'
    \\object          <- '{' object_field* '}'
    \\object_field    <- name ':' value
    \\bool           <- 'true' / 'false'
    \\null           <- 'null'
    \\enum           <- [A-Za-z_][A-Za-z0-9_]*
    \\int            <- '-'? [0-9]+
    \\float          <- '-'? [0-9]+ '.' [0-9]+ (_exp)?
    \\@silent _exp            <- [eE] [+\-]? [0-9]+
    \\string         <- '"' _str_char* '"'
    \\@silent _str_char       <- '\\' . / [^"\\]
    \\name           <- [A-Za-z_][A-Za-z0-9_]*
    \\@silent _req_ws        <- ([ \t\r\n,] / comment)+
    \\@silent _ws             <- ([ \t\r\n,] / comment)*
    \\comment         <- '#' [^\n]*
);

const http_grammar = peg.compile(
    \\message        <- request / response
    \\request        <- request_line headers _nl body?
    \\request_line   <- method _sp request_target _sp http_version _nl
    \\response       <- status_line headers _nl body?
    \\status_line    <- http_version _sp status_code _sp reason_phrase _nl
    \\headers        <- header*
    \\header         <- field_name ':' _ows field_value _nl
    \\field_name     <- [A-Za-z0-9\-]+
    \\field_value    <- [^\r\n]*
    \\method         <- [A-Z]+
    \\request_target <- [^ \r\n]+
    \\http_version   <- 'HTTP/' [0-9]+ '.' [0-9]+
    \\status_code    <- [0-9] [0-9] [0-9]
    \\reason_phrase  <- [^\r\n]+
    \\body           <- [\x00-\xFF]*
    \\@silent _sp            <- ' '+
    \\@silent _ows           <- ' '*
    \\@silent _nl            <- '\r\n' / '\n'
);

const BenchCase = struct {
    name: []const u8,
    filter_tag: CaseFilter,
    grammar: peg.Grammar,
    start: []const u8,
    input: []const u8,
    validator: ?*const fn ([]const u8) anyerror!void = null,
};

const BenchRow = struct {
    mode: []const u8,
    avg_us: f64,
    memo_entries: usize,
    memo_hits: usize,
    memo_misses: usize,
    pool_entries: usize,
};

const CaseFilter = enum {
    all,
    json,
    expr,
    graphql,
    http,
    strict,
};

const OutputFormat = enum {
    text,
    csv,
};

const BenchConfig = struct {
    runs: usize = 20,
    filter: CaseFilter = .all,
    format: OutputFormat = .text,
    output_path: ?[]u8 = null,
};

fn runBenchCase(
    allocator: std.mem.Allocator,
    case: BenchCase,
    mode_label: []const u8,
    mode: peg.MemoMode,
    full: bool,
    runs: usize,
) !BenchRow {
    var total_ns: u128 = 0;
    var last_stats: peg.ParseStats = .{};

    for (0..runs) |_| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var stats: peg.ParseStats = .{};

        var timer = try std.time.Timer.start();
        _ = try case.grammar.parseWithOptions(
            arena.allocator(),
            case.start,
            case.input,
            .{
                .consume_mode = if (full) .full else .partial,
                .memo_mode = mode,
                .stats = &stats,
            },
        );
        if (case.validator) |v| try v(case.input);
        total_ns += timer.read();
        last_stats = stats;
    }

    return .{
        .mode = mode_label,
        .avg_us = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(runs)) / 1_000.0,
        .memo_entries = last_stats.memo_entries,
        .memo_hits = last_stats.memo_hits,
        .memo_misses = last_stats.memo_misses,
        .pool_entries = last_stats.pool_entries,
    };
}

fn printRowText(writer: anytype, row: BenchRow) !void {
    try writer.print(
        "| {s: <16} | {d: >12.2} | {d: >8} | {d: >8} | {d: >10} | {d: >8} |\n",
        .{
            row.mode,
            row.avg_us,
            row.memo_entries,
            row.memo_hits,
            row.memo_misses,
            row.pool_entries,
        },
    );
}

fn speedupPercent(baseline_us: f64, candidate_us: f64) f64 {
    if (candidate_us <= 0.0) return 0.0;
    return ((baseline_us / candidate_us) - 1.0) * 100.0;
}

fn printRowCsv(writer: anytype, case_name: []const u8, row: BenchRow, speedup_percent: f64) !void {
    try writer.print(
        "{s},{s},{d:.2},{d},{d},{d},{d},{d:.2}\n",
        .{
            case_name,
            row.mode,
            row.avg_us,
            row.memo_entries,
            row.memo_hits,
            row.memo_misses,
            row.pool_entries,
            speedup_percent,
        },
    );
}

fn benchCase(
    writer: anytype,
    allocator: std.mem.Allocator,
    case: BenchCase,
    runs: usize,
    format: OutputFormat,
) !void {
    if (format == .text) {
        try writer.print("\n## {s}\n", .{case.name});
        try writer.writeAll("| Mode             | avg us/run   | memo ent | memo hit | memo miss  | pool ent |\n");
        try writer.writeAll("|------------------|--------------|----------|----------|------------|----------|\n");
    }

    const row_parse_on = try runBenchCase(allocator, case, "parse + memo on", .on, false, runs);
    const row_parse_off = try runBenchCase(allocator, case, "parse + memo off", .off, false, runs);
    const row_all_on = try runBenchCase(allocator, case, "full + memo on", .on, true, runs);
    const row_all_off = try runBenchCase(allocator, case, "full + memo off", .off, true, runs);

    const parse_speedup = speedupPercent(row_parse_on.avg_us, row_parse_off.avg_us);
    const parse_all_speedup = speedupPercent(row_all_on.avg_us, row_all_off.avg_us);

    switch (format) {
        .text => {
            try printRowText(writer, row_parse_on);
            try printRowText(writer, row_parse_off);
            try printRowText(writer, row_all_on);
            try printRowText(writer, row_all_off);
            try writer.print(
                "Speedup memo off: parse={d:.2}%, full={d:.2}%\n",
                .{ parse_speedup, parse_all_speedup },
            );
        },
        .csv => {
            try printRowCsv(writer, case.name, row_parse_on, 0.0);
            try printRowCsv(writer, case.name, row_parse_off, parse_speedup);
            try printRowCsv(writer, case.name, row_all_on, 0.0);
            try printRowCsv(writer, case.name, row_all_off, parse_all_speedup);
        },
    }
}

fn buildJsonInput(allocator: std.mem.Allocator) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer list.deinit(allocator);
    try list.appendSlice(allocator, "{\"users\":[");
    for (0..120) |i| {
        if (i != 0) try list.appendSlice(allocator, ",");
        try list.writer(allocator).print(
            "{{\"id\":{},\"name\":\"user{}\",\"active\":true,\"score\":{}.{} }}",
            .{ i, i, i * 17, i % 10 },
        );
    }
    try list.appendSlice(allocator, "],\"meta\":{\"page\":1,\"total\":120,\"ok\":true}}");
    return list.toOwnedSlice(allocator);
}

fn buildExprInput(allocator: std.mem.Allocator) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer list.deinit(allocator);
    for (0..500) |i| {
        if (i != 0) try list.appendSlice(allocator, " + ");
        try list.writer(allocator).print("({}*{}-{})", .{ i + 3, i % 11 + 1, i % 7 });
    }
    return list.toOwnedSlice(allocator);
}

fn buildPythonExprInput(allocator: std.mem.Allocator) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer list.deinit(allocator);
    try list.appendSlice(allocator, "x0");
    for (0..280) |i| {
        const op = switch (i % 3) {
            0 => " + ",
            1 => " - ",
            else => " * ",
        };
        try list.appendSlice(allocator, op);
        if (i % 2 == 0) {
            try list.writer(allocator).print("({} + y{})", .{ i + 3, i % 17 });
        } else {
            try list.writer(allocator).print("n{}%{}", .{ i % 31, i % 7 + 2 });
        }
    }
    try list.appendSlice(allocator, " >= threshold");
    return list.toOwnedSlice(allocator);
}

fn buildGraphqlInput(allocator: std.mem.Allocator) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer list.deinit(allocator);
    try list.appendSlice(allocator, "query Feed($limit: Int = 50) { feed(limit: $limit) { ");
    for (0..120) |i| {
        try list.writer(allocator).print("f{}: user{} {{ id name score posts {{ id title }} }} ", .{ i, i });
    }
    try list.appendSlice(allocator, "} }");
    return list.toOwnedSlice(allocator);
}

fn buildHttpInput(allocator: std.mem.Allocator) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer list.deinit(allocator);
    try list.appendSlice(allocator, "POST /api/bulk HTTP/1.1\r\n");
    try list.appendSlice(allocator, "Host: benchmark.local\r\n");
    try list.appendSlice(allocator, "User-Agent: peg-bench/1.0\r\n");
    try list.appendSlice(allocator, "Content-Type: application/json\r\n");
    try list.appendSlice(allocator, "Accept: */*\r\n");
    try list.appendSlice(allocator, "X-Trace: abcdef123456\r\n");
    var body = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"items\":[");
    for (0..160) |i| {
        if (i != 0) try body.appendSlice(allocator, ",");
        try body.writer(allocator).print("{{\"id\":{},\"name\":\"n{}\"}}", .{ i, i });
    }
    try body.appendSlice(allocator, "]}");
    try list.writer(allocator).print("Content-Length: {}\r\n", .{body.items.len});
    try list.appendSlice(allocator, "\r\n");
    try list.appendSlice(allocator, body.items);
    return list.toOwnedSlice(allocator);
}

fn validateGraphqlStrict(input: []const u8) !void {
    // Strict profile check: reserved introspection prefix "__" is forbidden.
    if (std.mem.indexOf(u8, input, "__") != null) return error.StrictValidationFailed;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
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

fn validateHttpStrict(input: []const u8) !void {
    const header_end_crlf = std.mem.indexOf(u8, input, "\r\n\r\n");
    const header_end_lf = std.mem.indexOf(u8, input, "\n\n");
    const header_end = if (header_end_crlf) |p|
        p
    else if (header_end_lf) |p|
        p
    else
        return error.StrictValidationFailed;

    const header_block = input[0..header_end];
    const start_line = if (std.mem.indexOf(u8, header_block, "\r\n")) |p|
        header_block[0..p]
    else if (std.mem.indexOfScalar(u8, header_block, '\n')) |p|
        header_block[0..p]
    else
        header_block;
    if (std.mem.indexOf(u8, start_line, "HTTP/1.0") == null and std.mem.indexOf(u8, start_line, "HTTP/1.1") == null) {
        return error.StrictValidationFailed;
    }

    var has_content_length = false;
    var has_chunked = false;
    if (std.mem.indexOf(u8, header_block, "\r\n") != null) {
        var it = std.mem.splitSequence(u8, header_block, "\r\n");
        _ = it.next();
        while (it.next()) |line| {
            if (line.len == 0) break;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const key = std.mem.trim(u8, line[0..colon], " \t");
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (eqlIgnoreCase(key, "content-length")) {
                has_content_length = true;
                _ = std.fmt.parseInt(usize, value, 10) catch return error.StrictValidationFailed;
            } else if (eqlIgnoreCase(key, "transfer-encoding")) {
                if (containsChunkedIgnoreCase(value)) has_chunked = true;
            }
        }
    } else {
        var it = std.mem.splitScalar(u8, header_block, '\n');
        _ = it.next();
        while (it.next()) |line| {
            if (line.len == 0) break;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const key = std.mem.trim(u8, line[0..colon], " \t");
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (eqlIgnoreCase(key, "content-length")) {
                has_content_length = true;
                _ = std.fmt.parseInt(usize, value, 10) catch return error.StrictValidationFailed;
            } else if (eqlIgnoreCase(key, "transfer-encoding")) {
                if (containsChunkedIgnoreCase(value)) has_chunked = true;
            }
        }
    }
    if (has_content_length and has_chunked) return error.StrictValidationFailed;
}

fn parseArgs(allocator: std.mem.Allocator) !BenchConfig {
    var cfg: BenchConfig = .{};
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--runs")) {
            if (i + 1 >= args.len) return error.InvalidArguments;
            cfg.runs = try std.fmt.parseInt(usize, args[i + 1], 10);
            if (cfg.runs == 0) return error.InvalidArguments;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--case")) {
            if (i + 1 >= args.len) return error.InvalidArguments;
            const v = args[i + 1];
            cfg.filter = if (std.mem.eql(u8, v, "all"))
                .all
            else if (std.mem.eql(u8, v, "json"))
                .json
            else if (std.mem.eql(u8, v, "expr"))
                .expr
            else if (std.mem.eql(u8, v, "graphql"))
                .graphql
            else if (std.mem.eql(u8, v, "http"))
                .http
            else if (std.mem.eql(u8, v, "strict"))
                .strict
            else
                return error.InvalidArguments;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--format")) {
            if (i + 1 >= args.len) return error.InvalidArguments;
            const v = args[i + 1];
            cfg.format = if (std.mem.eql(u8, v, "text"))
                .text
            else if (std.mem.eql(u8, v, "csv"))
                .csv
            else
                return error.InvalidArguments;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--output")) {
            if (i + 1 >= args.len) return error.InvalidArguments;
            cfg.output_path = try allocator.dupe(u8, args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.ShowUsage;
        } else {
            return error.InvalidArguments;
        }
    }
    return cfg;
}

fn printUsage() void {
    std.debug.print(
        \\Usage:
        \\  zig build bench -- [--runs N] [--case all|json|expr|graphql|http|strict] [--format text|csv] [--output file]
        \\
        \\Examples:
        \\  zig build bench
        \\  zig build bench -- --runs 50
        \\  zig build bench -- --case json --runs 30
        \\  zig build bench -- --case graphql --runs 30
        \\  zig build bench -- --case strict --runs 30
        \\  zig build bench -- --format csv
        \\  zig build bench -- --format csv --output bench.csv
        \\
    , .{});
}

fn writeAllBench(writer: anytype, allocator: std.mem.Allocator, cfg: BenchConfig, cases: []const BenchCase) !void {
    if (cfg.format == .text) {
        try writer.writeAll("# PEG microbench\n");
        try writer.print("Averages are measured over {} runs per mode.\n", .{cfg.runs});
    } else {
        try writer.writeAll("case,mode,avg_us,memo_entries,memo_hits,memo_misses,pool_entries,speedup_percent_vs_memo_on\n");
    }

    for (cases) |c| {
        switch (cfg.filter) {
            .all => {},
            .json => if (c.filter_tag != .json) continue,
            .expr => if (c.filter_tag != .expr) continue,
            .graphql => if (c.filter_tag != .graphql) continue,
            .http => if (c.filter_tag != .http) continue,
            .strict => if (c.filter_tag != .strict) continue,
        }
        try benchCase(writer, allocator, c, cfg.runs, cfg.format);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cfg = parseArgs(allocator) catch |err| switch (err) {
        error.ShowUsage => {
            printUsage();
            return;
        },
        error.InvalidArguments => {
            printUsage();
            return error.InvalidArguments;
        },
        else => return err,
    };
    defer if (cfg.output_path) |p| allocator.free(p);

    const json_input = try buildJsonInput(allocator);
    defer allocator.free(json_input);
    const expr_input = try buildExprInput(allocator);
    defer allocator.free(expr_input);
    const python_expr_input = try buildPythonExprInput(allocator);
    defer allocator.free(python_expr_input);
    const graphql_input = try buildGraphqlInput(allocator);
    defer allocator.free(graphql_input);
    const http_input = try buildHttpInput(allocator);
    defer allocator.free(http_input);

    const cases = [_]BenchCase{
        .{
            .name = "JSON value",
            .filter_tag = .json,
            .grammar = json_grammar,
            .start = "value",
            .input = json_input,
        },
        .{
            .name = "Arithmetic expr",
            .filter_tag = .expr,
            .grammar = expr_grammar,
            .start = "expr",
            .input = expr_input,
        },
        .{
            .name = "Python-like expr",
            .filter_tag = .expr,
            .grammar = python_expr_grammar,
            .start = "start",
            .input = python_expr_input,
        },
        .{
            .name = "Python-like expr (@memo_off number)",
            .filter_tag = .expr,
            .grammar = python_expr_memo_off_grammar,
            .start = "start",
            .input = python_expr_input,
        },
        .{
            .name = "GraphQL document",
            .filter_tag = .graphql,
            .grammar = graphql_grammar,
            .start = "document",
            .input = graphql_input,
        },
        .{
            .name = "GraphQL strict profile",
            .filter_tag = .strict,
            .grammar = graphql_grammar,
            .start = "document",
            .input = graphql_input,
            .validator = validateGraphqlStrict,
        },
        .{
            .name = "HTTP message",
            .filter_tag = .http,
            .grammar = http_grammar,
            .start = "message",
            .input = http_input,
        },
        .{
            .name = "HTTP strict profile",
            .filter_tag = .strict,
            .grammar = http_grammar,
            .start = "message",
            .input = http_input,
            .validator = validateHttpStrict,
        },
    };

    var out_buf = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer out_buf.deinit(allocator);
    try writeAllBench(out_buf.writer(allocator), allocator, cfg, &cases);

    if (cfg.output_path) |out| {
        const file = try std.fs.cwd().createFile(out, .{ .truncate = true });
        defer file.close();
        try file.writeAll(out_buf.items);
    } else {
        std.debug.print("{s}", .{out_buf.items});
    }
}
