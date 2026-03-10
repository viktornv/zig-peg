const std = @import("std");
const peg = @import("peg");

// GraphQL strict profile:
// - practical document grammar
// - names starting with "__" are rejected (reserved for introspection)
const gql = peg.compile(
    \\document          <- _ws definition (_ws definition)* _ws
    \\@squashed definition <- operation_def / fragment_def
    \\operation_def     <- selection_set / operation_type (_req_ws op_name)? (_ws variable_defs)? (_ws directives)? _ws selection_set
    \\operation_type    <- 'query' / 'mutation' / 'subscription'
    \\fragment_def      <- 'fragment' _req_ws fragment_name _req_ws 'on' _req_ws type_name (_ws directives)? _ws selection_set
    \\fragment_name     <- !'on' name
    \\
    \\selection_set     <- '{' _ws selection (_req_ws selection)* _ws '}'
    \\@squashed selection <- field / fragment_spread / inline_fragment
    \\field             <- alias? name (_ws arguments)? (_ws directives)? (_req_ws selection_set)?
    \\@squashed alias <- name _ws ':' _ws
    \\@squashed arguments <- '(' _ws (argument (_ws argument)*)? _ws ')'
    \\@squashed argument <- name _ws ':' _ws value
    \\fragment_spread   <- '...' _ws fragment_name (_ws directives)?
    \\inline_fragment   <- '...' (_ws 'on' _req_ws type_name)? (_ws directives)? _ws selection_set
    \\@squashed directives <- directive (_ws directive)*
    \\@squashed directive <- '@' name arguments?
    \\
    \\@squashed variable_defs <- '(' _ws (variable_def (_ws variable_def)*)? _ws ')'
    \\variable_def      <- variable _ws ':' _ws type_ref (_ws default_value)?
    \\@squashed default_value <- '=' _ws value
    \\@squashed type_ref <- non_null_type / list_type / named_type
    \\@squashed named_type <- type_name
    \\@squashed list_type <- '[' type_ref ']'
    \\@squashed non_null_type <- (named_type / list_type) '!'
    \\@squashed type_name <- name
    \\@squashed op_name <- name
    \\
    \\value             <- variable / float / int / string / bool / null / enum_value / list / object
    \\variable          <- '$' name
    \\@squashed list <- '[' _ws (value (_ws value)*)? _ws ']'
    \\@squashed object <- '{' _ws (object_field (_ws object_field)*)? _ws '}'
    \\@squashed object_field <- name _ws ':' _ws value
    \\bool             <- 'true' / 'false'
    \\null             <- 'null'
    \\enum_value       <- name
    \\int              <- ~"-?[0-9]+"
    \\float            <- ~"-?[0-9]+[.][0-9]+" _exp?
    \\@silent _exp              <- ~"[eE][+-]?[0-9]+"
    \\string           <- '"' _str_char* '"'
    \\@silent _str_char         <- '\\' . / [^"\\]
    \\name             <- !'__' ~"[A-Za-z_][A-Za-z0-9_]*"
    \\
    \\@silent _req_ws          <- ([ \t\r\n,] / comment)+
    \\@silent _ws               <- ([ \t\r\n,] / comment)*
    \\comment           <- ~"#[^\n]*"
);

fn expectParseAll(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try gql.parse(arena.allocator(), "document", input);
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (gql.parse(arena.allocator(), "document", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
    } else |_| {}
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var count: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) count += 1;
    for (node.children) |child| count += countTag(child, tag);
    return count;
}

test "graphql strict accepts practical documents" {
    try expectParseAll("query Q($id: ID!) { user(id: $id) { id name } }");
    try expectParseAll("fragment UserFields on User { id name } query { me { ...UserFields } }");
    try expectParseAll("mutation M { upsertUser(input: { role: ADMIN, active: true }) { id } }");
}

test "graphql strict rejects reserved names" {
    try expectFail("query __Q { me { id } }");
    try expectFail("query { __typename }");
    try expectFail("fragment on on User { id }");
}

test "graphql strict rejects malformed documents" {
    try expectFail("query { user(id: ) { id } }");
    try expectFail("query { user(id: 1) ");
    try expectFail("query Q($id: ID!) { user(id: $id) { id ");
}

test "graphql strict supports directives and variable defaults" {
    try expectParseAll(
        "query Q($id: ID! = 1) @trace { user(id: $id) @include(if: true) { id name } }",
    );
}

test "graphql strict tree structure smoke" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const input = "query Q($id: ID!) { user(id: $id) { id name } }";
    const r = try gql.parse(arena.allocator(), "document", input);
    try std.testing.expectEqualStrings("document", r.node.tag);
    try std.testing.expect(countTag(r.node, "operation_def") == 1);
    try std.testing.expect(countTag(r.node, "field") >= 3);
}

test "graphql strict detailed error reports location" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const bad = "query { user(id: ) { id } }";
    const d = gql.parseDetailed(arena.allocator(), "document", bad);
    switch (d) {
        .ok => return error.ShouldHaveFailed,
        .err => |e| {
            try std.testing.expectEqual(peg.ParseErrorClass.syntax, e.class);
            try std.testing.expect(e.pos > 0);
            try std.testing.expect(e.col > 0);
            try std.testing.expect(e.expected_count >= 1);
        },
    }
}
