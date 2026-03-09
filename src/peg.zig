const std = @import("std");

// --- Public Types ---

pub const Node = struct {
    // `tag` points into comptime grammar storage.
    tag: []const u8,
    // `text` points into the original input slice passed to `parse`.
    text: []const u8,
    // Owned heap allocation; free with `freeNode`.
    children: []const Node,
};

pub const ParseSuccess = struct {
    // Caller owns `node.children` allocations and should release with `freeNode`.
    node: Node,
    pos: usize,
};

pub const ParseDetailedResult = union(enum) {
    ok: ParseSuccess,
    err: DetailedError,
};

pub const ParseError = struct {
    pos: usize,
    expected: []const u8,
    expected_count: u8 = 0,
    expected_items: [5][]const u8 = [_][]const u8{ "", "", "", "", "" },
    expected_truncated: bool = false,
};

pub const DetailedError = struct {
    class: ParseErrorClass,
    pos: usize,
    line: usize,
    col: usize,
    expected: []const u8,
    expected_count: u8,
    expected_items: [5][]const u8,
    expected_truncated: bool = false,
    context: []const u8,
    context_prev: []const u8,
    context_next: []const u8,

    pub fn format(self: DetailedError, writer: anytype) !void {
        try writer.print(
            "Parse error ({s}) at line {}:{} - expected ",
            .{ @tagName(self.class), self.line, self.col },
        );
        if (self.expected_count > 1) {
            var i: usize = 0;
            while (i < self.expected_count) : (i += 1) {
                if (i != 0) try writer.writeAll(" / ");
                try writeEscapedExpected(writer, self.expected_items[i]);
            }
            if (self.expected_truncated) try writer.writeAll(" / ...");
        } else {
            try writeEscapedExpected(writer, self.expected);
        }
        if (self.context.len > 0) {
            if (self.context_prev.len > 0) try writer.print("\n  | {s}", .{self.context_prev});
            try writer.print("\n  | {s}", .{self.context});
            try writer.print("\n  | ", .{});
            for (0..self.col -| 1) |_| try writer.print(" ", .{});
            try writer.print("^", .{});
            if (self.context_next.len > 0) try writer.print("\n  | {s}", .{self.context_next});
        }
    }

    pub fn formatAlloc(self: DetailedError, allocator: std.mem.Allocator) ![]const u8 {
        var buf = try std.ArrayList(u8).initCapacity(allocator, 0);
        defer buf.deinit(allocator);
        try self.format(buf.writer(allocator));
        return try buf.toOwnedSlice(allocator);
    }
};

pub const EngineError = error{
    StartRuleNotFound,
    ParseFailed,
    OutOfMemory,
};

pub const ParseErrorClass = enum {
    syntax,
    start_rule,
    oom,
    internal,
};

pub const MemoMode = enum {
    on,
    off,
};

pub const ConsumeMode = enum {
    full,
    partial,
};

pub const ParseStats = struct {
    memo_hits: usize = 0,
    memo_misses: usize = 0,
    memo_puts: usize = 0,
    memo_entries: usize = 0,
    pool_entries: usize = 0,
    materialized_nodes: usize = 0,
};

pub const ParseOptions = struct {
    consume_mode: ConsumeMode = .full,
    memo_mode: MemoMode = .on,
    stats: ?*ParseStats = null,
    trace: bool = false,
    trace_buffer: ?*std.ArrayListUnmanaged(u8) = null,
    max_recursion_depth: usize = 4096,
};

pub const LintMode = enum {
    off,
    warn,
    strict,
};

pub const LeftRecursionMode = enum {
    off,
    lint,
    rewrite,
};

pub const CompileOptions = struct {
    lint_mode: LintMode = .off,
    left_recursion_mode: LeftRecursionMode = .off,
};

pub const LintKind = enum {
    unused_rule,
    unreachable_rule,
    nullable_rule,
    suspicious_choice_order,
    direct_left_recursion,
};

pub const LintDiagnostic = struct {
    kind: LintKind,
    rule: []const u8,
    message: []const u8,
};

// --- Rule Types ---

pub const Rule = union(enum) {
    literal: []const u8,
    literal_ic: []const u8, // case-insensitive
    char_class: []const CharRange,
    neg_char_class: []const CharRange,
    dot,
    sequence: []const Rule,
    choice: []const Rule,
    zero_or_more: []const Rule, // exactly one inner rule
    one_or_more: []const Rule, // exactly one inner rule
    optional: []const Rule, // exactly one inner rule
    repeat_range: RepeatRange,
    not: []const Rule, // exactly one inner rule
    amp: []const Rule, // exactly one inner rule
    ref: u16,
};

pub const RepeatRange = struct {
    rule: []const Rule, // exactly one inner rule
    min: u16,
    max: u16, // 0 = unlimited
};

pub const CharRange = struct {
    lo: u8,
    hi: u8,
};

pub const NamedRule = struct {
    name: []const u8,
    rule: Rule,
    silent: bool,
    squashed: bool,
    memo_mode: MemoModeOverride,
};

pub const MemoModeOverride = enum {
    inherit,
    on,
    off,
};

// --- Internal ---

const ParseOk = struct {
    pos: usize,
    nodes: NodeList,
};

const ParseResult = union(enum) {
    ok: ParseOk,
    err: ParseError,
};

const NodeList = struct {
    indices: std.ArrayListUnmanaged(u32) = .{},

    fn append(self: *NodeList, allocator: std.mem.Allocator, idx: u32) !void {
        try self.indices.append(allocator, idx);
    }

    fn appendSlice(self: *NodeList, allocator: std.mem.Allocator, other: NodeList) !void {
        try self.indices.appendSlice(allocator, other.indices.items);
    }

    fn empty() NodeList {
        return .{};
    }

    fn deinit(self: *NodeList, allocator: std.mem.Allocator) void {
        self.indices.deinit(allocator);
    }
};

const PoolEntry = struct {
    tag: []const u8,
    text: []const u8,
    child_indices: []const u32,
};

const NodePool = struct {
    entries: std.ArrayListUnmanaged(PoolEntry),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) NodePool {
        return .{ .entries = .{}, .allocator = allocator };
    }

    fn deinit(self: *NodePool) void {
        for (self.entries.items) |entry| {
            if (entry.child_indices.len > 0) {
                self.allocator.free(entry.child_indices);
            }
        }
        self.entries.deinit(self.allocator);
    }

    fn add(self: *NodePool, tag: []const u8, text: []const u8, child_indices: []const u32) !u32 {
        const idx: u32 = @intCast(self.entries.items.len);
        try self.entries.append(self.allocator, .{
            .tag = tag,
            .text = text,
            .child_indices = child_indices,
        });
        return idx;
    }

    fn materialize(self: *NodePool, idx: u32) !Node {
        const entry = self.entries.items[idx];
        var children: []const Node = &.{};
        if (entry.child_indices.len > 0) {
            const child_slice = try self.allocator.alloc(Node, entry.child_indices.len);
            var built: usize = 0;
            errdefer {
                var i: usize = 0;
                while (i < built) : (i += 1) {
                    freeNode(self.allocator, child_slice[i]);
                }
                self.allocator.free(child_slice);
            }
            for (entry.child_indices, 0..) |ci, i| {
                child_slice[i] = try self.materialize(ci);
                built = i + 1;
            }
            children = child_slice;
        }
        return Node{
            .tag = entry.tag,
            .text = entry.text,
            .children = children,
        };
    }
};

// --- Comptime PEG Compiler ---

pub fn compile(comptime source: []const u8) Grammar {
    return compileWithOptions(source, .{});
}

pub fn compileWithOptions(comptime source: []const u8, comptime options: CompileOptions) Grammar {
    comptime {
        @setEvalBranchQuota(1_000_000);
        const parsed = parseGrammarComptime(source);
        const grammar = switch (options.left_recursion_mode) {
            .rewrite => Grammar{ .rules = rewriteDirectLeftRecursionLite(parsed.rules) },
            else => parsed,
        };
        runGrammarLint(grammar.rules, options);
        return grammar;
    }
}

pub fn lint(comptime source: []const u8) []const LintDiagnostic {
    comptime {
        @setEvalBranchQuota(1_000_000);
        const grammar = parseGrammarComptime(source);
        return collectGrammarLint(grammar.rules);
    }
}

pub const Grammar = struct {
    rules: []const NamedRule,

    pub fn parse(self: Grammar, allocator: std.mem.Allocator, start: []const u8, input: []const u8) EngineError!ParseSuccess {
        return self.parseWithOptions(allocator, start, input, .{});
    }

    pub fn parseWithOptions(
        self: Grammar,
        allocator: std.mem.Allocator,
        start: []const u8,
        input: []const u8,
        options: ParseOptions,
    ) EngineError!ParseSuccess {
        const start_idx = self.findRuleIndex(start) orelse return error.StartRuleNotFound;
        var engine = Engine.init(self.rules, allocator, options);
        defer engine.deinit();
        const res = try engine.parse(start_idx, input);
        if (options.consume_mode == .partial) return res;
        if (res.pos != input.len) {
            freeNode(allocator, res.node);
            return error.ParseFailed;
        }
        return res;
    }

    pub fn parseDetailed(self: Grammar, allocator: std.mem.Allocator, start: []const u8, input: []const u8) ParseDetailedResult {
        return self.parseDetailedWithOptions(allocator, start, input, .{});
    }

    pub fn parseDetailedWithOptions(
        self: Grammar,
        allocator: std.mem.Allocator,
        start: []const u8,
        input: []const u8,
        options: ParseOptions,
    ) ParseDetailedResult {
        const start_idx = self.findRuleIndex(start) orelse return .{ .err = .{
            .class = .start_rule,
            .pos = 0,
            .line = 1,
            .col = 1,
            .expected = "valid start rule",
            .expected_count = 1,
            .expected_items = [_][]const u8{ "valid start rule", "", "", "", "" },
            .expected_truncated = false,
            .context = "",
            .context_prev = "",
            .context_next = "",
        } };
        var engine = Engine.init(self.rules, allocator, options);
        defer engine.deinit();
        const res = engine.parseInner(start_idx, input) catch |err| {
            const err_pos = engine.farthest_pos;
            const lc = computeLineCol(input, err_pos);
            const snippet = getContextSnippet(input, err_pos);
            const expected = switch (err) {
                error.OutOfMemory => "out of memory",
                else => "internal parser error",
            };
            return .{ .err = .{
                .class = switch (err) {
                    error.OutOfMemory => .oom,
                    else => .internal,
                },
                .pos = err_pos,
                .line = lc.line,
                .col = lc.col,
                .expected = expected,
                .expected_count = 1,
                .expected_items = [_][]const u8{ expected, "", "", "", "" },
                .expected_truncated = false,
                .context = snippet.line,
                .context_prev = snippet.prev,
                .context_next = snippet.next,
            } };
        };
        switch (res) {
            .ok => |ok| {
                if (options.consume_mode == .partial) return .{ .ok = ok };
                if (ok.pos == input.len) return .{ .ok = ok };
                freeNode(allocator, ok.node);
                const lc = computeLineCol(input, ok.pos);
                const snippet = getContextSnippet(input, ok.pos);
                return .{ .err = .{
                    .class = .syntax,
                    .pos = ok.pos,
                    .line = lc.line,
                    .col = lc.col,
                    .expected = "end of input",
                    .expected_count = 1,
                    .expected_items = [_][]const u8{ "end of input", "", "", "", "" },
                    .expected_truncated = false,
                    .context = snippet.line,
                    .context_prev = snippet.prev,
                    .context_next = snippet.next,
                } };
            },
            .err => |e| {
                const lc = computeLineCol(input, e.pos);
                const snippet = getContextSnippet(input, e.pos);
                return .{ .err = .{
                    .class = .syntax,
                    .pos = e.pos,
                    .line = lc.line,
                    .col = lc.col,
                    .expected = e.expected,
                    .expected_count = if (e.expected_count == 0) 1 else e.expected_count,
                    .expected_items = if (e.expected_count == 0)
                        [_][]const u8{ e.expected, "", "", "", "" }
                    else
                        e.expected_items,
                    .expected_truncated = e.expected_truncated,
                    .context = snippet.line,
                    .context_prev = snippet.prev,
                    .context_next = snippet.next,
                } };
            },
        }
    }

    fn findRuleIndex(self: Grammar, name: []const u8) ?u16 {
        for (self.rules, 0..) |nr, i| {
            if (std.mem.eql(u8, nr.name, name)) return @intCast(i);
        }
        return null;
    }
};

fn computeLineCol(input: []const u8, pos: usize) struct { line: usize, col: usize } {
    var line: usize = 1;
    var col: usize = 1;
    for (input[0..@min(pos, input.len)]) |c| {
        if (c == '\n') {
            line += 1;
            col = 1;
        } else {
            col += 1;
        }
    }
    return .{ .line = line, .col = col };
}

fn getContextSnippet(input: []const u8, pos: usize) struct { prev: []const u8, line: []const u8, next: []const u8 } {
    const p = @min(pos, input.len);
    var line_start = p;
    while (line_start > 0 and input[line_start - 1] != '\n') : (line_start -= 1) {}

    var line_end = p;
    while (line_end < input.len and input[line_end] != '\n') : (line_end += 1) {}

    var prev_start: usize = line_start;
    var prev_end: usize = line_start;
    if (line_start > 0) {
        prev_end = line_start - 1;
        prev_start = prev_end;
        while (prev_start > 0 and input[prev_start - 1] != '\n') : (prev_start -= 1) {}
    }

    var next_start: usize = line_end;
    var next_end: usize = line_end;
    if (line_end < input.len) {
        next_start = line_end + 1;
        next_end = next_start;
        while (next_end < input.len and input[next_end] != '\n') : (next_end += 1) {}
    }

    var clipped_line_end = line_end;
    if (clipped_line_end > line_start + 120) clipped_line_end = line_start + 120;
    var clipped_prev_end = prev_end;
    if (clipped_prev_end > prev_start + 120) clipped_prev_end = prev_start + 120;
    var clipped_next_end = next_end;
    if (clipped_next_end > next_start + 120) clipped_next_end = next_start + 120;

    return .{
        .prev = if (prev_end > prev_start) input[prev_start..clipped_prev_end] else "",
        .line = input[line_start..clipped_line_end],
        .next = if (next_end > next_start) input[next_start..clipped_next_end] else "",
    };
}

// --- Comptime helpers ---

fn isIdentChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
}

fn skipWs(comptime source: []const u8, comptime start: usize) usize {
    comptime {
        var pos = start;
        while (pos < source.len and (source[pos] == ' ' or source[pos] == '\t' or
            source[pos] == '\n' or source[pos] == '\r')) : (pos += 1)
        {}
        return pos;
    }
}

const RuleHeader = struct {
    name: []const u8,
    silent: bool,
    squashed: bool,
    memo_mode: MemoModeOverride,
    pos: usize,
};

fn parseRuleHeader(comptime source: []const u8, comptime start: usize) RuleHeader {
    comptime {
        var pos = skipWs(source, start);
        var silent = false;
        var squashed = false;
        var memo_mode: MemoModeOverride = .inherit;

        while (pos < source.len and source[pos] == '@') {
            pos += 1;
            const ann_start = pos;
            while (pos < source.len and isIdentChar(source[pos])) : (pos += 1) {}
            const ann = source[ann_start..pos];
            if (ann.len == 0) @compileError("Expected annotation or rule name after '@'");
            const after_ann = skipWs(source, pos);
            if (after_ann + 2 <= source.len and std.mem.eql(u8, source[after_ann .. after_ann + 2], "<-")) {
                @compileError("Deprecated rule header '@name <- ...' is no longer supported. Use 'name <- ...' and explicit whitespace rules.");
            }
            if (std.mem.eql(u8, ann, "squashed")) {
                squashed = true;
            } else if (std.mem.eql(u8, ann, "silent")) {
                silent = true;
            } else if (std.mem.eql(u8, ann, "atomic")) {
                @compileError("Deprecated annotation '@atomic' is no longer supported. Use explicit whitespace rules in grammar.");
            } else if (std.mem.eql(u8, ann, "memo_on")) {
                memo_mode = .on;
            } else if (std.mem.eql(u8, ann, "memo_off")) {
                memo_mode = .off;
            } else {
                @compileError("Unknown rule annotation: @" ++ ann);
            }
            pos = after_ann;
        }

        const name_start = pos;
        while (pos < source.len and isIdentChar(source[pos])) : (pos += 1) {}
        const name = source[name_start..pos];
        if (name.len == 0) @compileError("Expected rule name");
        pos = skipWs(source, pos);
        if (!(pos + 2 <= source.len and std.mem.eql(u8, source[pos .. pos + 2], "<-")))
            @compileError("Expected '<-' after rule name");
        pos += 2;
        return .{
            .name = name,
            .silent = silent,
            .squashed = squashed,
            .memo_mode = memo_mode,
            .pos = pos,
        };
    }
}

fn peekRuleDef(comptime source: []const u8, comptime start: usize) bool {
    comptime {
        var pos = start;
        while (pos < source.len and source[pos] == '@') {
            pos += 1;
            while (pos < source.len and isIdentChar(source[pos])) : (pos += 1) {}
            pos = skipWs(source, pos);
            if (pos + 2 <= source.len and std.mem.eql(u8, source[pos .. pos + 2], "<-")) return true;
        }
        while (pos < source.len and isIdentChar(source[pos])) : (pos += 1) {}
        pos = skipWs(source, pos);
        return (pos + 2 <= source.len and std.mem.eql(u8, source[pos .. pos + 2], "<-"));
    }
}

fn collectRuleNames(comptime source: []const u8) []const []const u8 {
    comptime {
        var names: []const []const u8 = &.{};
        var pos: usize = 0;
        while (pos < source.len) {
            const h = parseRuleHeader(source, pos);
            names = names ++ &[_][]const u8{h.name};
            pos = h.pos;

            var in_single = false;
            var in_double = false;
            var in_class = false;
            var escaped = false;
            var group_depth: usize = 0;
            while (pos < source.len) : (pos += 1) {
                const c = source[pos];

                if (escaped) {
                    escaped = false;
                    continue;
                }

                if (in_single) {
                    if (c == '\\') escaped = true else if (c == '\'') in_single = false;
                    continue;
                }

                if (in_double) {
                    if (c == '\\') escaped = true else if (c == '"') in_double = false;
                    continue;
                }

                if (in_class) {
                    if (c == '\\') escaped = true else if (c == ']') in_class = false;
                    continue;
                }

                switch (c) {
                    '\'' => in_single = true,
                    '"' => in_double = true,
                    '[' => in_class = true,
                    '(' => group_depth += 1,
                    ')' => {
                        if (group_depth > 0) group_depth -= 1;
                    },
                    else => {
                        if (group_depth == 0 and isIdentChar(c) and (pos == 0 or !isIdentChar(source[pos - 1])) and peekRuleDef(source, pos)) {
                            break;
                        }
                    },
                }
            }
        }
        return names;
    }
}

fn parseGrammarComptime(comptime source: []const u8) Grammar {
    comptime {
        const names = collectRuleNames(source);
        var rules: []const NamedRule = &.{};
        var pos: usize = 0;
        while (pos < source.len) {
            pos = skipWs(source, pos);
            if (pos >= source.len) break;
            const h = parseRuleHeader(source, pos);
            const name = h.name;
            pos = skipWs(source, h.pos);
            const r = parseChoice(source, pos, names);
            rules = rules ++ &[_]NamedRule{.{
                .name = name,
                .rule = r.rule,
                .silent = h.silent,
                .squashed = h.squashed,
                .memo_mode = h.memo_mode,
            }};
            pos = r.pos;
        }
        if (rules.len == 0) @compileError("No rules found in grammar");
        return .{ .rules = rules };
    }
}

fn findNameIndex(comptime names: []const []const u8, comptime name: []const u8) u16 {
    for (names, 0..) |n, i| {
        if (std.mem.eql(u8, n, name)) return @intCast(i);
    }
    @compileError("Unknown rule: '" ++ name ++ "'");
}

const RuleResult = struct { rule: Rule, pos: usize };

fn parseChoice(comptime source: []const u8, comptime start: usize, comptime names: []const []const u8) RuleResult {
    comptime {
        const first = parseSequence(source, start, names);
        var alts: []const Rule = &[_]Rule{first.rule};
        var pos = first.pos;
        while (true) {
            const saved = pos;
            pos = skipWs(source, pos);
            if (pos < source.len and source[pos] == '/') {
                pos += 1;
                pos = skipWs(source, pos);
                const next = parseSequence(source, pos, names);
                alts = alts ++ &[_]Rule{next.rule};
                pos = next.pos;
            } else {
                pos = saved;
                break;
            }
        }
        if (alts.len == 1) return .{ .rule = alts[0], .pos = pos };
        return .{ .rule = .{ .choice = alts }, .pos = pos };
    }
}

fn parseSequence(comptime source: []const u8, comptime start: usize, comptime names: []const []const u8) RuleResult {
    comptime {
        var parts: []const Rule = &.{};
        var pos = start;
        while (true) {
            pos = skipWs(source, pos);
            if (pos >= source.len) break;
            if (source[pos] == '/' or source[pos] == ')') break;
            if ((source[pos] == '@' and peekRuleDef(source, pos)) or (isIdentChar(source[pos]) and peekRuleDef(source, pos))) break;
            const r = parsePostfix(source, pos, names);
            parts = parts ++ &[_]Rule{r.rule};
            pos = r.pos;
        }
        if (parts.len == 0) @compileError("Empty sequence");
        if (parts.len == 1) return .{ .rule = parts[0], .pos = pos };
        return .{ .rule = .{ .sequence = parts }, .pos = pos };
    }
}

fn wrapZeroOrMore(comptime inner: Rule) Rule { return .{ .zero_or_more = &[_]Rule{inner} }; }
fn wrapOneOrMore(comptime inner: Rule) Rule { return .{ .one_or_more = &[_]Rule{inner} }; }
fn wrapOptional(comptime inner: Rule) Rule { return .{ .optional = &[_]Rule{inner} }; }
fn wrapNot(comptime inner: Rule) Rule { return .{ .not = &[_]Rule{inner} }; }
fn wrapAmp(comptime inner: Rule) Rule { return .{ .amp = &[_]Rule{inner} }; }
fn wrapRepeatRange(comptime inner: Rule, comptime min: u16, comptime max: u16) Rule {
    return .{ .repeat_range = .{ .rule = &[_]Rule{inner}, .min = min, .max = max } };
}

fn parseComptimeInt(comptime source: []const u8, comptime start: usize) struct { val: u16, pos: usize } {
    comptime {
        var pos = start;
        var val: u16 = 0;
        while (pos < source.len and source[pos] >= '0' and source[pos] <= '9') {
            val = val * 10 + @as(u16, source[pos] - '0');
            pos += 1;
        }
        return .{ .val = val, .pos = pos };
    }
}

fn parsePostfix(comptime source: []const u8, comptime start: usize, comptime names: []const []const u8) RuleResult {
    comptime {
        const r = parsePrefix(source, start, names);
        var pos = r.pos;
        if (pos < source.len and source[pos] == '*') return .{ .rule = wrapZeroOrMore(r.rule), .pos = pos + 1 };
        if (pos < source.len and source[pos] == '+') return .{ .rule = wrapOneOrMore(r.rule), .pos = pos + 1 };
        if (pos < source.len and source[pos] == '?') return .{ .rule = wrapOptional(r.rule), .pos = pos + 1 };
        if (pos < source.len and source[pos] == '{') {
            pos += 1;
            const min_start = pos;
            const min_r = parseComptimeInt(source, pos);
            pos = min_r.pos;
            if (pos == min_start) @compileError("Expected minimum value in repeat range");
            const  min_val = min_r.val;
            var max_val = min_val;
            if (pos < source.len and source[pos] == ',') {
                pos += 1;
                if (pos < source.len and source[pos] >= '0' and source[pos] <= '9') {
                    const max_r = parseComptimeInt(source, pos);
                    max_val = max_r.val;
                    pos = max_r.pos;
                } else {
                    max_val = 0; // unlimited
                }
            }
            if (pos >= source.len or source[pos] != '}') @compileError("Expected '}' in repeat range");
            pos += 1;
            if (max_val != 0 and min_val > max_val) @compileError("Invalid repeat range: min must be <= max");
            return .{ .rule = wrapRepeatRange(r.rule, min_val, max_val), .pos = pos };
        }
        return r;
    }
}

const RegexAtomResult = struct { rule: Rule, pos: usize };

fn parseRegexEscapedChar(comptime pattern: []const u8, comptime pos: usize) struct { ch: u8, next: usize } {
    comptime {
        if (pos >= pattern.len) @compileError("Incomplete regex escape");
        if (pattern[pos] != '\\') return .{ .ch = pattern[pos], .next = pos + 1 };
        if (pos + 1 >= pattern.len) @compileError("Incomplete regex escape");
        const n = pattern[pos + 1];
        if (n == 'x') {
            if (pos + 3 >= pattern.len) @compileError("Incomplete regex \\x escape");
            const hi = hexVal(pattern[pos + 2]);
            const lo = hexVal(pattern[pos + 3]);
            return .{ .ch = (hi << 4) | lo, .next = pos + 4 };
        }
        return .{
            .ch = switch (n) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                '"' => '"',
                '\'' => '\'',
                else => n,
            },
            .next = pos + 2,
        };
    }
}

fn parseRegexCharClass(comptime pattern: []const u8, comptime start: usize) RegexAtomResult {
    comptime {
        var pos = start + 1;
        var negated = false;
        if (pos < pattern.len and pattern[pos] == '^') {
            negated = true;
            pos += 1;
        }
        var ranges: []const CharRange = &.{};
        while (pos < pattern.len and pattern[pos] != ']') {
            const a = parseRegexEscapedChar(pattern, pos);
            pos = a.next;
            if (pos < pattern.len and pattern[pos] == '-' and pos + 1 < pattern.len and pattern[pos + 1] != ']') {
                pos += 1;
                const b = parseRegexEscapedChar(pattern, pos);
                pos = b.next;
                if (a.ch > b.ch) @compileError("Invalid regex class range");
                ranges = ranges ++ &[_]CharRange{.{ .lo = a.ch, .hi = b.ch }};
            } else {
                ranges = ranges ++ &[_]CharRange{.{ .lo = a.ch, .hi = a.ch }};
            }
        }
        if (pos >= pattern.len or pattern[pos] != ']') @compileError("Unterminated regex char class");
        pos += 1;
        return .{
            .rule = if (negated) .{ .neg_char_class = ranges } else .{ .char_class = ranges },
            .pos = pos,
        };
    }
}

fn parseRegexAtom(comptime pattern: []const u8, comptime start: usize) RegexAtomResult {
    comptime {
        if (start >= pattern.len) @compileError("Unexpected end of regex pattern");
        const c = pattern[start];
        if (c == '[') return parseRegexCharClass(pattern, start);
        if (c == '.') return .{ .rule = .dot, .pos = start + 1 };
        if (c == '\\') {
            const e = parseRegexEscapedChar(pattern, start);
            return .{
                .rule = .{ .char_class = &[_]CharRange{.{ .lo = e.ch, .hi = e.ch }} },
                .pos = e.next,
            };
        }
        return .{ .rule = .{ .literal = pattern[start .. start + 1] }, .pos = start + 1 };
    }
}

fn parseRegexPattern(comptime pattern: []const u8) Rule {
    comptime {
        if (pattern.len == 0) return .{ .literal = "" };
        var pos: usize = 0;
        var parts: []const Rule = &.{};
        while (pos < pattern.len) {
            const a = parseRegexAtom(pattern, pos);
            var r = a.rule;
            pos = a.pos;
            if (pos < pattern.len and pattern[pos] == '*') {
                r = wrapZeroOrMore(r);
                pos += 1;
            } else if (pos < pattern.len and pattern[pos] == '+') {
                r = wrapOneOrMore(r);
                pos += 1;
            } else if (pos < pattern.len and pattern[pos] == '?') {
                r = wrapOptional(r);
                pos += 1;
            } else if (pos < pattern.len and pattern[pos] == '{') {
                pos += 1;
                const min_start = pos;
                const min_r = parseComptimeInt(pattern, pos);
                pos = min_r.pos;
                if (pos == min_start) @compileError("Expected minimum value in regex repeat range");
                const min_val = min_r.val;
                var max_val = min_val;
                if (pos < pattern.len and pattern[pos] == ',') {
                    pos += 1;
                    if (pos < pattern.len and pattern[pos] >= '0' and pattern[pos] <= '9') {
                        const max_r = parseComptimeInt(pattern, pos);
                        max_val = max_r.val;
                        pos = max_r.pos;
                    } else {
                        max_val = 0;
                    }
                }
                if (pos >= pattern.len or pattern[pos] != '}') @compileError("Expected '}' in regex repeat range");
                pos += 1;
                if (max_val != 0 and min_val > max_val) @compileError("Invalid regex repeat range: min must be <= max");
                r = wrapRepeatRange(r, min_val, max_val);
            }
            parts = parts ++ &[_]Rule{r};
        }
        if (parts.len == 1) return parts[0];
        return .{ .sequence = parts };
    }
}

fn parsePrefix(comptime source: []const u8, comptime start: usize, comptime names: []const []const u8) RuleResult {
    comptime {
        var pos = start;
        if (pos < source.len and source[pos] == '!') {
            pos += 1;
            pos = skipWs(source, pos);
            const inner = parseAtom(source, pos, names);
            return .{ .rule = wrapNot(inner.rule), .pos = inner.pos };
        }
        if (pos < source.len and source[pos] == '&') {
            pos += 1;
            pos = skipWs(source, pos);
            const inner = parseAtom(source, pos, names);
            return .{ .rule = wrapAmp(inner.rule), .pos = inner.pos };
        }
        return parseAtom(source, pos, names);
    }
}

fn parseCharClassEscape(comptime source: []const u8, comptime pos: usize) struct { ch: u8, next: usize } {
    comptime {
        if (source[pos] != '\\' or pos + 1 >= source.len)
            return .{ .ch = source[pos], .next = pos + 1 };
        const ch: u8 = switch (source[pos + 1]) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            '\\' => '\\',
            ']' => ']',
            '[' => '[',
            '-' => '-',
            '\'' => '\'',
            '"' => '"',
            '^' => '^',
            'x' => {
                // \xHH — hex escape
                if (pos + 3 >= source.len) @compileError("Incomplete \\x escape");
                const hi = hexVal(source[pos + 2]);
                const lo = hexVal(source[pos + 3]);
                return .{ .ch = (hi << 4) | lo, .next = pos + 4 };
            },
            else => @compileError("Unknown escape in char class"),
        };
        return .{ .ch = ch, .next = pos + 2 };
    }
}

fn hexVal(comptime c: u8) u8 {
    comptime {
        if (c >= '0' and c <= '9') return c - '0';
        if (c >= 'a' and c <= 'f') return c - 'a' + 10;
        if (c >= 'A' and c <= 'F') return c - 'A' + 10;
        @compileError("Invalid hex digit in \\x escape");
    }
}

fn parseCharClassBody(comptime source: []const u8, comptime start: usize) struct { ranges: []const CharRange, pos: usize } {
    comptime {
        var ranges: []const CharRange = &.{};
        var pos = start;
        while (pos < source.len and source[pos] != ']') {
            const lo_r = parseCharClassEscape(source, pos);
            pos = lo_r.next;
            if (pos + 1 < source.len and source[pos] == '-' and source[pos + 1] != ']') {
                pos += 1;
                const hi_r = parseCharClassEscape(source, pos);
                pos = hi_r.next;
                if (lo_r.ch > hi_r.ch) @compileError("Invalid character range: lower bound must be <= upper bound");
                ranges = ranges ++ &[_]CharRange{.{ .lo = lo_r.ch, .hi = hi_r.ch }};
            } else {
                ranges = ranges ++ &[_]CharRange{.{ .lo = lo_r.ch, .hi = lo_r.ch }};
            }
        }
        if (pos >= source.len) @compileError("Unterminated character class");
        return .{ .ranges = ranges, .pos = pos + 1 };
    }
}

fn toLowerComptime(comptime s: []const u8) []const u8 {
    comptime {
        var has_upper = false;
        for (s) |c| {
            if (c >= 'A' and c <= 'Z') {
                has_upper = true;
                break;
            }
        }
        if (!has_upper) return s;

        var result: []const u8 = &.{};
        for (s) |c| {
            if (c >= 'A' and c <= 'Z') {
                result = result ++ &[_]u8{c + 32};
            } else {
                result = result ++ &[_]u8{c};
            }
        }
        return result;
    }
}

fn parseStringLiteral(comptime source: []const u8, comptime start: usize, comptime quote: u8) struct { text: []const u8, pos: usize } {
    comptime {
        // Fast path: no escapes, return a direct source slice.
        var pos = start;
        var has_escape = false;
        while (pos < source.len and source[pos] != quote) : (pos += 1) {
            if (source[pos] == '\\') has_escape = true;
        }
        if (pos >= source.len) @compileError("Unterminated string literal");
        if (!has_escape) {
            return .{ .text = source[start..pos], .pos = pos + 1 };
        }

        // Slow path: escaped literal, decode in two passes to avoid O(N^2) concatenation.
        var out_len: usize = 0;
        pos = start;
        while (pos < source.len and source[pos] != quote) {
            if (source[pos] == '\\') {
                if (pos + 1 >= source.len) @compileError("Unterminated string literal escape");
                _ = switch (source[pos + 1]) {
                    'n', 't', 'r', '\\', '\'', '"' => {},
                    else => @compileError("Unknown escape in string literal"),
                };
                pos += 2;
            } else {
                pos += 1;
            }
            out_len += 1;
        }
        if (pos >= source.len) @compileError("Unterminated string literal");
        const end_pos = pos + 1;

        var out: [out_len]u8 = undefined;
        var out_i: usize = 0;
        pos = start;
        while (pos < source.len and source[pos] != quote) {
            if (source[pos] == '\\') {
                if (pos + 1 >= source.len) @compileError("Unterminated string literal escape");
                out[out_i] = switch (source[pos + 1]) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    '\\' => '\\',
                    '\'' => '\'',
                    '"' => '"',
                    else => @compileError("Unknown escape in string literal"),
                };
                pos += 2;
            } else {
                out[out_i] = source[pos];
                pos += 1;
            }
            out_i += 1;
        }
        const frozen = out;
        return .{ .text = frozen[0..], .pos = end_pos };
    }
}

fn parseRegexLiteral(comptime source: []const u8, comptime start: usize, comptime quote: u8) struct { text: []const u8, pos: usize } {
    comptime {
        var pos = start;
        var has_escape = false;
        while (pos < source.len and source[pos] != quote) : (pos += 1) {
            if (source[pos] == '\\') {
                has_escape = true;
                if (pos + 1 >= source.len) @compileError("Unterminated regex literal escape");
                pos += 1;
            }
        }
        if (pos >= source.len) @compileError("Unterminated regex literal");
        if (!has_escape) return .{ .text = source[start..pos], .pos = pos + 1 };

        var out_len: usize = 0;
        pos = start;
        while (pos < source.len and source[pos] != quote) {
            if (source[pos] == '\\') {
                if (pos + 1 >= source.len) @compileError("Unterminated regex literal escape");
                out_len += 2;
                pos += 2;
            } else {
                out_len += 1;
                pos += 1;
            }
        }
        if (pos >= source.len) @compileError("Unterminated regex literal");
        const end_pos = pos + 1;

        var out: [out_len]u8 = undefined;
        var out_i: usize = 0;
        pos = start;
        while (pos < source.len and source[pos] != quote) {
            if (source[pos] == '\\') {
                if (pos + 1 >= source.len) @compileError("Unterminated regex literal escape");
                out[out_i] = source[pos];
                out[out_i + 1] = source[pos + 1];
                out_i += 2;
                pos += 2;
            } else {
                out[out_i] = source[pos];
                out_i += 1;
                pos += 1;
            }
        }
        const frozen = out;
        return .{ .text = frozen[0..], .pos = end_pos };
    }
}

fn parseAtom(comptime source: []const u8, comptime start: usize, comptime names: []const []const u8) RuleResult {
    comptime {
        var pos = start;
        if (pos >= source.len) @compileError("Unexpected end of grammar");

        // Regex-like primitive: ~'...' / ~"..."
        if (source[pos] == '~') {
            pos += 1;
            if (pos >= source.len or (source[pos] != '\'' and source[pos] != '"'))
                @compileError("Expected quoted regex literal after '~'");
            const quote = source[pos];
            const r = parseRegexLiteral(source, pos + 1, quote);
            pos = r.pos;
            if (pos < source.len and source[pos] == 'i') {
                @compileError("Regex-like primitive does not support 'i' flag yet");
            }
            return .{ .rule = parseRegexPattern(r.text), .pos = pos };
        }

        // Dot
        if (source[pos] == '.') return .{ .rule = .dot, .pos = pos + 1 };

        // Single-quote string
        if (source[pos] == '\'') {
            const r = parseStringLiteral(source, pos + 1, '\'');
            // Check for 'i' suffix (case-insensitive)
            if (r.pos < source.len and source[r.pos] == 'i') {
                return .{ .rule = .{ .literal_ic = toLowerComptime(r.text) }, .pos = r.pos + 1 };
            }
            return .{ .rule = .{ .literal = r.text }, .pos = r.pos };
        }

        // Double-quote string
        if (source[pos] == '"') {
            const r = parseStringLiteral(source, pos + 1, '"');
            // Check for 'i' suffix (case-insensitive)
            if (r.pos < source.len and source[r.pos] == 'i') {
                return .{ .rule = .{ .literal_ic = toLowerComptime(r.text) }, .pos = r.pos + 1 };
            }
            return .{ .rule = .{ .literal = r.text }, .pos = r.pos };
        }

        // Character class
        if (source[pos] == '[') {
            pos += 1;
            if (pos < source.len and source[pos] == '^') {
                pos += 1;
                const body = parseCharClassBody(source, pos);
                return .{ .rule = .{ .neg_char_class = body.ranges }, .pos = body.pos };
            } else {
                const body = parseCharClassBody(source, pos);
                return .{ .rule = .{ .char_class = body.ranges }, .pos = body.pos };
            }
        }

        // Group
        if (source[pos] == '(') {
            pos += 1;
            pos = skipWs(source, pos);
            const inner = parseChoice(source, pos, names);
            pos = inner.pos;
            pos = skipWs(source, pos);
            if (pos >= source.len or source[pos] != ')') @compileError("Expected ')'");
            pos += 1;
            return .{ .rule = inner.rule, .pos = pos };
        }

        // Identifier
        if (isIdentChar(source[pos])) {
            const id_start = pos;
            while (pos < source.len and isIdentChar(source[pos])) : (pos += 1) {}
            return .{ .rule = .{ .ref = findNameIndex(names, source[id_start..pos]) }, .pos = pos };
        }

        @compileError("Unexpected character in grammar: '" ++ source[pos .. pos + 1] ++ "'");
    }
}

// --- Runtime Engine ---

const MemoKey = struct {
    rule_idx: u16,
    pos: u32,
};

const MemoNodes = union(enum) {
    none,
    one: u32,
    many: []const u32,
};

const MemoValue = struct {
    result_pos: u32,
    nodes: MemoNodes,
    err_expected: []const u8,
};

const Engine = struct {
    rules: []const NamedRule,
    allocator: std.mem.Allocator,
    options: ParseOptions,
    pool: NodePool,
    memo: std.AutoHashMapUnmanaged(MemoKey, MemoValue),
    farthest_pos: usize,
    farthest_expected: []const u8,
    farthest_expected_count: u8,
    farthest_expected_items: [5][]const u8,
    farthest_expected_truncated: bool,
    trace_depth: usize,
    recursion_depth: usize,

    fn init(rules: []const NamedRule, allocator: std.mem.Allocator, options: ParseOptions) Engine {
        return .{
            .rules = rules,
            .allocator = allocator,
            .options = options,
            .pool = NodePool.init(allocator),
            .memo = .{},
            .farthest_pos = 0,
            .farthest_expected = "",
            .farthest_expected_count = 0,
            .farthest_expected_items = [_][]const u8{ "", "", "", "", "" },
            .farthest_expected_truncated = false,
            .trace_depth = 0,
            .recursion_depth = 0,
        };
    }

    fn deinit(self: *Engine) void {
        var it = self.memo.iterator();
        while (it.next()) |entry| {
            self.memoNodesDeinit(entry.value_ptr.nodes);
        }
        self.memo.deinit(self.allocator);
        self.pool.deinit();
    }

    fn memoNodesDeinit(self: *Engine, nodes: MemoNodes) void {
        switch (nodes) {
            .many => |slice| {
                if (slice.len > 0) self.allocator.free(slice);
            },
            else => {},
        }
    }

    fn memoNodesFromNodeList(self: *Engine, nodes: NodeList) !MemoNodes {
        const items = nodes.indices.items;
        if (items.len == 0) return .none;
        if (items.len == 1) return MemoNodes{ .one = items[0] };
        return MemoNodes{ .many = try self.allocator.dupe(u32, items) };
    }

    fn memoNodesToNodeList(self: *Engine, memo_nodes: MemoNodes) !NodeList {
        var nodes = NodeList.empty();
        switch (memo_nodes) {
            .none => {},
            .one => |idx| try nodes.append(self.allocator, idx),
            .many => |slice| try nodes.indices.appendSlice(self.allocator, slice),
        }
        return nodes;
    }

    fn memoPutSuccess(self: *Engine, key: MemoKey, pos: usize, nodes: NodeList) !void {
        if (pos > std.math.maxInt(u32)) return;
        const memo_nodes = try self.memoNodesFromNodeList(nodes);
        if (self.memo.getPtr(key)) |existing| {
            self.memoNodesDeinit(existing.nodes);
            existing.* = .{
                .result_pos = @intCast(pos),
                .nodes = memo_nodes,
                .err_expected = "",
            };
        } else {
            errdefer self.memoNodesDeinit(memo_nodes);
            try self.memo.put(self.allocator, key, .{
                .result_pos = @intCast(pos),
                .nodes = memo_nodes,
                .err_expected = "",
            });
        }
        if (self.options.stats) |s| s.memo_puts += 1;
    }

    fn memoPutFailure(self: *Engine, key: MemoKey, expected: []const u8) !void {
        if (self.memo.getPtr(key)) |existing| {
            self.memoNodesDeinit(existing.nodes);
            existing.* = .{
                .result_pos = 0xFFFFFFFF,
                .nodes = .none,
                .err_expected = expected,
            };
        } else {
            try self.memo.put(self.allocator, key, .{
                .result_pos = 0xFFFFFFFF,
                .nodes = .none,
                .err_expected = expected,
            });
        }
        if (self.options.stats) |s| s.memo_puts += 1;
    }

    fn parse(self: *Engine, start_idx: u16, input: []const u8) EngineError!ParseSuccess {
        const result = try self.parseInner(start_idx, input);
        if (self.options.stats) |s| {
            s.memo_entries = self.memo.count();
            s.pool_entries = self.pool.entries.items.len;
            s.materialized_nodes = self.pool.entries.items.len;
        }
        switch (result) {
            .ok => |s| return s,
            .err => return error.ParseFailed,
        }
    }

    const InnerResult = union(enum) {
        ok: ParseSuccess,
        err: ParseError,
    };

    fn parseInner(self: *Engine, start_idx: u16, input: []const u8) EngineError!InnerResult {
        const start_pos: usize = 0;
        const res = try self.matchRule(.{ .ref = start_idx }, input, start_pos);
        switch (res) {
            .ok => |ok| {
                defer {
                    var temp = ok.nodes;
                    temp.deinit(self.allocator);
                }
                if (ok.nodes.indices.items.len == 1) {
                    const root = try self.pool.materialize(ok.nodes.indices.items[0]);
                    return .{ .ok = ParseSuccess{
                        .node = Node{
                            .tag = self.rules[start_idx].name,
                            .text = input[start_pos..ok.pos],
                            .children = root.children,
                        },
                        .pos = ok.pos,
                    } };
                }
                var children: []const Node = &.{};
                if (ok.nodes.indices.items.len > 0) {
                    const cs = try self.allocator.alloc(Node, ok.nodes.indices.items.len);
                    for (ok.nodes.indices.items, 0..) |ni, i| {
                        cs[i] = try self.pool.materialize(ni);
                    }
                    children = cs;
                }
                return .{ .ok = ParseSuccess{
                    .node = Node{
                        .tag = self.rules[start_idx].name,
                        .text = input[start_pos..ok.pos],
                        .children = children,
                    },
                    .pos = ok.pos,
                } };
            },
            .err => {
                return .{ .err = .{
                    .pos = self.farthest_pos,
                    .expected = if (self.farthest_expected_count > 0) self.farthest_expected_items[0] else self.farthest_expected,
                    .expected_count = self.farthest_expected_count,
                    .expected_items = self.farthest_expected_items,
                    .expected_truncated = self.farthest_expected_truncated,
                } };
            },
        }
    }

    fn trackError(self: *Engine, pos: usize, expected: []const u8) void {
        if (pos > self.farthest_pos) {
            self.farthest_pos = pos;
            self.farthest_expected = expected;
            self.farthest_expected_count = 0;
            self.farthest_expected_truncated = false;
            self.addExpectedAtFarthest(expected);
            return;
        }
        if (pos == self.farthest_pos and expected.len > 0) {
            if (self.farthest_expected_count == 0) {
                self.farthest_expected = expected;
            }
            self.addExpectedAtFarthest(expected);
        }
    }

    fn addExpectedAtFarthest(self: *Engine, expected: []const u8) void {
        if (expected.len == 0) return;
        var i: usize = 0;
        while (i < self.farthest_expected_count) : (i += 1) {
            if (std.mem.eql(u8, self.farthest_expected_items[i], expected)) return;
        }
        if (self.farthest_expected_count >= self.farthest_expected_items.len) {
            self.farthest_expected_truncated = true;
            return;
        }
        self.farthest_expected_items[self.farthest_expected_count] = expected;
        self.farthest_expected_count += 1;
    }

    fn traceIndent(self: *Engine, writer: anytype) !void {
        for (0..self.trace_depth) |_| try writer.writeAll("  ");
    }

    fn tracef(self: *Engine, comptime fmt: []const u8, args: anytype) void {
        if (!self.options.trace) return;
        if (self.options.trace_buffer) |buf| {
            const w = buf.writer(self.allocator);
            self.traceIndent(w) catch return;
            w.print(fmt, args) catch return;
            w.writeByte('\n') catch return;
        }
    }

    fn matchRule(self: *Engine, rule: Rule, input: []const u8, pos: usize) EngineError!ParseResult {
        if (self.options.max_recursion_depth != 0 and self.recursion_depth >= self.options.max_recursion_depth) {
            self.trackError(pos, "recursion depth limit");
            return .{ .err = .{ .pos = pos, .expected = "recursion depth limit" } };
        }
        self.recursion_depth += 1;
        defer self.recursion_depth -= 1;
        return switch (rule) {
            .literal => |lit| self.matchLiteral(lit, input, pos, false),
            .literal_ic => |lit| self.matchLiteral(lit, input, pos, true),
            .char_class => |ranges| self.matchCharClass(ranges, input, pos, false),
            .neg_char_class => |ranges| self.matchCharClass(ranges, input, pos, true),
            .dot => self.matchDot(input, pos),
            .sequence => |seq| self.matchSequence(seq, input, pos),
            .choice => |alts| self.matchChoice(alts, input, pos),
            .zero_or_more => |r| self.matchRepeat(r[0], input, pos, 0, 0),
            .one_or_more => |r| self.matchRepeat(r[0], input, pos, 1, 0),
            .optional => |r| self.matchOptional(r[0], input, pos),
            .repeat_range => |rr| self.matchRepeat(rr.rule[0], input, pos, rr.min, rr.max),
            .not => |r| self.matchNot(r[0], input, pos),
            .amp => |r| self.matchAmp(r[0], input, pos),
            .ref => |idx| self.matchRef(idx, input, pos),
        };
    }

    fn isMemoEnabled(self: *Engine, nr: NamedRule) bool {
        return switch (nr.memo_mode) {
            .inherit => self.options.memo_mode == .on,
            .on => true,
            .off => false,
        };
    }

    fn matchRef(self: *Engine, idx: u16, input: []const u8, pos: usize) EngineError!ParseResult {
        const nr = self.rules[idx];
        const memo_enabled = self.isMemoEnabled(nr);
        const rule_name = self.rules[idx].name;
        self.tracef("-> {s} @{}", .{ rule_name, pos });
        self.trace_depth += 1;
        defer self.trace_depth -= 1;
        if (pos > std.math.maxInt(u32)) {
            self.trackError(pos, "input position exceeds memo key range");
            self.tracef("<- {s} fail@{} (memo-pos-overflow)", .{ rule_name, pos });
            return .{ .err = .{ .pos = pos, .expected = "input position exceeds memo key range" } };
        }
        const key = MemoKey{ .rule_idx = idx, .pos = @intCast(pos) };

        if (memo_enabled) {
            if (self.memo.get(key)) |cached| {
                if (self.options.stats) |s| s.memo_hits += 1;
                if (cached.result_pos == 0xFFFFFFFF) {
                    self.tracef("<- {s} fail@{} (memo)", .{ rule_name, pos });
                    return .{ .err = .{ .pos = pos, .expected = cached.err_expected } };
                }
                const nodes = try self.memoNodesToNodeList(cached.nodes);
                self.tracef("<- {s} ok {}->{} (memo)", .{ rule_name, pos, cached.result_pos });
                return .{ .ok = .{ .pos = cached.result_pos, .nodes = nodes } };
            }
            if (self.options.stats) |s| s.memo_misses += 1;
        }

        const res = try self.matchRule(nr.rule, input, pos);
        switch (res) {
            .ok => |ok| {
                var result_nodes: NodeList = undefined;
                if (nr.squashed) {
                    result_nodes = ok.nodes;
                } else if (nr.silent) {
                    var old_nodes = ok.nodes;
                    old_nodes.deinit(self.allocator);
                    result_nodes = NodeList.empty();
                } else {
                    const child_indices = try self.allocator.dupe(u32, ok.nodes.indices.items);
                    var old_nodes = ok.nodes;
                    old_nodes.deinit(self.allocator);
                    const node_idx = try self.pool.add(nr.name, input[pos..ok.pos], child_indices);
                    result_nodes = NodeList.empty();
                    try result_nodes.append(self.allocator, node_idx);
                }
                errdefer {
                    var tmp = result_nodes;
                    tmp.deinit(self.allocator);
                }

                if (memo_enabled) {
                    try self.memoPutSuccess(key, ok.pos, result_nodes);
                }

                if (nr.squashed) {
                    self.tracef("<- {s} ok {}->{} (squashed)", .{ rule_name, pos, ok.pos });
                } else {
                    self.tracef("<- {s} ok {}->{}", .{ rule_name, pos, ok.pos });
                }
                return .{ .ok = .{ .pos = ok.pos, .nodes = result_nodes } };
            },
            .err => |e| {
                if (memo_enabled) {
                    try self.memoPutFailure(key, e.expected);
                }
                self.tracef("<- {s} fail@{} exp {s}", .{ rule_name, e.pos, e.expected });
                return res;
            },
        }
    }

    fn matchLiteral(self: *Engine, lit: []const u8, input: []const u8, pos: usize, case_insensitive: bool) ParseResult {
        if (pos + lit.len > input.len) {
            self.trackError(pos, lit);
            return .{ .err = .{ .pos = pos, .expected = lit } };
        }
        if (case_insensitive) {
            for (0..lit.len) |i| {
                var c = input[pos + i];
                if (c >= 'A' and c <= 'Z') c += 32;
                if (c != lit[i]) {
                    self.trackError(pos, lit);
                    return .{ .err = .{ .pos = pos, .expected = lit } };
                }
            }
        } else {
            if (!std.mem.eql(u8, input[pos .. pos + lit.len], lit)) {
                self.trackError(pos, lit);
                return .{ .err = .{ .pos = pos, .expected = lit } };
            }
        }
        return .{ .ok = .{ .pos = pos + lit.len, .nodes = NodeList.empty() } };
    }

    fn matchCharClass(self: *Engine, ranges: []const CharRange, input: []const u8, pos: usize, negated: bool) ParseResult {
        if (pos >= input.len) {
            self.trackError(pos, "character class");
            return .{ .err = .{ .pos = pos, .expected = "character class" } };
        }
        const c = input[pos];
        var matched = false;
        for (ranges) |r| {
            if (c >= r.lo and c <= r.hi) {
                matched = true;
                break;
            }
        }
        if (negated) matched = !matched;
        if (matched)
            return .{ .ok = .{ .pos = pos + 1, .nodes = NodeList.empty() } };
        self.trackError(pos, "character class");
        return .{ .err = .{ .pos = pos, .expected = "character class" } };
    }

    fn matchDot(self: *Engine, input: []const u8, pos: usize) ParseResult {
        if (pos >= input.len) {
            self.trackError(pos, "any character");
            return .{ .err = .{ .pos = pos, .expected = "any character" } };
        }
        return .{ .ok = .{ .pos = pos + 1, .nodes = NodeList.empty() } };
    }

    fn matchNot(self: *Engine, rule: Rule, input: []const u8, pos: usize) EngineError!ParseResult {
        const res = try self.matchRule(rule, input, pos);
        switch (res) {
            .ok => |ok| {
                var nodes = ok.nodes;
                nodes.deinit(self.allocator);
                return .{ .err = .{ .pos = pos, .expected = "negative lookahead mismatch" } };
            },
            .err => return .{ .ok = .{ .pos = pos, .nodes = NodeList.empty() } },
        }
    }

    fn matchAmp(self: *Engine, rule: Rule, input: []const u8, pos: usize) EngineError!ParseResult {
        const res = try self.matchRule(rule, input, pos);
        switch (res) {
            .ok => |ok| {
                var nodes = ok.nodes;
                nodes.deinit(self.allocator);
                return .{ .ok = .{ .pos = pos, .nodes = NodeList.empty() } };
            },
            .err => |e| return .{ .err = e },
        }
    }

    fn matchSequence(self: *Engine, seq: []const Rule, input: []const u8, pos0: usize) EngineError!ParseResult {
        var pos = pos0;
        var all_nodes = NodeList.empty();
        errdefer all_nodes.deinit(self.allocator);
        try all_nodes.indices.ensureTotalCapacity(self.allocator, seq.len);

        for (seq) |part| {
            const r = try self.matchRule(part, input, pos);
            switch (r) {
                .ok => |ok| {
                    pos = ok.pos;
                    try all_nodes.appendSlice(self.allocator, ok.nodes);
                    var old = ok.nodes;
                    old.deinit(self.allocator);
                },
                .err => {
                    all_nodes.deinit(self.allocator);
                    return r;
                },
            }
        }

        return .{ .ok = .{ .pos = pos, .nodes = all_nodes } };
    }

    fn matchChoice(self: *Engine, alts: []const Rule, input: []const u8, pos: usize) EngineError!ParseResult {
        var best_err: ?ParseError = null;
        for (alts, 0..) |alt, i| {
            const r = try self.matchRule(alt, input, pos);
            switch (r) {
                .ok => return r,
                .err => |e| {
                    self.tracef("backtrack choice alt#{} @{}", .{ i, pos });
                    best_err = if (best_err) |be| (if (e.pos > be.pos) e else be) else e;
                },
            }
        }
        return .{ .err = best_err orelse .{ .pos = pos, .expected = "choice" } };
    }

    fn matchOptional(self: *Engine, rule: Rule, input: []const u8, pos: usize) EngineError!ParseResult {
        const res = try self.matchRule(rule, input, pos);
        switch (res) {
            .ok => return res,
            .err => return .{ .ok = .{ .pos = pos, .nodes = NodeList.empty() } },
        }
    }

    fn matchRepeat(self: *Engine, rule: Rule, input: []const u8, pos0: usize, min: u16, max: u16) EngineError!ParseResult {
        var pos = pos0;
        var count: u16 = 0;
        var all_nodes = NodeList.empty();
        errdefer all_nodes.deinit(self.allocator);
        if (max != 0 and max <= 64) {
            try all_nodes.indices.ensureTotalCapacity(self.allocator, max);
        }

        while (max == 0 or count < max) {
            const res = try self.matchRule(rule, input, pos);
            switch (res) {
                .ok => |ok| {
                    if (ok.pos == pos) {
                        var old = ok.nodes;
                        old.deinit(self.allocator);
                        break;
                    }
                    pos = ok.pos;
                    count += 1;
                    try all_nodes.appendSlice(self.allocator, ok.nodes);
                    var old = ok.nodes;
                    old.deinit(self.allocator);
                },
                .err => break,
            }
        }

        if (count < min) {
            all_nodes.deinit(self.allocator);
            return .{ .err = .{ .pos = pos0, .expected = "repetition" } };
        }
        return .{ .ok = .{ .pos = pos, .nodes = all_nodes } };
    }
};

fn startsWithSelfRef(comptime rule: Rule, comptime self_idx: u16) bool {
    comptime {
        return switch (rule) {
            .ref => |idx| idx == self_idx,
            .sequence => |seq| if (seq.len == 0) false else startsWithSelfRef(seq[0], self_idx),
            .choice => |alts| blk: {
                for (alts) |alt| {
                    if (startsWithSelfRef(alt, self_idx)) break :blk true;
                }
                break :blk false;
            },
            else => false,
        };
    }
}

fn tailAfterLeadingSelf(comptime alt: Rule, comptime self_idx: u16) ?Rule {
    comptime {
        return switch (alt) {
            .sequence => |seq| blk: {
                if (seq.len < 2) break :blk null;
                if (!startsWithSelfRef(seq[0], self_idx)) break :blk null;
                if (seq.len == 2) break :blk seq[1];
                break :blk Rule{ .sequence = seq[1..] };
            },
            else => null,
        };
    }
}

fn rewriteDirectLeftRecursionRuleLite(comptime rules: []const NamedRule, comptime rule: Rule, comptime self_idx: u16) Rule {
    comptime {
        return switch (rule) {
            .choice => |alts| blk: {
                if (alts.len != 2) break :blk rule;
                var base_idx: usize = 1;
                var tail = tailAfterLeadingSelf(alts[0], self_idx);
                if (tail == null) {
                    base_idx = 0;
                    tail = tailAfterLeadingSelf(alts[1], self_idx);
                }
                if (tail == null) break :blk rule;
                const base = alts[base_idx];
                const tail_rule = tail.?;

                if (startsWithSelfRef(base, self_idx)) break :blk rule;

                var seen_nullable: [rules.len]bool = [_]bool{false} ** rules.len;
                var active_nullable: [rules.len]bool = [_]bool{false} ** rules.len;
                var nullable_cache: [rules.len]bool = [_]bool{false} ** rules.len;
                if (ruleMayMatchEmpty(rules, base, &seen_nullable, &active_nullable, &nullable_cache)) break :blk rule;

                seen_nullable = [_]bool{false} ** rules.len;
                active_nullable = [_]bool{false} ** rules.len;
                nullable_cache = [_]bool{false} ** rules.len;
                if (ruleMayMatchEmpty(rules, tail_rule, &seen_nullable, &active_nullable, &nullable_cache)) break :blk rule;

                const repeated = wrapZeroOrMore(tail_rule);
                break :blk Rule{ .sequence = &[_]Rule{ base, repeated } };
            },
            else => rule,
        };
    }
}

fn rewriteDirectLeftRecursionLite(comptime rules: []const NamedRule) []const NamedRule {
    comptime {
        var out: []const NamedRule = &.{};
        for (rules, 0..) |nr, i| {
            const self_idx: u16 = @intCast(i);
            const rewritten = rewriteDirectLeftRecursionRuleLite(rules, nr.rule, self_idx);
            if (startsWithSelfRef(nr.rule, self_idx) and startsWithSelfRef(rewritten, self_idx)) {
                @compileError("left_recursion_mode=.rewrite could not rewrite rule '" ++ nr.name ++ "'; supported shape is: A <- A tail / base");
            }
            out = out ++ &[_]NamedRule{.{
                .name = nr.name,
                .rule = rewritten,
                .silent = nr.silent,
                .squashed = nr.squashed,
                .memo_mode = nr.memo_mode,
            }};
        }
        return out;
    }
}

fn runGrammarLint(comptime rules: []const NamedRule, comptime options: CompileOptions) void {
    comptime {
        if (options.lint_mode == .off) return;
        const diagnostics = collectGrammarLint(rules);
        if (diagnostics.len == 0) return;

        if (options.lint_mode == .warn) {
            // Zig 0.15 treats `@compileLog` as a hard compile error.
            // Keep warn mode non-failing; callers can fetch diagnostics via `peg.lint(...)`.
            return;
        }

        var message: []const u8 = "PEG strict lint failed:\n";
        for (diagnostics) |d| {
            message = message ++ " - [" ++ @tagName(d.kind) ++ "] " ++ d.rule ++ ": " ++ d.message ++ "\n";
        }
        @compileError(message);
    }
}

fn collectGrammarLint(comptime rules: []const NamedRule) []const LintDiagnostic {
    comptime {
        if (rules.len == 0) return &.{};

        var diags: []const LintDiagnostic = &.{};
        var referenced: [rules.len]bool = [_]bool{false} ** rules.len;
        var reachable: [rules.len]bool = [_]bool{false} ** rules.len;

        for (rules) |nr| collectReferenced(nr.rule, &referenced);
        markReachableFrom(rules, 0, &reachable);

        if (rules.len > 1) {
            var i: usize = 1;
            while (i < rules.len) : (i += 1) {
                if (!referenced[i]) {
                    diags = diags ++ &[_]LintDiagnostic{.{
                        .kind = .unused_rule,
                        .rule = rules[i].name,
                        .message = "rule is never referenced by other rules",
                    }};
                }
                if (!reachable[i]) {
                    diags = diags ++ &[_]LintDiagnostic{.{
                        .kind = .unreachable_rule,
                        .rule = rules[i].name,
                        .message = "rule is not reachable from start rule",
                    }};
                }
            }
        }

        var seen_nullable: [rules.len]bool = [_]bool{false} ** rules.len;
        var active_nullable: [rules.len]bool = [_]bool{false} ** rules.len;
        var nullable_cache: [rules.len]bool = [_]bool{false} ** rules.len;
        for (rules, 0..) |nr, i| {
            const self_idx: u16 = @intCast(i);
            if (startsWithSelfRef(nr.rule, self_idx)) {
                diags = diags ++ &[_]LintDiagnostic{.{
                    .kind = .direct_left_recursion,
                    .rule = nr.name,
                    .message = "rule starts with itself (direct left recursion); use left_recursion_mode=.rewrite or rewrite to iterative form",
                }};
            }
            if (ruleMayMatchEmpty(rules, nr.rule, &seen_nullable, &active_nullable, &nullable_cache)) {
                diags = diags ++ &[_]LintDiagnostic{.{
                    .kind = .nullable_rule,
                    .rule = nr.name,
                    .message = "rule may match empty input; verify this is intentional",
                }};
            }
            if (suspiciousChoiceOrder(nr.rule)) {
                diags = diags ++ &[_]LintDiagnostic{.{
                    .kind = .suspicious_choice_order,
                    .rule = nr.name,
                    .message = "choice may shadow specific alternatives (general before narrow)",
                }};
            }
        }

        return diags;
    }
}

fn collectReferenced(comptime rule: Rule, referenced: anytype) void {
    comptime {
        switch (rule) {
            .ref => |idx| referenced[idx] = true,
            .sequence => |seq| for (seq) |part| collectReferenced(part, referenced),
            .choice => |alts| for (alts) |alt| collectReferenced(alt, referenced),
            .zero_or_more => |r| collectReferenced(r[0], referenced),
            .one_or_more => |r| collectReferenced(r[0], referenced),
            .optional => |r| collectReferenced(r[0], referenced),
            .repeat_range => |rr| collectReferenced(rr.rule[0], referenced),
            .not => |r| collectReferenced(r[0], referenced),
            .amp => |r| collectReferenced(r[0], referenced),
            else => {},
        }
    }
}

fn markReachableFrom(comptime rules: []const NamedRule, comptime idx: usize, reachable: anytype) void {
    comptime {
        if (idx >= rules.len) return;
        if (reachable[idx]) return;
        reachable[idx] = true;
        walkRuleRefs(rules, rules[idx].rule, reachable);
    }
}

fn walkRuleRefs(comptime rules: []const NamedRule, comptime rule: Rule, reachable: anytype) void {
    comptime {
        switch (rule) {
            .ref => |idx| markReachableFrom(rules, idx, reachable),
            .sequence => |seq| for (seq) |part| walkRuleRefs(rules, part, reachable),
            .choice => |alts| for (alts) |alt| walkRuleRefs(rules, alt, reachable),
            .zero_or_more => |r| walkRuleRefs(rules, r[0], reachable),
            .one_or_more => |r| walkRuleRefs(rules, r[0], reachable),
            .optional => |r| walkRuleRefs(rules, r[0], reachable),
            .repeat_range => |rr| walkRuleRefs(rules, rr.rule[0], reachable),
            .not => |r| walkRuleRefs(rules, r[0], reachable),
            .amp => |r| walkRuleRefs(rules, r[0], reachable),
            else => {},
        }
    }
}

fn ruleMayMatchEmpty(
    comptime rules: []const NamedRule,
    comptime rule: Rule,
    seen: anytype,
    active: anytype,
    cache: anytype,
) bool {
    comptime {
        return switch (rule) {
            .literal => |lit| lit.len == 0,
            .literal_ic => |lit| lit.len == 0,
            .char_class, .neg_char_class, .dot => false,
            .sequence => |seq| blk: {
                for (seq) |part| {
                    if (!ruleMayMatchEmpty(rules, part, seen, active, cache)) break :blk false;
                }
                break :blk true;
            },
            .choice => |alts| blk: {
                for (alts) |alt| {
                    if (ruleMayMatchEmpty(rules, alt, seen, active, cache)) break :blk true;
                }
                break :blk false;
            },
            .zero_or_more, .optional => true,
            .one_or_more => |r| ruleMayMatchEmpty(rules, r[0], seen, active, cache),
            .repeat_range => |rr| if (rr.min == 0) true else ruleMayMatchEmpty(rules, rr.rule[0], seen, active, cache),
            .not, .amp => true,
            .ref => |idx| blk: {
                if (active[idx]) break :blk false;
                if (seen[idx]) break :blk cache[idx];
                active[idx] = true;
                const v = ruleMayMatchEmpty(rules, rules[idx].rule, seen, active, cache);
                active[idx] = false;
                seen[idx] = true;
                cache[idx] = v;
                break :blk v;
            },
        };
    }
}

fn suspiciousChoiceOrder(comptime rule: Rule) bool {
    comptime {
        return switch (rule) {
            .choice => |alts| blk: {
                var i: usize = 0;
                while (i < alts.len) : (i += 1) {
                    var j: usize = i + 1;
                    while (j < alts.len) : (j += 1) {
                        if (choiceAltShadows(alts[i], alts[j])) break :blk true;
                    }
                }
                break :blk false;
            },
            .sequence => |seq| blk: {
                for (seq) |part| {
                    if (suspiciousChoiceOrder(part)) break :blk true;
                }
                break :blk false;
            },
            .zero_or_more => |r| suspiciousChoiceOrder(r[0]),
            .one_or_more => |r| suspiciousChoiceOrder(r[0]),
            .optional => |r| suspiciousChoiceOrder(r[0]),
            .repeat_range => |rr| suspiciousChoiceOrder(rr.rule[0]),
            .not => |r| suspiciousChoiceOrder(r[0]),
            .amp => |r| suspiciousChoiceOrder(r[0]),
            else => false,
        };
    }
}

fn choiceAltShadows(comptime lhs: Rule, comptime rhs: Rule) bool {
    comptime {
        return switch (lhs) {
            .dot => true,
            .literal => |a| switch (rhs) {
                .literal => |b| std.mem.startsWith(u8, b, a),
                else => false,
            },
            .literal_ic => |a| switch (rhs) {
                .literal_ic => |b| icaseStartsWith(b, a),
                .literal => |b| icaseStartsWith(b, a),
                else => false,
            },
            else => false,
        };
    }
}

fn icaseStartsWith(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i < needle.len) : (i += 1) {
        if (std.ascii.toLower(haystack[i]) != std.ascii.toLower(needle[i])) return false;
    }
    return true;
}

// --- Utilities ---

fn writeEscapedExpected(writer: anytype, expected: []const u8) !void {
    const max_len: usize = 80;
    const limit = @min(expected.len, max_len);
    for (expected[0..limit]) |c| {
        switch (c) {
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            else => {
                if (std.ascii.isPrint(c)) {
                    try writer.writeByte(c);
                } else {
                    try writer.print("\\x{X:0>2}", .{c});
                }
            },
        }
    }
    if (expected.len > max_len) try writer.writeAll("...");
}

fn writeJsonString(writer: anytype, s: []const u8) !void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (std.ascii.isPrint(c)) {
                    try writer.writeByte(c);
                } else {
                    try writer.print("\\u{X:0>4}", .{@as(u16, c)});
                }
            },
        }
    }
    try writer.writeByte('"');
}

pub fn writeTreeJson(writer: anytype, node: Node) !void {
    try writer.writeAll("{\"tag\":");
    try writeJsonString(writer, node.tag);
    try writer.writeAll(",\"text\":");
    try writeJsonString(writer, node.text);
    try writer.writeAll(",\"children\":[");
    for (node.children, 0..) |child, i| {
        if (i != 0) try writer.writeAll(",");
        try writeTreeJson(writer, child);
    }
    try writer.writeAll("]}");
}

pub fn treeJsonAlloc(allocator: std.mem.Allocator, node: Node) ![]const u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buf.deinit(allocator);
    try writeTreeJson(buf.writer(allocator), node);
    return try buf.toOwnedSlice(allocator);
}

pub fn freeNode(allocator: std.mem.Allocator, node: Node) void {
    for (node.children) |child| {
        freeNode(allocator, child);
    }
    if (node.children.len > 0) {
        allocator.free(@constCast(node.children));
    }
}

pub fn printTree(node: Node, indent: usize) void {
    for (0..indent) |_| std.debug.print("  ", .{});
    std.debug.print("{s}: \"{s}\"\n", .{ node.tag, node.text });
    for (node.children) |child| printTree(child, indent + 1);
}

fn materializeNodePoolWithAllocator(allocator: std.mem.Allocator) !void {
    var pool = NodePool.init(allocator);
    defer pool.deinit();

    const leaf = try pool.add("leaf", "x", &.{});
    const parent_child_indices = try allocator.dupe(u32, &[_]u32{ leaf, leaf, leaf, leaf });
    const parent = try pool.add("root", "x", parent_child_indices);

    const node = try pool.materialize(parent);
    defer freeNode(allocator, node);
}

test "NodePool.materialize cleans partial allocations on OOM" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        materializeNodePoolWithAllocator,
        .{},
    );
}

test "memo key position overflow returns deterministic parse error" {
    const g = comptime compile(
        \\start <- 'a'
    );
    var engine = Engine.init(g.rules, std.testing.allocator, .{});
    defer engine.deinit();

    const overflow_pos = @as(usize, std.math.maxInt(u32)) + 1;
    const res = try engine.matchRef(0, "a", overflow_pos);
    switch (res) {
        .ok => return error.ShouldHaveFailed,
        .err => |e| {
            try std.testing.expectEqual(overflow_pos, e.pos);
            try std.testing.expectEqualStrings("input position exceeds memo key range", e.expected);
        },
    }
}

pub const NodeIterator = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayListUnmanaged(Node) = .{},

    pub fn init(allocator: std.mem.Allocator, root: Node) !NodeIterator {
        var it = NodeIterator{ .allocator = allocator };
        try it.stack.append(allocator, root);
        return it;
    }

    pub fn deinit(self: *NodeIterator) void {
        self.stack.deinit(self.allocator);
    }

    pub fn next(self: *NodeIterator) !?Node {
        if (self.stack.items.len == 0) return null;
        const node = self.stack.pop() orelse return null;
        var i: usize = node.children.len;
        while (i > 0) {
            i -= 1;
            try self.stack.append(self.allocator, node.children[i]);
        }
        return node;
    }
};

// --- Tree Walker ---

pub fn Walker(comptime Result: type, comptime Context: type) type {
    return struct {
        const Self = @This();
        pub const Action = *const fn (node: Node, children: []const Result, ctx: Context) anyerror!Result;

        actions: []const struct {
            tag: []const u8,
            func: Action,
        },
        default: ?Action = null,
        allocator: std.mem.Allocator,

        pub fn walk(self: Self, node: Node, ctx: Context) anyerror!Result {
            var child_results: std.ArrayListUnmanaged(Result) = .{};
            defer child_results.deinit(self.allocator);

            for (node.children) |child| {
                try child_results.append(self.allocator, try self.walk(child, ctx));
            }

            for (self.actions) |a| {
                if (std.mem.eql(u8, a.tag, node.tag))
                    return a.func(node, child_results.items, ctx);
            }

            if (self.default) |d|
                return d(node, child_results.items, ctx);

            return error.NoActionForTag;
        }
    };
}