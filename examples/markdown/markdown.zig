const std = @import("std");
const peg = @import("peg");

const md = peg.compile(
    \\document <- block+
    \\block    <- heading / codeblock / ulist / olist / paragraph / blankline
    \\
    \\heading  <- _hashes _sp inline+ _nl
    \\@silent _hashes  <- '######' / '#####' / '####' / '###' / '##' / '#'
    \\@silent _sp      <- ' '+
    \\
    \\codeblock <- '```' _codeid? _nl _codetext '```' _nl?
    \\@silent _codeid   <- [a-zA-Z0-9]+
    \\@silent _codetext <- (!'```' .)*
    \\
    \\ulist    <- uitem+
    \\uitem    <- '- ' inline+ _nl
    \\
    \\olist    <- oitem+
    \\oitem    <- _digits '. ' inline+ _nl
    \\@silent _digits  <- [0-9]+
    \\
    \\paragraph <- inline+ _nl
    \\blankline <- _nl
    \\
    \\inline   <- bold / italic / code / link / image / text
    \\bold     <- '**' _boldtext '**'
    \\@silent _boldtext <- (!'**' .)+
    \\italic   <- '*' !'*' _italtext '*'
    \\@silent _italtext <- (!'*' .)+
    \\code     <- '`' _codespan '`'
    \\@silent _codespan <- (!'`' .)+
    \\link     <- '[' _linktext ']' '(' _linkurl ')'
    \\@silent _linktext <- (!']' .)+
    \\@silent _linkurl  <- (!')' .)+
    \\image    <- '![' _alttext ']' '(' _imgurl ')'
    \\@silent _alttext  <- (!']' .)+
    \\@silent _imgurl   <- (!')' .)+
    \\text     <- (!'*' !'`' !'[' !'!' !_nl .)+
    \\
    \\@silent _nl      <- '\r'? '\n' / !.
);

fn expectParse(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try md.parse(arena.allocator(), "document", input);
    try std.testing.expect(result.pos == input.len);
    std.debug.print("  OK\n", .{});
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (md.parse(arena.allocator(), "document", input)) |r| {
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
    const result = try md.parse(arena.allocator(), "document", input);
    try std.testing.expectEqual(expected, countTag(result.node, tag));
}

test "headings" {
    std.debug.print("\n-- md: headings --\n", .{});
    const cases = [_][]const u8{
        "# Heading 1\n",
        "## Heading 2\n",
        "### Heading 3\n",
        "#### Heading 4\n",
        "##### Heading 5\n",
        "###### Heading 6\n",
    };
    for (cases) |input| try expectParse(input);
}

test "heading levels" {
    std.debug.print("\n-- md: heading levels --\n", .{});
    try expectTagCount("# Title\n## Subtitle\n### Section\n", "heading", 3);
    std.debug.print("  OK: heading level tree\n", .{});
}

test "paragraphs" {
    std.debug.print("\n-- md: paragraphs --\n", .{});
    try expectParse("Hello world\n");
    try expectParse("This is a paragraph\n");
    try expectParse("Line one\nLine two\n");
}

test "bold" {
    std.debug.print("\n-- md: bold --\n", .{});
    try expectParse("This is **bold** text\n");
    try expectParse("**all bold**\n");
    try expectParse("a **b** c **d** e\n");
    try expectTagCount("Hello **world** today\n", "bold", 1);
    std.debug.print("  OK: bold tree\n", .{});
}

test "italic" {
    std.debug.print("\n-- md: italic --\n", .{});
    try expectParse("This is *italic* text\n");
    try expectParse("*all italic*\n");
}

test "inline code" {
    std.debug.print("\n-- md: inline code --\n", .{});
    try expectParse("Use `code` here\n");
    try expectParse("`hello` and `world`\n");
    try expectParse("Run `npm install` now\n");
    try expectTagCount("Use `x` and `y`\n", "code", 2);
    std.debug.print("  OK: code tree\n", .{});
}

test "links" {
    std.debug.print("\n-- md: links --\n", .{});
    try expectParse("[click here](http://example.com)\n");
    try expectParse("Visit [Google](https://google.com) now\n");
    try expectParse("[a](b) and [c](d)\n");
    try expectTagCount("[text](url)\n", "link", 1);
    std.debug.print("  OK: link tree\n", .{});
}

test "images" {
    std.debug.print("\n-- md: images --\n", .{});
    try expectParse("![alt text](image.png)\n");
    try expectParse("See ![photo](pic.jpg) here\n");
    try expectTagCount("![logo](logo.png)\n", "image", 1);
    std.debug.print("  OK: image tree\n", .{});
}

test "unordered list" {
    std.debug.print("\n-- md: unordered list --\n", .{});
    try expectParse("- item one\n- item two\n- item three\n");
    try expectParse("- single\n");
    try expectTagCount("- a\n- b\n- c\n", "uitem", 3);
    std.debug.print("  OK: ulist tree\n", .{});
}

test "ordered list" {
    std.debug.print("\n-- md: ordered list --\n", .{});
    try expectParse("1. first\n2. second\n3. third\n");
    try expectParse("1. only\n");
    try expectTagCount("1. a\n2. b\n", "oitem", 2);
    std.debug.print("  OK: olist tree\n", .{});
}

test "code blocks" {
    std.debug.print("\n-- md: code blocks --\n", .{});
    try expectParse("```\nhello\n```\n");
    try expectParse("```zig\nconst x = 1;\n```\n");
    try expectParse("```python\nprint('hi')\nx = 42\n```\n");
    try expectTagCount("```zig\ncode here\n```\n", "codeblock", 1);
    std.debug.print("  OK: codeblock tree\n", .{});
}

test "mixed formatting" {
    std.debug.print("\n-- md: mixed --\n", .{});
    try expectParse("**bold** and *italic* and `code`\n");
    try expectParse("Click [here](url) or see ![img](pic.png)\n");
}

test "blank lines" {
    std.debug.print("\n-- md: blank lines --\n", .{});
    try expectParse("Hello\n\nWorld\n");
    try expectParse("\n\n\n");
    try expectParse("# Title\n\nParagraph\n");
}

test "complex document" {
    std.debug.print("\n-- md: complex --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\# My Document
        \\
        \\This is a **paragraph** with *formatting*.
        \\
        \\## Code Example
        \\
        \\```zig
        \\const x = 42;
        \\```
        \\
        \\## Lists
        \\
        \\- item **one**
        \\- item *two*
        \\- item `three`
        \\
        \\1. first
        \\2. second
        \\
        \\Visit [docs](http://example.com) for more.
        \\
    ;
    const result = try md.parse(arena.allocator(), "document", input);
    peg.printTree(result.node, 2);

    try std.testing.expect(countTag(result.node, "heading") >= 2);
    try std.testing.expect(countTag(result.node, "bold") >= 1);
    try std.testing.expect(countTag(result.node, "link") >= 1);
    std.debug.print("  OK: complex document\n", .{});
}

test "empty" {
    std.debug.print("\n-- md: empty --\n", .{});
    try expectFail("");
}

test "invalid markdown cases" {
    std.debug.print("\n-- md: invalid --\n", .{});
    // These inputs start with tokens that cannot be consumed as plain text,
    // and are also incomplete for their corresponding inline constructs.
    try expectFail("*\n");
    try expectFail("`\n");
    try expectFail("[\n");
    try expectFail("!\n");
}

test "markdown detailed errors" {
    std.debug.print("\n-- md: detailed errors --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const bad = "[broken](\n";
    const d = md.parseDetailed(arena.allocator(), "document", bad);
    switch (d) {
        .ok => return error.ShouldHaveFailed,
        .err => |e| {
            try std.testing.expectEqual(peg.ParseErrorClass.syntax, e.class);
            try std.testing.expect(e.line >= 1);
            try std.testing.expect(e.col >= 1);
            try std.testing.expect(e.expected_count >= 1);
        },
    }
}