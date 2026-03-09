const std = @import("std");
const peg = @import("peg");

const basic = peg.compileWithOptions(
    \\program    <- _ws (line _ws)*
    \\line       <- linenum _ws stmt
    \\linenum    <- _digits
    \\stmt       <- print / let / ifthen / goto / gosub / ret / end / rem
    \\
    \\print      <- 'PRINT'i ![a-zA-Z0-9_] _ws printlist
    \\printlist  <- expr (_ws ';' _ws expr)*
    \\
    \\let        <- 'LET'i ![a-zA-Z0-9_] _ws assign
    \\assign     <- varname _ws '=' _ws expr
    \\
    \\ifthen     <- 'IF'i ![a-zA-Z0-9_] _ws expr _ws 'THEN'i ![a-zA-Z0-9_] _ws stmt
    \\
    \\goto       <- 'GOTO'i ![a-zA-Z0-9_] _ws _digits
    \\gosub      <- 'GOSUB'i ![a-zA-Z0-9_] _ws _digits
    \\ret        <- 'RETURN'i ![a-zA-Z0-9_]
    \\end        <- 'END'i ![a-zA-Z0-9_]
    \\rem        <- 'REM'i [^\n]*
    \\
    \\expr       <- comparison
    \\comparison <- sum (_ws cmp_op _ws sum)?
    \\cmp_op     <- '<=' / '>=' / '<>' / '<' / '>' / '='
    \\sum        <- sum _ws add_op _ws product / product
    \\add_op     <- '+' / '-'
    \\product    <- product _ws mul_op _ws unary / unary
    \\mul_op     <- '*' / '/' / '%'
    \\unary      <- neg / atom
    \\neg        <- '-' _ws atom
    \\atom       <- number / string / var / '(' _ws expr _ws ')'
    \\
    \\number     <- _digits ('.' _digits)?
    \\string     <- '"' [^"]* '"'
    \\var        <- _var
    \\varname    <- _var
    \\
    \\@silent @memo_off _var    <- [a-zA-Z] [a-zA-Z0-9_]* '$'?
    \\@silent @memo_off _digits <- [0-9]+
    \\@silent _ws        <- [ \t\n\r]*
,
    .{ .left_recursion_mode = .rewrite }
);

// --- Value type ---

const Value = union(enum) {
    int: i64,
    float: f64,
    str: []const u8,
    boolean: bool,

    fn asInt(self: Value) i64 {
        return switch (self) {
            .int => |v| v,
            .float => |v| @intFromFloat(v),
            .boolean => |v| if (v) @as(i64, 1) else 0,
            .str => 0,
        };
    }

    fn asFloat(self: Value) f64 {
        return switch (self) {
            .int => |v| @floatFromInt(v),
            .float => |v| v,
            .boolean => |v| if (v) @as(f64, 1.0) else 0.0,
            .str => 0.0,
        };
    }

    fn isTrue(self: Value) bool {
        return switch (self) {
            .int => |v| v != 0,
            .float => |v| v != 0.0,
            .boolean => |v| v,
            .str => |v| v.len > 0,
        };
    }

    fn isFloaty(self: Value) bool {
        return switch (self) {
            .float => true,
            else => false,
        };
    }

    fn opChar(self: Value) u8 {
        if (self == .str and self.str.len > 0) return self.str[0];
        return 0;
    }

    fn format(self: Value, buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) !void {
        var tmp: [64]u8 = undefined;
        const s = switch (self) {
            .int => |v| std.fmt.bufPrint(&tmp, "{}", .{v}) catch "?",
            .float => |v| std.fmt.bufPrint(&tmp, "{d:.6}", .{v}) catch "?",
            .boolean => |v| if (v) "1" else "0",
            .str => |v| v,
        };
        try buf.appendSlice(allocator, s);
    }
};

// --- Environment ---

const Env = struct {
    vars: std.StringHashMapUnmanaged(Value),
    output: std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) Env {
        return .{
            .vars = .{},
            .output = .{},
            .allocator = allocator,
        };
    }

    fn set(self: *Env, name: []const u8, val: Value) !void {
        try self.vars.put(self.allocator, name, val);
    }

    fn get(self: *Env, name: []const u8) Value {
        return self.vars.get(name) orelse Value{ .int = 0 };
    }

    fn printVal(self: *Env, val: Value) !void {
        try val.format(&self.output, self.allocator);
    }

    fn println(self: *Env) !void {
        try self.output.append(self.allocator, '\n');
    }

    fn getOutput(self: *Env) []const u8 {
        return self.output.items;
    }
};

// --- Walker ---

const BasicWalker = peg.Walker(Value, *Env);

fn walkProgram(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len > 0) return children[children.len - 1];
    return Value{ .int = 0 };
}

fn walkLine(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len > 0) return children[children.len - 1];
    return Value{ .int = 0 };
}

fn walkLinenum(_: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    return Value{ .int = 0 };
}

fn walkStmt(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len > 0) return children[0];
    return Value{ .int = 0 };
}

fn walkPrint(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len > 0) return children[0];
    return Value{ .int = 0 };
}

fn walkPrintlist(_: peg.Node, children: []const Value, env: *Env) anyerror!Value {
    for (children) |val| {
        try env.printVal(val);
    }
    try env.println();
    return Value{ .int = 0 };
}

fn walkLet(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len > 0) return children[0];
    return Value{ .int = 0 };
}

fn walkAssign(node: peg.Node, children: []const Value, env: *Env) anyerror!Value {
    const var_name = findChildTag(node, "varname");
    if (children.len >= 2) {
        try env.set(var_name, children[1]);
        return children[1];
    }
    return Value{ .int = 0 };
}

fn walkVarname(node: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    return Value{ .str = node.text };
}

fn walkIfthen(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len >= 2) return children[1];
    return Value{ .int = 0 };
}

fn walkGoto(_: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    return Value{ .int = 0 };
}

fn walkGosub(_: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    return Value{ .int = 0 };
}

fn walkRet(_: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    return Value{ .int = 0 };
}

fn walkEnd(_: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    return Value{ .int = 0 };
}

fn walkRem(_: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    return Value{ .int = 0 };
}

fn walkExpr(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len > 0) return children[0];
    return Value{ .int = 0 };
}

fn walkComparison(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len < 3) {
        if (children.len == 1) return children[0];
        return Value{ .int = 0 };
    }
    const left = children[0];
    const op_val = children[1];
    const right = children[2];
    const op = if (op_val == .str) op_val.str else "=";
    const a = left.asFloat();
    const b = right.asFloat();
    const result = if (std.mem.eql(u8, op, "="))
        a == b
    else if (std.mem.eql(u8, op, "<>"))
        a != b
    else if (std.mem.eql(u8, op, "<"))
        a < b
    else if (std.mem.eql(u8, op, ">"))
        a > b
    else if (std.mem.eql(u8, op, "<="))
        a <= b
    else if (std.mem.eql(u8, op, ">="))
        a >= b
    else
        false;
    return Value{ .boolean = result };
}

fn walkCmpOp(node: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    return Value{ .str = node.text };
}

fn walkSum(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len == 0) return Value{ .int = 0 };
    var result = children[0];
    var i: usize = 1;
    while (i + 1 < children.len) : (i += 2) {
        const op = children[i].opChar();
        const right = children[i + 1];
        if (result.isFloaty() or right.isFloaty()) {
            const a = result.asFloat();
            const b = right.asFloat();
            result = Value{ .float = if (op == '-') a - b else a + b };
        } else {
            const a = result.asInt();
            const b = right.asInt();
            result = Value{ .int = if (op == '-') a - b else a + b };
        }
    }
    return result;
}

fn walkAddOp(node: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    return Value{ .str = node.text };
}

fn walkProduct(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len == 0) return Value{ .int = 0 };
    var result = children[0];
    var i: usize = 1;
    while (i + 1 < children.len) : (i += 2) {
        const op = children[i].opChar();
        const right = children[i + 1];
        if (result.isFloaty() or right.isFloaty()) {
            const a = result.asFloat();
            const b = right.asFloat();
            result = Value{ .float = if (op == '*') a * b else if (op == '/') a / b else @mod(a, b) };
        } else {
            const a = result.asInt();
            const b = right.asInt();
            if (op == '*') {
                result = Value{ .int = a * b };
            } else if (op == '/') {
                if (b == 0) return error.DivisionByZero;
                result = Value{ .int = @divTrunc(a, b) };
            } else {
                if (b == 0) return error.DivisionByZero;
                result = Value{ .int = @mod(a, b) };
            }
        }
    }
    return result;
}

fn walkMulOp(node: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    return Value{ .str = node.text };
}

fn walkUnary(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len > 0) return children[0];
    return Value{ .int = 0 };
}

fn walkNeg(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len > 0) {
        return switch (children[0]) {
            .int => |n| Value{ .int = -n },
            .float => |n| Value{ .float = -n },
            else => Value{ .int = 0 },
        };
    }
    return Value{ .int = 0 };
}

fn walkAtom(_: peg.Node, children: []const Value, _: *Env) anyerror!Value {
    if (children.len > 0) return children[0];
    return Value{ .int = 0 };
}

fn walkNumber(node: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    if (std.mem.indexOf(u8, node.text, ".") != null) {
        const f = std.fmt.parseFloat(f64, node.text) catch 0.0;
        return Value{ .float = f };
    }
    const n = std.fmt.parseInt(i64, node.text, 10) catch 0;
    return Value{ .int = n };
}

fn walkString(node: peg.Node, _: []const Value, _: *Env) anyerror!Value {
    if (node.text.len >= 2) {
        return Value{ .str = node.text[1 .. node.text.len - 1] };
    }
    return Value{ .str = "" };
}

fn walkVar(node: peg.Node, _: []const Value, env: *Env) anyerror!Value {
    return env.get(node.text);
}

// --- Tree helpers ---

fn findChildTag(node: peg.Node, tag: []const u8) []const u8 {
    for (node.children) |child| {
        if (std.mem.eql(u8, child.tag, tag)) return child.text;
        const r = findChildTag(child, tag);
        if (r.len > 0) return r;
    }
    return "";
}

fn findNodeByTag(node: peg.Node, tag: []const u8) ?peg.Node {
    if (std.mem.eql(u8, node.tag, tag)) return node;
    for (node.children) |child| {
        if (findNodeByTag(child, tag)) |found| return found;
    }
    return null;
}

fn findStmtTagStatic(node: peg.Node) []const u8 {
    if (std.mem.eql(u8, node.tag, "goto") or
        std.mem.eql(u8, node.tag, "gosub") or
        std.mem.eql(u8, node.tag, "ret") or
        std.mem.eql(u8, node.tag, "end") or
        std.mem.eql(u8, node.tag, "ifthen"))
    {
        return node.tag;
    }
    for (node.children) |child| {
        const r = findStmtTagStatic(child);
        if (r.len > 0) return r;
    }
    return "";
}

fn findGotoTargetStatic(node: peg.Node) ?usize {
    if (std.mem.eql(u8, node.tag, "goto") or std.mem.eql(u8, node.tag, "gosub")) {
        var i = node.text.len;
        while (i > 0 and node.text[i - 1] >= '0' and node.text[i - 1] <= '9') : (i -= 1) {}
        if (i < node.text.len) {
            return std.fmt.parseInt(usize, node.text[i..], 10) catch null;
        }
    }
    for (node.children) |child| {
        const r = findGotoTargetStatic(child);
        if (r != null) return r;
    }
    return null;
}

fn findInnerStmtTag(node: peg.Node) []const u8 {
    if (std.mem.eql(u8, node.tag, "ifthen")) {
        for (node.children) |child| {
            if (std.mem.eql(u8, child.tag, "stmt")) {
                return findStmtTagStatic(child);
            }
        }
    }
    for (node.children) |child| {
        const r = findInnerStmtTag(child);
        if (r.len > 0) return r;
    }
    return "";
}

fn makeInterpreter(allocator: std.mem.Allocator) BasicWalker {
    return BasicWalker{
        .actions = &.{
            .{ .tag = "program", .func = walkProgram },
            .{ .tag = "line", .func = walkLine },
            .{ .tag = "linenum", .func = walkLinenum },
            .{ .tag = "stmt", .func = walkStmt },
            .{ .tag = "print", .func = walkPrint },
            .{ .tag = "printlist", .func = walkPrintlist },
            .{ .tag = "let", .func = walkLet },
            .{ .tag = "assign", .func = walkAssign },
            .{ .tag = "varname", .func = walkVarname },
            .{ .tag = "ifthen", .func = walkIfthen },
            .{ .tag = "goto", .func = walkGoto },
            .{ .tag = "gosub", .func = walkGosub },
            .{ .tag = "ret", .func = walkRet },
            .{ .tag = "end", .func = walkEnd },
            .{ .tag = "rem", .func = walkRem },
            .{ .tag = "expr", .func = walkExpr },
            .{ .tag = "comparison", .func = walkComparison },
            .{ .tag = "cmp_op", .func = walkCmpOp },
            .{ .tag = "sum", .func = walkSum },
            .{ .tag = "add_op", .func = walkAddOp },
            .{ .tag = "product", .func = walkProduct },
            .{ .tag = "mul_op", .func = walkMulOp },
            .{ .tag = "unary", .func = walkUnary },
            .{ .tag = "neg", .func = walkNeg },
            .{ .tag = "atom", .func = walkAtom },
            .{ .tag = "number", .func = walkNumber },
            .{ .tag = "string", .func = walkString },
            .{ .tag = "var", .func = walkVar },
        },
        .allocator = allocator,
    };
}

// --- Line-based Executor for GOTO/GOSUB ---

const LineInfo = struct {
    node: peg.Node,
    linenum: usize,
};

const Executor = struct {
    lines: std.ArrayListUnmanaged(LineInfo),
    label_map: std.AutoHashMapUnmanaged(usize, usize),
    call_stack: std.ArrayListUnmanaged(usize),
    env: *Env,
    walker: BasicWalker,
    allocator: std.mem.Allocator,

    fn evalCondition(self: *Executor, line_node: peg.Node) !bool {
        const ifthen_node = findNodeByTag(line_node, "ifthen") orelse return false;
        for (ifthen_node.children) |child| {
            if (std.mem.eql(u8, child.tag, "expr")) {
                const val = try self.walker.walk(child, self.env);
                return val.isTrue();
            }
        }
        return false;
    }

    fn run(self: *Executor) !void {
        var pc: usize = 0;
        var steps: usize = 0;
        const max_steps: usize = 10000;

        while (pc < self.lines.items.len) {
            steps += 1;
            if (steps > max_steps) return error.InfiniteLoop;

            const line = self.lines.items[pc];
            const stmt_tag = findStmtTagStatic(line.node);

            if (std.mem.eql(u8, stmt_tag, "goto")) {
                const target = findGotoTargetStatic(line.node) orelse return error.LabelNotFound;
                pc = self.label_map.get(target) orelse return error.LabelNotFound;
                continue;
            }

            if (std.mem.eql(u8, stmt_tag, "gosub")) {
                const target = findGotoTargetStatic(line.node) orelse return error.LabelNotFound;
                try self.call_stack.append(self.allocator, pc + 1);
                pc = self.label_map.get(target) orelse return error.LabelNotFound;
                continue;
            }

            if (std.mem.eql(u8, stmt_tag, "ret")) {
                if (self.call_stack.items.len == 0) return error.ReturnWithoutGosub;
                pc = self.call_stack.pop().?;
                continue;
            }

            if (std.mem.eql(u8, stmt_tag, "end")) {
                return;
            }

            if (std.mem.eql(u8, stmt_tag, "ifthen")) {
                const cond = try self.evalCondition(line.node);
                if (cond) {
                    const inner_tag = findInnerStmtTag(line.node);
                    if (std.mem.eql(u8, inner_tag, "goto")) {
                        const target = findGotoTargetStatic(line.node) orelse return error.LabelNotFound;
                        pc = self.label_map.get(target) orelse return error.LabelNotFound;
                        continue;
                    }
                    if (std.mem.eql(u8, inner_tag, "gosub")) {
                        const target = findGotoTargetStatic(line.node) orelse return error.LabelNotFound;
                        try self.call_stack.append(self.allocator, pc + 1);
                        pc = self.label_map.get(target) orelse return error.LabelNotFound;
                        continue;
                    }
                    if (std.mem.eql(u8, inner_tag, "end")) {
                        return;
                    }
                    _ = try self.walker.walk(line.node, self.env);
                }
                pc += 1;
                continue;
            }

            _ = try self.walker.walk(line.node, self.env);
            pc += 1;
        }
    }
};

fn parseLinenumFromNode(line_node: peg.Node) usize {
    for (line_node.children) |child| {
        if (std.mem.eql(u8, child.tag, "linenum")) {
            return std.fmt.parseInt(usize, std.mem.trim(u8, child.text, " \t"), 10) catch 0;
        }
    }
    return 0;
}

fn initExecutor(allocator: std.mem.Allocator, program_node: peg.Node, env: *Env) !Executor {
    var ex = Executor{
        .lines = .{},
        .label_map = .{},
        .call_stack = .{},
        .env = env,
        .walker = makeInterpreter(allocator),
        .allocator = allocator,
    };

    // Collect lines and sort by line number
    var raw_lines = std.ArrayListUnmanaged(LineInfo){};
    for (program_node.children) |child| {
        if (std.mem.eql(u8, child.tag, "line")) {
            const num = parseLinenumFromNode(child);
            try raw_lines.append(allocator, .{ .node = child, .linenum = num });
        }
    }

    // Sort by line number (classic BASIC executes in line number order)
    std.mem.sort(LineInfo, raw_lines.items, {}, struct {
        fn lessThan(_: void, a: LineInfo, b: LineInfo) bool {
            return a.linenum < b.linenum;
        }
    }.lessThan);

    for (raw_lines.items, 0..) |li, idx| {
        try ex.lines.append(allocator, li);
        try ex.label_map.put(allocator, li.linenum, idx);
    }

    return ex;
}

// --- Run helpers ---

const RunResult = struct {
    output: []const u8,
    env: *Env,
    arena: std.heap.ArenaAllocator,
};

fn runBasic(input: []const u8) !RunResult {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();
    const result = try basic.parse(alloc, "program", input);
    const env = try alloc.create(Env);
    env.* = Env.init(alloc);
    var executor = try initExecutor(alloc, result.node, env);
    try executor.run();
    return .{ .output = env.getOutput(), .env = env, .arena = arena };
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var r = try runBasic(input);
    defer r.arena.deinit();
    const actual = std.mem.trimRight(u8, r.output, "\n");
    std.debug.print("  Output: \"{s}\"\n", .{actual});
    try std.testing.expectEqualStrings(expected, actual);
}

fn expectVar(input: []const u8, name: []const u8, expected: i64) !void {
    var r = try runBasic(input);
    defer r.arena.deinit();
    const val = r.env.get(name);
    std.debug.print("  {s} = {}\n", .{ name, val.asInt() });
    try std.testing.expectEqual(expected, val.asInt());
}

fn expectParse(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try basic.parse(arena.allocator(), "program", input);
    try std.testing.expect(result.pos == input.len);
    std.debug.print("  OK\n", .{});
}

fn expectParseCases(cases: []const []const u8) !void {
    for (cases) |input| try expectParse(input);
}

// ===================== TESTS =====================

// --- Parse tests ---

test "empty program" {
    std.debug.print("\n-- basic: empty --\n", .{});
    try expectParse("");
    try expectParse("   ");
    try expectParse("\n\n");
}

test "print statements" {
    std.debug.print("\n-- basic: print parse --\n", .{});
    try expectParseCases(&.{
        "10 PRINT 42",
        "10 PRINT \"hello\"",
        "10 PRINT 1 + 2",
        "10 PRINT x",
        "10 PRINT 1; 2; 3",
    });
}

test "case insensitive keywords" {
    std.debug.print("\n-- basic: case insensitive --\n", .{});
    try expectParseCases(&.{
        "10 PRINT 1",
        "10 print 1",
        "10 Print 1",
        "10 pRiNt 1",
        "10 LET x = 1",
        "10 let x = 1",
        "10 Let X = 1",
        "10 IF 1 THEN END",
        "10 if 1 then end",
        "10 If 1 Then End",
    });
}

test "let statements" {
    std.debug.print("\n-- basic: let parse --\n", .{});
    try expectParseCases(&.{
        "10 LET x = 10",
        "10 LET name$ = \"hello\"",
        "10 LET result = 2 + 3 * 4",
        "10 LET a = b + c",
    });
}

test "if then" {
    std.debug.print("\n-- basic: if parse --\n", .{});
    try expectParse("10 IF x > 0 THEN PRINT x");
    try expectParse("10 IF a = b THEN END");
    try expectParse("10 IF 1 THEN LET x = 2");
    try expectParse("10 IF x <> 0 THEN PRINT \"nonzero\"");
    try expectParse("10 IF x <= 10 THEN PRINT x");
    try expectParse("10 IF x >= 5 THEN PRINT \"big\"");
}

test "goto and gosub" {
    std.debug.print("\n-- basic: goto parse --\n", .{});
    try expectParse("10 GOTO 100");
    try expectParse("10 PRINT \"hello\"\n20 GOTO 10");
    try expectParse("10 GOSUB 100");
    try expectParse("10 RETURN");
}

test "rem comments" {
    std.debug.print("\n-- basic: rem --\n", .{});
    try expectParse("10 REM this is a comment");
    try expectParse("10 rem also a comment");
    try expectParse("10 REM\n20 PRINT 1");
}

test "expressions" {
    std.debug.print("\n-- basic: expr parse --\n", .{});
    try expectParseCases(&.{
        "10 PRINT 1 + 2",
        "10 PRINT 3 * 4 + 5",
        "10 PRINT (1 + 2) * 3",
        "10 PRINT -5",
        "10 PRINT 10 / 3",
        "10 PRINT 10 % 3",
        "10 PRINT 3.14",
        "10 PRINT 1.5 + 2.5",
    });
}

test "multi-line program" {
    std.debug.print("\n-- basic: multi-line parse --\n", .{});
    try expectParse(
        \\10 LET x = 10
        \\20 LET y = 20
        \\30 PRINT x + y
        \\40 END
    );
}

test "keyword boundary" {
    std.debug.print("\n-- basic: keyword boundary --\n", .{});
    try expectParseCases(&.{
        "10 LET PRINTER = 1",
        "10 LET LETTER = 2",
        "10 LET IFFY = 3",
        "10 LET ENDING = 4",
        "10 LET GOTOWN = 5",
    });
}

test "tree structure" {
    std.debug.print("\n-- basic: tree --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try basic.parse(arena.allocator(), "program",
        \\10 LET x = 1 + 2
        \\20 PRINT x
    );
    peg.printTree(result.node, 2);
}

// --- Eval tests ---

test "eval print number" {
    std.debug.print("\n-- basic: eval print --\n", .{});
    try expectOutput("10 PRINT 42", "42");
    try expectOutput("10 PRINT 0", "0");
    try expectOutput("10 PRINT -7", "-7");
}

test "eval print string" {
    std.debug.print("\n-- basic: eval print string --\n", .{});
    try expectOutput("10 PRINT \"hello\"", "hello");
    try expectOutput("10 PRINT \"hello world\"", "hello world");
    try expectOutput("10 PRINT \"\"", "");
}

test "eval print expression" {
    std.debug.print("\n-- basic: eval print expr --\n", .{});
    try expectOutput("10 PRINT 1 + 2", "3");
    try expectOutput("10 PRINT 10 - 3", "7");
    try expectOutput("10 PRINT 2 * 3", "6");
    try expectOutput("10 PRINT 10 / 3", "3");
    try expectOutput("10 PRINT 10 % 3", "1");
}

test "eval operator priority" {
    std.debug.print("\n-- basic: eval priority --\n", .{});
    try expectOutput("10 PRINT 2 + 3 * 4", "14");
    try expectOutput("10 PRINT (2 + 3) * 4", "20");
    try expectOutput("10 PRINT 10 - 2 * 3", "4");
}

test "eval negation" {
    std.debug.print("\n-- basic: eval neg --\n", .{});
    try expectOutput("10 PRINT -5", "-5");
    try expectOutput("10 PRINT -5 + 10", "5");
    try expectOutput("10 PRINT -(3 + 4)", "-7");
}

test "eval float" {
    std.debug.print("\n-- basic: eval float --\n", .{});
    try expectOutput("10 PRINT 3.14", "3.140000");
    try expectOutput("10 PRINT 1.5 + 2.5", "4.000000");
    try expectOutput("10 PRINT 10.0 / 4.0", "2.500000");
}

test "eval let and var" {
    std.debug.print("\n-- basic: eval let --\n", .{});
    try expectVar("10 LET x = 42", "x", 42);
    try expectVar(
        \\10 LET x = 10
        \\20 LET x = x + 5
    , "x", 15);
    try expectVar(
        \\10 LET a = 3
        \\20 LET b = 4
        \\30 LET c = a + b
    , "c", 7);
}

test "eval let and print" {
    std.debug.print("\n-- basic: eval let+print --\n", .{});
    try expectOutput(
        \\10 LET x = 10
        \\20 PRINT x
    , "10");
    try expectOutput(
        \\10 LET x = 3
        \\20 LET y = 4
        \\30 PRINT x + y
    , "7");
    try expectOutput(
        \\10 LET x = 10
        \\20 LET x = x * 2
        \\30 PRINT x
    , "20");
}

test "eval print semicolons" {
    std.debug.print("\n-- basic: eval print semi --\n", .{});
    try expectOutput("10 PRINT 1; 2; 3", "123");
    try expectOutput("10 PRINT \"a\"; \"b\"; \"c\"", "abc");
    try expectOutput("10 PRINT 1; \"+\"; 2; \"=\"; 3", "1+2=3");
}

test "eval if then true" {
    std.debug.print("\n-- basic: eval if true --\n", .{});
    try expectOutput("10 IF 1 > 0 THEN PRINT \"yes\"", "yes");
    try expectOutput(
        \\10 LET x = 10
        \\20 IF x > 5 THEN PRINT "big"
    , "big");
    try expectOutput("10 IF 5 = 5 THEN PRINT \"equal\"", "equal");
}

test "eval comparisons" {
    std.debug.print("\n-- basic: eval cmp --\n", .{});
    try expectOutput("10 IF 1 < 2 THEN PRINT \"yes\"", "yes");
    try expectOutput("10 IF 2 > 1 THEN PRINT \"yes\"", "yes");
    try expectOutput("10 IF 1 <= 1 THEN PRINT \"yes\"", "yes");
    try expectOutput("10 IF 1 >= 1 THEN PRINT \"yes\"", "yes");
    try expectOutput("10 IF 1 <> 2 THEN PRINT \"yes\"", "yes");
    try expectOutput("10 IF 1 = 1 THEN PRINT \"yes\"", "yes");
}

test "eval multi-line program" {
    std.debug.print("\n-- basic: eval program --\n", .{});
    try expectOutput(
        \\10 LET x = 10
        \\20 LET y = 20
        \\30 PRINT x + y
    , "30");
}

test "eval case insensitive" {
    std.debug.print("\n-- basic: eval case --\n", .{});
    try expectOutput("10 print 42", "42");
    try expectOutput(
        \\10 let x = 5
        \\20 print x
    , "5");
    try expectOutput("10 Print 1 + 2", "3");
}

test "eval complex program" {
    std.debug.print("\n-- basic: eval complex --\n", .{});
    try expectOutput(
        \\10 REM Compute area
        \\20 LET width = 5
        \\30 LET height = 3
        \\40 LET area = width * height
        \\50 PRINT "Area = "; area
    , "Area = 15");
}

test "eval fibonacci" {
    std.debug.print("\n-- basic: eval fib --\n", .{});
    try expectOutput(
        \\10 LET a = 0
        \\20 LET b = 1
        \\30 PRINT a
        \\40 PRINT b
        \\50 LET c = a + b
        \\60 PRINT c
        \\70 LET a = b
        \\80 LET b = c
        \\90 LET c = a + b
        \\100 PRINT c
        \\110 LET a = b
        \\120 LET b = c
        \\130 LET c = a + b
        \\140 PRINT c
    , "0\n1\n1\n2\n3");
}

// --- GOTO tests ---

test "goto skip" {
    std.debug.print("\n-- basic: goto skip --\n", .{});
    try expectOutput(
        \\10 PRINT "start"
        \\20 GOTO 40
        \\30 PRINT "skipped"
        \\40 PRINT "end"
    , "start\nend");
}

test "goto end" {
    std.debug.print("\n-- basic: goto end --\n", .{});
    try expectOutput(
        \\10 PRINT "hello"
        \\20 END
        \\30 PRINT "never"
    , "hello");
}

test "goto chain" {
    std.debug.print("\n-- basic: goto chain --\n", .{});
    try expectOutput(
        \\10 PRINT "a"
        \\20 GOTO 50
        \\30 PRINT "b"
        \\40 END
        \\50 PRINT "c"
        \\60 GOTO 30
    , "a\nc\nb");
}

test "goto out of order" {
    std.debug.print("\n-- basic: goto order --\n", .{});
    try expectOutput(
        \\30 PRINT "third"
        \\10 PRINT "first"
        \\20 PRINT "second"
    , "first\nsecond\nthird");
}

test "gosub return" {
    std.debug.print("\n-- basic: gosub --\n", .{});
    try expectOutput(
        \\10 PRINT "main"
        \\20 GOSUB 100
        \\30 PRINT "back"
        \\40 END
        \\100 PRINT "sub"
        \\110 RETURN
    , "main\nsub\nback");
}

test "gosub nested" {
    std.debug.print("\n-- basic: gosub nested --\n", .{});
    try expectOutput(
        \\10 GOSUB 100
        \\20 PRINT "done"
        \\30 END
        \\100 PRINT "a"
        \\110 GOSUB 200
        \\120 PRINT "c"
        \\130 RETURN
        \\200 PRINT "b"
        \\210 RETURN
    , "a\nb\nc\ndone");
}

test "goto loop with counter" {
    std.debug.print("\n-- basic: goto loop --\n", .{});
    try expectVar(
        \\10 LET i = 0
        \\20 LET i = i + 1
        \\30 IF i < 5 THEN GOTO 20
    , "i", 5);
}

test "goto countdown" {
    std.debug.print("\n-- basic: countdown --\n", .{});
    try expectOutput(
        \\10 LET n = 3
        \\20 PRINT n
        \\30 LET n = n - 1
        \\40 IF n > 0 THEN GOTO 20
    , "3\n2\n1");
}

test "goto if false no jump" {
    std.debug.print("\n-- basic: if false no jump --\n", .{});
    try expectOutput(
        \\10 LET x = 0
        \\20 IF x > 5 THEN GOTO 99
        \\30 PRINT "not jumped"
        \\40 END
        \\99 PRINT "jumped"
        \\100 END
    , "not jumped");
}

test "goto sum 1 to 5" {
    std.debug.print("\n-- basic: sum loop --\n", .{});
    try expectOutput(
        \\10 REM Sum 1 to 5
        \\20 LET sum = 0
        \\30 LET i = 1
        \\40 LET sum = sum + i
        \\50 LET i = i + 1
        \\60 IF i <= 5 THEN GOTO 40
        \\70 PRINT "Sum = "; sum
    , "Sum = 15");
}

test "gosub multiply" {
    std.debug.print("\n-- basic: gosub multiply --\n", .{});
    try expectOutput(
        \\10 LET a = 7
        \\20 LET b = 6
        \\30 GOSUB 100
        \\40 PRINT "Result = "; result
        \\50 END
        \\100 LET result = a * b
        \\110 RETURN
    , "Result = 42");
}

test "goto infinite loop protection" {
    std.debug.print("\n-- basic: infinite loop --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const result = try basic.parse(alloc, "program", "10 GOTO 10");
    const env = try alloc.create(Env);
    env.* = Env.init(alloc);

    var executor = try initExecutor(alloc, result.node, env);
    if (executor.run()) |_| {
        return error.ShouldHaveFailed;
    } else |err| {
        try std.testing.expect(err == error.InfiniteLoop);
        std.debug.print("  OK: infinite loop detected\n", .{});
    }
}

test "classic BASIC program" {
    std.debug.print("\n-- basic: classic program --\n", .{});
    try expectOutput(
        \\10 REM Classic BASIC
        \\20 PRINT "Hello, BASIC!"
        \\30 LET N = 1
        \\40 IF N > 5 THEN GOTO 80
        \\50 PRINT N
        \\60 LET N = N + 1
        \\70 GOTO 40
        \\80 PRINT "Done!"
    , "Hello, BASIC!\n1\n2\n3\n4\n5\nDone!");
}

test "detailed errors" {
    std.debug.print("\n-- basic: detailed errors --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const r1 = basic.parseDetailed(arena.allocator(), "program", "10 LET = 5");
    switch (r1) {
        .ok => |ok| {
            std.debug.print("  'LET = 5' partial, pos={}\n", .{ok.pos});
            try std.testing.expect(ok.pos < 10);
        },
        .err => |e| {
            std.debug.print("  'LET = 5' error at {}:{}: {s}\n", .{ e.line, e.col, e.expected });
        },
    }

    const r2 = basic.parseDetailed(arena.allocator(), "program", "10 PRINT 1 +");
    switch (r2) {
        .ok => |ok| {
            std.debug.print("  'PRINT 1 +' partial, pos={}\n", .{ok.pos});
        },
        .err => |e| {
            std.debug.print("  'PRINT 1 +' error at {}:{}: {s}\n", .{ e.line, e.col, e.expected });
        },
    }
}