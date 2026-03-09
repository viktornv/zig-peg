const std = @import("std");
const peg = @import("peg");

// Practical Component Pascal grammar example (BlackBox-style subset).
const cp = peg.compile(
    \\module          <- _ws KW_MODULE ident_def ';' import_list? decl_seq begin_part? KW_END ident '.' _ws
    \\import_list     <- KW_IMPORT import_item (',' import_item)* ';'
    \\import_item     <- ident (':=' ident)?
    \\decl_seq        <- const_section? type_section? var_section? (proc_decl ';')*
    \\const_section   <- KW_CONST const_decl (';' const_decl)* ';'?
    \\const_decl      <- ident_def '=' const_expr
    \\type_section    <- KW_TYPE type_decl (';' type_decl)* ';'?
    \\type_decl       <- ident_def '=' type_expr
    \\var_section     <- KW_VAR var_decl (';' var_decl)* ';'?
    \\var_decl        <- ident_def_list ':' type_expr
    \\ident_list      <- ident (',' ident)*
    \\ident_def_list  <- ident_def (',' ident_def)*
    \\
    \\type_expr       <- array_type / record_type / pointer_type / procedure_type / set_type / qualident
    \\array_type      <- KW_ARRAY const_expr (',' const_expr)* KW_OF type_expr
    \\record_type     <- KW_RECORD base_type? field_list_seq? KW_END
    \\base_type       <- '(' qualident ')'
    \\field_list_seq  <- field_list (';' field_list)*
    \\field_list      <- ident_list ':' type_expr
    \\pointer_type    <- KW_POINTER KW_TO type_expr
    \\procedure_type  <- KW_PROCEDURE formal_params?
    \\set_type        <- KW_SET
    \\
    \\proc_decl       <- KW_PROCEDURE receiver? ident_def formal_params? ';' decl_seq begin_part? KW_END ident
    \\receiver        <- '(' ident ':' ident ')'
    \\formal_params   <- '(' (fp_section (';' fp_section)*)? ')' return_type?
    \\return_type     <- ':' qualident
    \\fp_section      <- param_mode? ident_list ':' qualident
    \\param_mode      <- KW_VAR / KW_IN / KW_OUT / KW_READONLY
    \\
    \\begin_part      <- KW_BEGIN stat_seq
    \\stat_seq        <- statement (';' statement)*
    \\statement       <- assignment / if_stmt / case_stmt / while_stmt / repeat_stmt / for_stmt / loop_stmt / with_stmt / exit_stmt / return_stmt / call_stmt / ''
    \\
    \\assignment      <- designator ':=' expr
    \\call_stmt       <- designator
    \\if_stmt         <- KW_IF expr KW_THEN stat_seq (KW_ELSIF expr KW_THEN stat_seq)* (KW_ELSE stat_seq)? KW_END
    \\case_stmt       <- KW_CASE expr KW_OF case_branch ('|' case_branch)* (KW_ELSE stat_seq)? KW_END
    \\case_branch     <- label_range (',' label_range)* ':' stat_seq
    \\label_range     <- const_expr ('..' const_expr)?
    \\while_stmt      <- KW_WHILE expr KW_DO stat_seq (KW_ELSIF expr KW_DO stat_seq)* KW_END
    \\repeat_stmt     <- KW_REPEAT stat_seq KW_UNTIL expr
    \\for_stmt        <- KW_FOR ident ':=' expr KW_TO expr (KW_BY const_expr)? KW_DO stat_seq KW_END
    \\loop_stmt       <- KW_LOOP stat_seq KW_END
    \\with_stmt       <- KW_WITH guard ('|' guard)* (KW_ELSE stat_seq)? KW_END
    \\guard           <- qualident ':' qualident KW_DO stat_seq
    \\exit_stmt       <- KW_EXIT
    \\return_stmt     <- KW_RETURN expr?
    \\
    \\expr            <- simple_expr (relation simple_expr)?
    \\relation        <- '=' / '#' / '<=' / '>=' / '<' / '>' / KW_IN / KW_IS
    \\simple_expr     <- sign? term (add_op term)*
    \\sign            <- '+' / '-'
    \\add_op          <- '+' / '-' / KW_OR
    \\term            <- factor (mul_op factor)*
    \\mul_op          <- '*' / '/' / KW_DIV / KW_MOD / '&'
    \\factor          <- number / string / char_lit / KW_NIL / KW_TRUE / KW_FALSE / set_literal / '~' factor / '(' expr ')' / designator
    \\set_literal     <- '{' (element (',' element)*)? '}'
    \\element         <- expr ('..' expr)?
    \\
    \\designator      <- qualident selector*
    \\selector        <- '.' ident / '[' expr_list ']' / '^' / actual_params
    \\actual_params   <- '(' (expr (',' expr)*)? ')'
    \\expr_list       <- expr (',' expr)*
    \\
    \\const_expr      <- expr
    \\qualident       <- ident ('.' ident)?
    \\ident_def       <- ident (_ws ('*' / '-'))? _ws
    \\
    \\ident          <- _ws !_keyword [A-Za-z] [A-Za-z0-9_]* _ws
    \\number         <- _ws [0-9]+ ('.' [0-9]+)? _ws
    \\string         <- _ws '"' [^"\n]* '"' _ws
    \\char_lit       <- _ws '\'' [^'\n] '\'' _ws
    \\@silent _keyword        <- KW_MODULE / KW_IMPORT / KW_CONST / KW_TYPE / KW_VAR / KW_PROCEDURE / KW_BEGIN / KW_END / KW_ARRAY / KW_OF / KW_RECORD / KW_POINTER / KW_TO / KW_SET / KW_IF / KW_THEN / KW_ELSIF / KW_ELSE / KW_CASE / KW_WHILE / KW_DO / KW_REPEAT / KW_UNTIL / KW_FOR / KW_BY / KW_LOOP / KW_WITH / KW_EXIT / KW_RETURN / KW_NIL / KW_TRUE / KW_FALSE / KW_DIV / KW_MOD / KW_OR / KW_IN / KW_IS / KW_OUT / KW_READONLY
    \\
    \\KW_MODULE       <- _ws 'MODULE' ![A-Za-z0-9_] _ws
    \\KW_IMPORT       <- _ws 'IMPORT' ![A-Za-z0-9_] _ws
    \\KW_CONST        <- _ws 'CONST' ![A-Za-z0-9_] _ws
    \\KW_TYPE         <- _ws 'TYPE' ![A-Za-z0-9_] _ws
    \\KW_VAR          <- _ws 'VAR' ![A-Za-z0-9_] _ws
    \\KW_PROCEDURE    <- _ws 'PROCEDURE' ![A-Za-z0-9_] _ws
    \\KW_BEGIN        <- _ws 'BEGIN' ![A-Za-z0-9_] _ws
    \\KW_END          <- _ws 'END' ![A-Za-z0-9_] _ws
    \\KW_ARRAY        <- _ws 'ARRAY' ![A-Za-z0-9_] _ws
    \\KW_OF           <- _ws 'OF' ![A-Za-z0-9_] _ws
    \\KW_RECORD       <- _ws 'RECORD' ![A-Za-z0-9_] _ws
    \\KW_POINTER      <- _ws 'POINTER' ![A-Za-z0-9_] _ws
    \\KW_TO           <- _ws 'TO' ![A-Za-z0-9_] _ws
    \\KW_SET          <- _ws 'SET' ![A-Za-z0-9_] _ws
    \\KW_IF           <- _ws 'IF' ![A-Za-z0-9_] _ws
    \\KW_THEN         <- _ws 'THEN' ![A-Za-z0-9_] _ws
    \\KW_ELSIF        <- _ws 'ELSIF' ![A-Za-z0-9_] _ws
    \\KW_ELSE         <- _ws 'ELSE' ![A-Za-z0-9_] _ws
    \\KW_CASE         <- _ws 'CASE' ![A-Za-z0-9_] _ws
    \\KW_WHILE        <- _ws 'WHILE' ![A-Za-z0-9_] _ws
    \\KW_DO           <- _ws 'DO' ![A-Za-z0-9_] _ws
    \\KW_REPEAT       <- _ws 'REPEAT' ![A-Za-z0-9_] _ws
    \\KW_UNTIL        <- _ws 'UNTIL' ![A-Za-z0-9_] _ws
    \\KW_FOR          <- _ws 'FOR' ![A-Za-z0-9_] _ws
    \\KW_BY           <- _ws 'BY' ![A-Za-z0-9_] _ws
    \\KW_LOOP         <- _ws 'LOOP' ![A-Za-z0-9_] _ws
    \\KW_WITH         <- _ws 'WITH' ![A-Za-z0-9_] _ws
    \\KW_EXIT         <- _ws 'EXIT' ![A-Za-z0-9_] _ws
    \\KW_RETURN       <- _ws 'RETURN' ![A-Za-z0-9_] _ws
    \\KW_NIL          <- _ws 'NIL' ![A-Za-z0-9_] _ws
    \\KW_TRUE         <- _ws 'TRUE' ![A-Za-z0-9_] _ws
    \\KW_FALSE        <- _ws 'FALSE' ![A-Za-z0-9_] _ws
    \\KW_DIV          <- _ws 'DIV' ![A-Za-z0-9_] _ws
    \\KW_MOD          <- _ws 'MOD' ![A-Za-z0-9_] _ws
    \\KW_OR           <- _ws 'OR' ![A-Za-z0-9_] _ws
    \\KW_IN           <- _ws 'IN' ![A-Za-z0-9_] _ws
    \\KW_IS           <- _ws 'IS' ![A-Za-z0-9_] _ws
    \\KW_OUT          <- _ws 'OUT' ![A-Za-z0-9_] _ws
    \\KW_READONLY     <- _ws 'READONLY' ![A-Za-z0-9_] _ws
    \\
    \\@silent _comment        <- '(*' (!'*)' .)* '*)'
    \\@silent _ws             <- ([ \t\n\r] / _comment)*
);

fn expectParseAll(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try cp.parse(arena.allocator(), "module", input);
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (cp.parse(arena.allocator(), "module", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
    } else |_| {}
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var c: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) c += 1;
    for (node.children) |child| c += countTag(child, tag);
    return c;
}

test "cp minimal module" {
    try expectParseAll(
        \\MODULE M;
        \\BEGIN
        \\END M.
    );
}

test "cp declarations and exported names" {
    try expectParseAll(
        \\MODULE Example;
        \\IMPORT Out;
        \\CONST N* = 10;
        \\TYPE T* = RECORD x: INTEGER END;
        \\VAR g*: T;
        \\BEGIN
        \\  g.x := N
        \\END Example.
    );
}

test "cp procedure params with modes" {
    try expectParseAll(
        \\MODULE P;
        \\TYPE Text = ARRAY 8 OF CHAR;
        \\PROCEDURE Copy*(IN src: Text; OUT dst: Text);
        \\BEGIN
        \\END Copy;
        \\PROCEDURE Use(VAR x: INTEGER; READONLY y: INTEGER): INTEGER;
        \\BEGIN
        \\  RETURN x + y
        \\END Use;
        \\BEGIN
        \\END P.
    );
}

test "cp control flow" {
    try expectParseAll(
        \\MODULE Flow;
        \\VAR i, s: INTEGER;
        \\BEGIN
        \\  IF i = 0 THEN s := 1 ELSIF i > 0 THEN s := 2 ELSE s := 3 END;
        \\  WHILE i < 10 DO i := i + 1 END;
        \\  REPEAT i := i - 1 UNTIL i = 0;
        \\  FOR i := 0 TO 10 BY 2 DO s := s + i END
        \\END Flow.
    );
}

test "cp tree checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\MODULE T;
        \\PROCEDURE P*(a: INTEGER);
        \\BEGIN
        \\  IF a > 0 THEN RETURN a ELSE RETURN 0 END
        \\END P;
        \\BEGIN
        \\END T.
    ;
    const r = try cp.parse(arena.allocator(), "module", input);
    try std.testing.expectEqual(@as(usize, 1), countTag(r.node, "module"));
    try std.testing.expectEqual(@as(usize, 1), countTag(r.node, "proc_decl"));
    try std.testing.expectEqual(@as(usize, 1), countTag(r.node, "if_stmt"));
}

test "cp invalid" {
    try expectFail("");
    try expectFail("MODULE X; BEGIN END.");
    try expectFail("MODULE X BEGIN END X.");
    try expectFail("MODULE X; VAR a: ; BEGIN END X.");
    try expectFail("MODULE X; PROCEDURE P(; BEGIN END P; BEGIN END X.");
}
