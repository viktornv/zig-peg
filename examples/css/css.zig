const std = @import("std");
const peg = @import("peg");

const css = peg.compile(
    \\stylesheet <- _ws (rule _ws)*
    \\rule       <- selectors _ws '{' _ws (decl _ws)* '}'
    \\@squashed selectors <- selector (_ws ',' _ws selector)*
    \\selector   <- simple (_combinator simple)*
    \\simple     <- (element / class / id / universal / pseudo)+
    \\element    <- &[a-zA-Z] _ident
    \\class      <- '.' _ident
    \\id         <- '#' _ident
    \\universal  <- '*'
    \\pseudo     <- ':' _ident
    \\@silent @squashed _combinator <- _ws '>' _ws / _ws '+' _ws / _ws '~' _ws / _sp
    \\decl       <- property _ws ':' _ws val_list _ws ';'
    \\property   <- _ident
    \\@squashed val_list <- val (_sp val)*
    \\@squashed val <- color / size / number / keyword / str
    \\color      <- '#' _hex{6} / '#' _hex{3}
    \\size       <- _digits _unit
    \\number     <- _digits
    \\@squashed keyword <- _ident
    \\str        <- '"' [^"]* '"' / '\'' [^']* '\''
    \\@silent _unit      <- 'px' / 'em' / 'rem' / '%' / 'vh' / 'vw'
    \\@silent _ident     <- [a-zA-Z\-_] [a-zA-Z0-9\-_]*
    \\@silent _hex       <- [0-9a-fA-F]
    \\@silent _digits    <- [0-9]+
    \\@silent _sp        <- [ \t]+
    \\@silent _ws        <- [ \t\n\r]*
);

// --- Walker: extract info from CSS ---

const CssInfo = struct {
    rule_count: usize,
    decl_count: usize,
    color_count: usize,
    selector_text: []const u8,
};

const SelCollector = struct {
    items: std.ArrayListUnmanaged([]const u8) = .{},
    allocator: std.mem.Allocator,

    fn append(self: *SelCollector, text: []const u8) !void {
        try self.items.append(self.allocator, text);
    }
};

const CssWalker = peg.Walker(CssInfo, *SelCollector);

fn walkStylesheet(_: peg.Node, children: []const CssInfo, _: *SelCollector) anyerror!CssInfo {
    var rules: usize = 0;
    var decls: usize = 0;
    var colors: usize = 0;
    for (children) |c| {
        rules += c.rule_count;
        decls += c.decl_count;
        colors += c.color_count;
    }
    return .{ .rule_count = rules, .decl_count = decls, .color_count = colors, .selector_text = "" };
}

fn walkRule(_: peg.Node, children: []const CssInfo, _: *SelCollector) anyerror!CssInfo {
    var decls: usize = 0;
    var colors: usize = 0;
    for (children) |c| {
        decls += c.decl_count;
        colors += c.color_count;
    }
    return .{ .rule_count = 1, .decl_count = decls, .color_count = colors, .selector_text = "" };
}

fn walkDecl(_: peg.Node, children: []const CssInfo, _: *SelCollector) anyerror!CssInfo {
    var colors: usize = 0;
    for (children) |c| colors += c.color_count;
    return .{ .rule_count = 0, .decl_count = 1, .color_count = colors, .selector_text = "" };
}

fn walkColor(_: peg.Node, _: []const CssInfo, _: *SelCollector) anyerror!CssInfo {
    return .{ .rule_count = 0, .decl_count = 0, .color_count = 1, .selector_text = "" };
}

fn walkSelector(node: peg.Node, _: []const CssInfo, ctx: *SelCollector) anyerror!CssInfo {
    try ctx.append(node.text);
    return .{ .rule_count = 0, .decl_count = 0, .color_count = 0, .selector_text = node.text };
}

fn walkDefault(_: peg.Node, children: []const CssInfo, _: *SelCollector) anyerror!CssInfo {
    var rules: usize = 0;
    var decls: usize = 0;
    var colors: usize = 0;
    for (children) |c| {
        rules += c.rule_count;
        decls += c.decl_count;
        colors += c.color_count;
    }
    return .{ .rule_count = rules, .decl_count = decls, .color_count = colors, .selector_text = "" };
}

fn makeWalker(allocator: std.mem.Allocator) CssWalker {
    return CssWalker{
        .actions = &.{
            .{ .tag = "stylesheet", .func = walkStylesheet },
            .{ .tag = "rule", .func = walkRule },
            .{ .tag = "decl", .func = walkDecl },
            .{ .tag = "color", .func = walkColor },
            .{ .tag = "selector", .func = walkSelector },
        },
        .default = walkDefault,
        .allocator = allocator,
    };
}

// --- Helpers ---

fn expectParse(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try css.parse(arena.allocator(), "stylesheet", input);
    try std.testing.expect(result.pos == input.len);
    std.debug.print("  OK\n", .{});
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (css.parse(arena.allocator(), "stylesheet", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
        std.debug.print("  PARTIAL (ok)\n", .{});
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

fn expectTagCount(input: []const u8, tag: []const u8, expected: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try css.parse(arena.allocator(), "stylesheet", input);
    try std.testing.expectEqual(expected, countTag(result.node, tag));
}

// --- Tests ---

test "empty stylesheet" {
    std.debug.print("\n-- css: empty --\n", .{});
    try expectParse("");
    try expectParse("   ");
    try expectParse("\n\n");
}

test "single rule" {
    std.debug.print("\n-- css: single rule --\n", .{});
    const cases = [_][]const u8{
        "body { color: red; }",
        "div { margin: 0px; }",
        "p { font-size: 16px; }",
    };
    for (cases) |input| try expectParse(input);
}

test "element selectors" {
    std.debug.print("\n-- css: elements --\n", .{});
    const cases = [_][]const u8{
        "div { color: red; }",
        "span { color: blue; }",
        "body { margin: 0px; }",
        "section { padding: 10px; }",
    };
    for (cases) |input| try expectParse(input);
}

test "class selectors" {
    std.debug.print("\n-- css: classes --\n", .{});
    const cases = [_][]const u8{
        ".container { width: 100vw; }",
        ".btn { padding: 8px; }",
        ".my-class { color: red; }",
        ".a_b { color: red; }",
    };
    for (cases) |input| try expectParse(input);
}

test "id selectors" {
    std.debug.print("\n-- css: ids --\n", .{});
    const cases = [_][]const u8{
        "#main { width: 960px; }",
        "#header { height: 60px; }",
        "#my-id { color: blue; }",
    };
    for (cases) |input| try expectParse(input);
}

test "universal selector" {
    std.debug.print("\n-- css: universal --\n", .{});
    try expectParse("* { margin: 0px; }");
    try expectParse("* { padding: 0px; }");
}

test "pseudo selectors" {
    std.debug.print("\n-- css: pseudo --\n", .{});
    try expectParse("a:hover { color: red; }");
    try expectParse("input:focus { border-color: blue; }");
    try expectParse("li:first-child { margin-top: 0px; }");
}

test "compound selectors" {
    std.debug.print("\n-- css: compound --\n", .{});
    try expectParse("div.container { width: 100vw; }");
    try expectParse("p.intro { font-size: 18px; }");
    try expectParse("a#logo { text-decoration: none; }");
    try expectParse("input.large:focus { border-width: 2px; }");
}

test "descendant combinator" {
    std.debug.print("\n-- css: descendant --\n", .{});
    try expectParse("div p { color: red; }");
    try expectParse("body div p { margin: 0px; }");
    try expectParse(".container .item { padding: 5px; }");
}

test "child combinator" {
    std.debug.print("\n-- css: child --\n", .{});
    try expectParse("div > p { color: red; }");
    try expectParse("ul > li { list-style: none; }");
    try expectParse(".parent > .child { margin: 0px; }");
}

test "sibling combinators" {
    std.debug.print("\n-- css: siblings --\n", .{});
    try expectParse("h1 + p { margin-top: 0px; }");
    try expectParse("h2 ~ p { color: gray; }");
}

test "selector lists" {
    std.debug.print("\n-- css: selector lists --\n", .{});
    try expectParse("h1, h2, h3 { font-weight: bold; }");
    try expectParse("div, .class, #id { margin: 0px; }");
    try expectParse(".a, .b { color: red; }");
}

test "multiple declarations" {
    std.debug.print("\n-- css: multi decl --\n", .{});
    try expectParse("div { color: red; margin: 10px; padding: 5px; }");
    try expectParse("body { font-family: sans-serif; font-size: 16px; line-height: 1; }");
}

test "colors" {
    std.debug.print("\n-- css: colors --\n", .{});
    try expectParse("div { color: #ff0000; }");
    try expectParse("div { color: #fff; }");
    try expectParse("div { color: #aabbcc; }");
    try expectParse("div { background-color: #123456; }");
    try expectParse("div { color: #ABC; }");
}

test "sizes and units" {
    std.debug.print("\n-- css: sizes --\n", .{});
    try expectParse("div { width: 100px; }");
    try expectParse("div { height: 50vh; }");
    try expectParse("div { margin: 2em; }");
    try expectParse("div { padding: 1rem; }");
    try expectParse("div { width: 100%; }");
    try expectParse("div { width: 50vw; }");
}

test "multi-value declarations" {
    std.debug.print("\n-- css: multi-value --\n", .{});
    try expectParse("div { margin: 10px 20px; }");
    try expectParse("div { padding: 5px 10px 15px 20px; }");
    try expectParse("div { border: 1px solid red; }");
}

test "string values" {
    std.debug.print("\n-- css: strings --\n", .{});
    try expectParse("div { content: \"hello\"; }");
    try expectParse("div { content: 'world'; }");
    try expectParse("div { font-family: \"Times New Roman\"; }");
}

test "keyword values" {
    std.debug.print("\n-- css: keywords --\n", .{});
    try expectParse("div { display: block; }");
    try expectParse("div { position: relative; }");
    try expectParse("div { overflow: hidden; }");
    try expectParse("div { text-align: center; }");
}

test "empty rule body" {
    std.debug.print("\n-- css: empty body --\n", .{});
    try expectParse("div { }");
    try expectParse(".empty { }");
}

test "multiple rules" {
    std.debug.print("\n-- css: multiple rules --\n", .{});
    try expectParse("body { margin: 0px; } div { padding: 10px; }");
    try expectParse("h1 { font-size: 24px; } h2 { font-size: 20px; } h3 { font-size: 16px; }");
}

test "whitespace variants" {
    std.debug.print("\n-- css: whitespace --\n", .{});
    try expectParse("div{color:red;}");
    try expectParse("div  {  color  :  red  ;  }");
    try expectParse("div\n{\n  color: red;\n}");
    try expectParse("div\t{\tcolor:\tred;\t}");
    try expectParse(
        \\body {
        \\  margin: 0px;
        \\  padding: 0px;
        \\}
        \\
        \\div {
        \\  color: red;
        \\}
    );
}

test "complex stylesheet" {
    std.debug.print("\n-- css: complex --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\* {
        \\  margin: 0px;
        \\  padding: 0px;
        \\}
        \\
        \\body {
        \\  font-family: sans-serif;
        \\  font-size: 16px;
        \\  color: #333333;
        \\}
        \\
        \\.container {
        \\  width: 960px;
        \\  margin: 0px auto;
        \\}
        \\
        \\h1, h2, h3 {
        \\  font-weight: bold;
        \\  color: #111;
        \\}
        \\
        \\.btn {
        \\  padding: 8px 16px;
        \\  background-color: #007bff;
        \\  color: #fff;
        \\}
        \\
        \\.btn:hover {
        \\  background-color: #0056b3;
        \\}
        \\
        \\#main > .content {
        \\  padding: 20px;
        \\}
        \\
        \\ul > li {
        \\  list-style: none;
        \\}
        \\
        \\a:hover {
        \\  text-decoration: underline;
        \\  color: #0056b3;
        \\}
    ;
    const result = try css.parse(arena.allocator(), "stylesheet", input);
    peg.printTree(result.node, 2);

    const rule_count = countTag(result.node, "rule");
    const decl_count = countTag(result.node, "decl");
    const color_count = countTag(result.node, "color");
    std.debug.print("  Rules: {}, Declarations: {}, Colors: {}\n", .{ rule_count, decl_count, color_count });
    try std.testing.expect(rule_count >= 8);
    try std.testing.expect(decl_count >= 15);
    try std.testing.expect(color_count >= 5);
}

test "tree structure" {
    std.debug.print("\n-- css: tree --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try css.parse(arena.allocator(), "stylesheet", "div.active { color: #ff0000; padding: 10px; }");
    peg.printTree(result.node, 2);

    try std.testing.expectEqual(@as(usize, 1), countTag(result.node, "rule"));
    try std.testing.expectEqual(@as(usize, 2), countTag(result.node, "decl"));
    try std.testing.expectEqual(@as(usize, 1), countTag(result.node, "color"));
    try std.testing.expectEqual(@as(usize, 1), countTag(result.node, "size"));
    try std.testing.expectEqual(@as(usize, 1), countTag(result.node, "element"));
    try std.testing.expectEqual(@as(usize, 1), countTag(result.node, "class"));
    std.debug.print("  OK: tree structure\n", .{});
}

test "walker with context" {
    std.debug.print("\n-- css: walker --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const input =
        \\body { color: #333; }
        \\div.main { padding: 10px; margin: 20px; }
        \\.btn { background-color: #007bff; color: #fff; }
    ;
    const result = try css.parse(arena.allocator(), "stylesheet", input);

    var selectors = SelCollector{ .allocator = arena.allocator() };
    const walker = makeWalker(arena.allocator());
    const info = try walker.walk(result.node, &selectors);

    std.debug.print("  Rules: {}\n", .{info.rule_count});
    std.debug.print("  Declarations: {}\n", .{info.decl_count});
    std.debug.print("  Colors: {}\n", .{info.color_count});
    std.debug.print("  Selectors:\n", .{});
    for (selectors.items.items) |s| {
        std.debug.print("    - \"{s}\"\n", .{s});
    }

    try std.testing.expectEqual(@as(usize, 3), info.rule_count);
    try std.testing.expectEqual(@as(usize, 5), info.decl_count);
    try std.testing.expectEqual(@as(usize, 3), info.color_count);
    try std.testing.expectEqual(@as(usize, 3), selectors.items.items.len);
    std.debug.print("  OK: walker with context\n", .{});
}

test "and predicate" {
    std.debug.print("\n-- css: and predicate --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try css.parse(arena.allocator(), "stylesheet", "div { color: red; }");
    try std.testing.expectEqual(@as(usize, 1), countTag(result.node, "element"));
    try std.testing.expectEqual(@as(usize, 0), countTag(result.node, "class"));
    try std.testing.expectEqual(@as(usize, 0), countTag(result.node, "id"));

    const result2 = try css.parse(arena.allocator(), "stylesheet", ".cls { color: red; }");
    try std.testing.expectEqual(@as(usize, 0), countTag(result2.node, "element"));
    try std.testing.expectEqual(@as(usize, 1), countTag(result2.node, "class"));

    const result3 = try css.parse(arena.allocator(), "stylesheet", "#myid { color: red; }");
    try std.testing.expectEqual(@as(usize, 0), countTag(result3.node, "element"));
    try std.testing.expectEqual(@as(usize, 1), countTag(result3.node, "id"));

    std.debug.print("  OK: & predicate disambiguates selectors\n", .{});
}

test "hex color lengths" {
    std.debug.print("\n-- css: hex lengths --\n", .{});
    try expectTagCount("div { color: #abc; }", "color", 1);
    try expectTagCount("div { color: #aabbcc; }", "color", 1);

    std.debug.print("  OK: hex {{3}} and {{6}}\n", .{});
}

test "detailed errors" {
    std.debug.print("\n-- css: detailed errors --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const r1 = css.parseDetailed(arena.allocator(), "stylesheet", "div { color: red }");
    switch (r1) {
        .ok => |ok| {
            std.debug.print("  'missing ;' partial parse, pos={}/{}\n", .{ ok.pos, 18 });
            try std.testing.expect(ok.pos < 18);
        },
        .err => |e| {
            std.debug.print("  'missing ;' error at line {}:{}: {s}\n", .{ e.line, e.col, e.expected });
        },
    }

    const r2 = css.parseDetailed(arena.allocator(), "stylesheet", "div { color: red;");
    switch (r2) {
        .ok => |ok| {
            std.debug.print("  'missing }}' partial parse, pos={}/{}\n", .{ ok.pos, 17 });
            try std.testing.expect(ok.pos < 17);
        },
        .err => |e| {
            std.debug.print("  'missing }}' error at line {}:{}: {s}\n", .{ e.line, e.col, e.expected });
        },
    }

    const r3 = css.parseDetailed(arena.allocator(), "stylesheet",
        \\body {
        \\  color: red;
        \\  margin: ;
        \\}
    );
    switch (r3) {
        .ok => |ok| {
            std.debug.print("  'bad value' partial parse, pos={}\n", .{ok.pos});
        },
        .err => |e| {
            std.debug.print("  'bad value' error at line {}:{}: {s}\n", .{ e.line, e.col, e.expected });
            std.debug.print("  context: \"{s}\"\n", .{e.context});
        },
    }
}