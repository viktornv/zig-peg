const std = @import("std");
const peg = @import("peg");

const ruby = peg.compile(
    \\program         <- _ws (_sep _ws)* (stmt (_sep _ws)*)+ _ws
    \\@squashed stmt  <- def_stmt / class_stmt / module_stmt / if_stmt / unless_stmt / while_stmt / assign_stmt / postfix_if_stmt / expr_stmt
    \\
    \\def_stmt        <- KW_def _ws ident (_ws def_params)? _sep block (_ws _sep _ws)* KW_end
    \\@squashed def_params <- '(' _ws (ident (_ws ',' _ws ident)*)? _ws ')'
    \\
    \\class_stmt      <- KW_class _ws const_name _sep block (_ws _sep _ws)* KW_end
    \\module_stmt     <- KW_module _ws const_name _sep block (_ws _sep _ws)* KW_end
    \\
    \\if_stmt         <- KW_if _ws expr _sep block (_ws elsif_part)* (_ws else_part)? (_ws _sep _ws)* KW_end
    \\@squashed elsif_part <- KW_elsif _ws expr _sep block
    \\@squashed else_part <- KW_else _sep block
    \\unless_stmt     <- KW_unless _ws expr _sep block (_ws else_part)? (_ws _sep _ws)* KW_end
    \\while_stmt      <- KW_while _ws expr _sep block (_ws _sep _ws)* KW_end
    \\
    \\postfix_if_stmt <- expr _ws KW_if _ws expr
    \\assign_stmt     <- ident _ws '=' _ws expr
    \\@squashed expr_stmt <- no_paren_call / expr
    \\@squashed no_paren_call <- ident _req_ws call_arg (_ws ',' _ws call_arg)*
    \\@squashed call_arg <- expr
    \\block           <- (_ws _sep _ws)* (_ws stmt (_ws _sep _ws)*)*
    \\
    \\expr            <- logic_or
    \\logic_or        <- logic_and logic_or_tail*
    \\@squashed logic_or_tail <- _ws (KW_or / '||') _ws logic_and
    \\logic_and       <- equality logic_and_tail*
    \\@squashed logic_and_tail <- _ws (KW_and / '&&') _ws equality
    \\equality        <- comparison equality_tail*
    \\@squashed equality_tail <- _ws ('==' / '!=') _ws comparison
    \\comparison      <- additive comparison_tail*
    \\@squashed comparison_tail <- _ws ('<=' / '>=' / '<' / '>') _ws additive
    \\additive        <- multiplicative additive_tail*
    \\@squashed additive_tail <- _ws ('+' / '-') _ws multiplicative
    \\multiplicative  <- unary multiplicative_tail*
    \\@squashed multiplicative_tail <- _ws ('*' / '/') _ws unary
    \\unary           <- (_ws (KW_not / '!') _ws unary) / postfix
    \\postfix         <- primary postfix_tail*
    \\@squashed postfix_tail <- call_args / dot_call
    \\@squashed dot_call <- _ws '.' _ws ident (_ws call_args)?
    \\@squashed call_args <- '(' _ws (expr (_ws ',' _ws expr)*)? _ws ')'
    \\
    \\primary         <- literal / array / hash / '(' _ws expr _ws ')' / ident / const_name
    \\@squashed literal <- string / float / integer / bool / nil
    \\bool            <- KW_true / KW_false
    \\nil             <- KW_nil
    \\array           <- '[' _ws (expr (_ws ',' _ws expr)*)? _ws ']'
    \\hash            <- '{' _ws (hash_pair (_ws ',' _ws hash_pair)*)? _ws '}'
    \\@squashed hash_pair <- (ident / string / symbol_key) _ws hash_sep _ws expr
    \\@squashed hash_sep <- '=>' / ':'
    \\@squashed symbol_key <- ':' ident
    \\
    \\string         <- '"' _strchar* '"'
    \\@silent _strchar        <- _esc / [^"\\]
    \\@silent _esc            <- '\\' ["\\/bfnrt]
    \\float          <- '-'? [0-9]+ '.' [0-9]+
    \\integer        <- '-'? [0-9]+
    \\ident          <- !_keyword [a-z_] [a-zA-Z0-9_]*
    \\const_name     <- [A-Z] [a-zA-Z0-9_]*
    \\@silent _req_ws         <- [ \t\r]+
    \\@silent _sep            <- (';' / '\n')+
    \\@silent _comment        <- '#' [^\n]*
    \\@silent _ws             <- ([ \t\r] / _comment)*
    \\
    \\KW_def          <- 'def' ![a-zA-Z0-9_]
    \\KW_class        <- 'class' ![a-zA-Z0-9_]
    \\KW_module       <- 'module' ![a-zA-Z0-9_]
    \\KW_end          <- 'end' ![a-zA-Z0-9_]
    \\KW_if           <- 'if' ![a-zA-Z0-9_]
    \\KW_elsif        <- 'elsif' ![a-zA-Z0-9_]
    \\KW_else         <- 'else' ![a-zA-Z0-9_]
    \\KW_unless       <- 'unless' ![a-zA-Z0-9_]
    \\KW_while        <- 'while' ![a-zA-Z0-9_]
    \\KW_and          <- 'and' ![a-zA-Z0-9_]
    \\KW_or           <- 'or' ![a-zA-Z0-9_]
    \\KW_not          <- 'not' ![a-zA-Z0-9_]
    \\KW_true         <- 'true' ![a-zA-Z0-9_]
    \\KW_false        <- 'false' ![a-zA-Z0-9_]
    \\KW_nil          <- 'nil' ![a-zA-Z0-9_]
    \\@silent _keyword        <- KW_def / KW_class / KW_module / KW_end / KW_if / KW_elsif / KW_else / KW_unless / KW_while / KW_and / KW_or / KW_not / KW_true / KW_false / KW_nil
);

fn expectParseAll(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try ruby.parse(arena.allocator(), "program", input);
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (ruby.parse(arena.allocator(), "program", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
    } else |_| {}
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var c: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) c += 1;
    for (node.children) |child| c += countTag(child, tag);
    return c;
}

test "ruby literals and collections" {
    try expectParseAll("x = 1");
    try expectParseAll("x = -7");
    try expectParseAll("x = 3.14");
    try expectParseAll("x = \"hello\"");
    try expectParseAll("x = true");
    try expectParseAll("x = false");
    try expectParseAll("x = nil");
    try expectParseAll("x = [1, 2, 3]");
    try expectParseAll("x = []");
    try expectParseAll("x = {a: 1, b: 2}");
    try expectParseAll("x = {\"a\" => 1}");
    try expectParseAll("x = {}");
}

test "ruby expressions and precedence" {
    try expectParseAll("x = 1 + 2 * 3");
    try expectParseAll("x = (1 + 2) * 3");
    try expectParseAll("x = 10 / 2 - 1");
    try expectParseAll("x = a > b");
    try expectParseAll("x = a >= b");
    try expectParseAll("x = a == b");
    try expectParseAll("x = a != b");
    try expectParseAll("x = true and false");
    try expectParseAll("x = true || false");
    try expectParseAll("x = not false");
    try expectParseAll("x = !false");
}

test "ruby calls and chaining" {
    try expectParseAll("foo()");
    try expectParseAll("foo(1, 2)");
    try expectParseAll("foo 1, 2");
    try expectParseAll("obj.method");
    try expectParseAll("obj.method()");
    try expectParseAll("obj.method(1, 2)");
    try expectParseAll("user.profile.name");
    try expectParseAll("user.profile.name.upcase()");
    try expectParseAll("result = service.call(1).next_step(2)");
}

test "ruby control flow" {
    try expectParseAll(
        \\if x > 0
        \\  y = 1
        \\end
    );
    try expectParseAll(
        \\if x > 0
        \\  y = 1
        \\elsif x < 0
        \\  y = -1
        \\else
        \\  y = 0
        \\end
    );
    try expectParseAll(
        \\unless done
        \\  work = 1
        \\else
        \\  work = 0
        \\end
    );
    try expectParseAll(
        \\while n > 0
        \\  n = n - 1
        \\end
    );
    try expectParseAll("puts(\"ok\") if ready");
}

test "ruby definitions and nesting" {
    try expectParseAll(
        \\def add(a, b)
        \\  a + b
        \\end
    );
    try expectParseAll(
        \\class User
        \\  def name()
        \\    "alice"
        \\  end
        \\end
    );
    try expectParseAll(
        \\module Auth
        \\  class Session
        \\    def active()
        \\      true
        \\    end
        \\  end
        \\end
    );
}

test "ruby whitespace and comments" {
    try expectParseAll("x=1; y=2; z=x+y");
    try expectParseAll(
        \\# comment
        \\x = 1
        \\# next
        \\y = x + 2
    );
    try expectParseAll("   foo( 1 , 2 )   ");
}

test "ruby tree asserts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const input =
        \\module M
        \\  class User
        \\    def run(a)
        \\      if a > 0
        \\        puts(a)
        \\      else
        \\        puts(0)
        \\      end
        \\    end
        \\  end
        \\end
    ;
    const result = try ruby.parse(arena.allocator(), "program", input);
    try std.testing.expectEqual(@as(usize, 1), countTag(result.node, "module_stmt"));
    try std.testing.expectEqual(@as(usize, 1), countTag(result.node, "class_stmt"));
    try std.testing.expectEqual(@as(usize, 1), countTag(result.node, "def_stmt"));
    try std.testing.expectEqual(@as(usize, 1), countTag(result.node, "if_stmt"));
}

test "ruby invalid programs" {
    try expectFail("");
    try expectFail("if x > 0");
    try expectFail("def foo(a, b");
    try expectFail("class User");
    try expectFail("module A");
    try expectFail("x = ");
    try expectFail("x = [1, 2, ]");
    try expectFail("x = {a: 1,}");
    try expectFail("x = \"unterminated");
    try expectFail("foo(");
    try expectFail("foo 1,");
    try expectFail("= 1");
    try expectFail("puts 1 if");
    try expectFail("unless x\n y = 1");
    try expectFail("while x > 0\nx = x - 1");
    try expectFail("obj..name");
}
