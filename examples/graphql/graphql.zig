const std = @import("std");
const peg = @import("peg");

// Practical GraphQL parser:
// - query/mutation/subscription operations
// - fragment definitions/spreads, inline fragments
// - variables, arguments, directives
// - scalar/list/object values
const graphql = peg.compile(
    \\document        <- _ws definition (_ws definition)* _ws
    \\@squashed definition <- operation_def / fragment_def
    \\operation_def   <- selection_set / operation_type (_req_ws name)? (_ws variable_defs)? (_ws directives)? _ws selection_set
    \\operation_type  <- 'query' / 'mutation' / 'subscription'
    \\fragment_def    <- 'fragment' _req_ws name _req_ws 'on' _req_ws type_name (_ws directives)? _ws selection_set
    \\
    \\selection_set   <- '{' _ws selection (_req_ws selection)* _ws '}'
    \\@squashed selection <- field / fragment_spread / inline_fragment
    \\field           <- alias? name (_ws arguments)? (_ws directives)? (_req_ws selection_set)?
    \\@squashed alias <- name _ws ':' _ws
    \\@squashed arguments <- '(' _ws (argument (_ws argument)*)? _ws ')'
    \\@squashed argument <- name _ws ':' _ws value
    \\fragment_spread <- '...' _ws !'on' name (_ws directives)?
    \\inline_fragment <- '...' (_ws 'on' _req_ws type_name)? (_ws directives)? _ws selection_set
    \\@squashed directives <- directive (_ws directive)*
    \\@squashed directive <- '@' name arguments?
    \\
    \\@squashed variable_defs <- '(' _ws (variable_def (_ws variable_def)*)? _ws ')'
    \\variable_def    <- variable _ws ':' _ws type_ref (_ws default_value)?
    \\@squashed default_value <- '=' _ws value
    \\@squashed type_ref <- non_null_type / list_type / named_type
    \\@squashed named_type <- name
    \\@squashed list_type <- '[' type_ref ']'
    \\@squashed non_null_type <- (named_type / list_type) '!'
    \\@squashed type_name <- name
    \\
    \\value           <- variable / float / int / string / bool / null / enum / list / object
    \\variable        <- '$' name
    \\@squashed list <- '[' _ws (value (_ws value)*)? _ws ']'
    \\@squashed object <- '{' _ws (object_field (_ws object_field)*)? _ws '}'
    \\@squashed object_field <- name _ws ':' _ws value
    \\bool           <- 'true' / 'false'
    \\null           <- 'null'
    \\enum           <- ~"[A-Za-z_][A-Za-z0-9_]*"
    \\int            <- ~"-?[0-9]+"
    \\float          <- ~"-?[0-9]+[.][0-9]+" _exp?
    \\@silent _exp            <- ~"[eE][+-]?[0-9]+"
    \\string         <- '"' _str_char* '"'
    \\@silent _str_char       <- '\\' . / [^"\\]
    \\name           <- ~"[A-Za-z_][A-Za-z0-9_]*"
    \\
    \\@silent _req_ws        <- ([ \t\r\n,] / comment)+
    \\@silent _ws             <- ([ \t\r\n,] / comment)*
    \\comment         <- ~"#[^\n]*"
);

fn expectParseAll(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try graphql.parse(arena.allocator(), "document", input);
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (graphql.parse(arena.allocator(), "document", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
    } else |_| {}
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var count: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) count += 1;
    for (node.children) |child| count += countTag(child, tag);
    return count;
}

test "graphql simple queries" {
    try expectParseAll("{ me { id name } }");
    try expectParseAll("query { user { id } }");
    try expectParseAll("query getUser { user { id name } }");
}

test "graphql variables arguments and directives" {
    try expectParseAll("query Q($id: ID!, $limit: Int = 10) { user(id: $id) @cache(ttl: 30) { posts(limit: $limit) { title } } }");
    try expectParseAll("mutation Add($name: String!) { addUser(name: $name) { id } }");
}

test "graphql fragments inline fragments and comments" {
    try expectParseAll(
        \\# main query
        \\query Feed {
        \\  feed {
        \\    ...PostFields
        \\    ... on VideoPost { duration }
        \\  }
        \\}
        \\fragment PostFields on Post {
        \\  id
        \\  title
        \\}
    );
}

test "graphql values list object enum" {
    try expectParseAll(
        \\query {
        \\  search(
        \\    text: "zig",
        \\    options: { limit: 10, tags: ["parser", "peg"], exact: false },
        \\    mode: FAST
        \\  ) {
        \\    id
        \\  }
        \\}
    );
}

test "graphql invalid cases" {
    try expectFail("");
    try expectFail("query");
    try expectFail("{ user( }");
    try expectFail("fragment X on { id }");
    try expectFail("query Q($id ID!) { x }");
    try expectFail("query { ... on { id } }");
}

test "graphql tree structure smoke" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const input = "query Q($id: ID!) { user(id: $id) { id name } }";
    const res = try graphql.parse(arena.allocator(), "document", input);

    try std.testing.expectEqualStrings("document", res.node.tag);
    try std.testing.expect(countTag(res.node, "operation_def") >= 1);
    try std.testing.expect(countTag(res.node, "field") >= 2);
    try std.testing.expect(countTag(res.node, "name") >= 4);
}
