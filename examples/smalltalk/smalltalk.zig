const std = @import("std");
const peg = @import("peg");

const st = peg.compile(
    // === Точки входа ===
    \\script       <- _ws stmtlist _ws
    \\program      <- _ws topitems _ws
    
    // === Верхний уровень ===
    \\topitems     <- topitem (_ws topitem)*
    \\topitem      <- classdef / methoddef
    \\
    // === Определение класса ===
    \\classdef     <- variable _ws 'subclass:' _ws symbol
    \\               _ws 'instanceVariableNames:' _ws string
    \\               (_ws 'classVariableNames:' _ws string)?
    \\               (_ws 'poolDictionaries:' _ws string)?
    \\               (_ws 'category:' _ws string)?
    \\
    // === Определение метода ===
    \\methoddef    <- methodpat (_ws temps)? (_ws pragmas)? _ws stmtlist
    \\methodpat    <- kwmethpat / binmethpat / unarymethpat
    \\unarymethpat <- variable
    \\binmethpat   <- binsel _ws variable
    \\kwmethpat    <- (keyword _ws variable)+
    \\
    // === Прагмы ===
    \\pragmas      <- pragma (_ws pragma)*
    \\pragma       <- '<' pragbody '>'
    \\pragbody     <- kwpragma / unarypragma
    \\kwpragma     <- (keyword literal)+
    \\unarypragma  <- variable
    \\
    // === Временные переменные ===
    \\temps        <- '|' _ws (variable _ws)* '|'
    \\
    // === Список операторов ===
    \\stmtlist     <- temps? stmts?
    \\stmts        <- stmt (_ws '.' _ws stmt)* (_ws '.')?
    \\stmt         <- returnstmt / exprstmt
    \\returnstmt   <- '^' _ws expr
    \\exprstmt     <- assign / cascade
    \\
    // === Присваивание ===
    \\assign       <- variable _ws ':=' _ws expr
    \\
    // === Выражения ===
    \\expr         <- cascade
    \\cascade      <- keymsg (_ws ';' _ws cascmsg)*
    \\cascmsg      <- kwpart / binmsg_tail / unarymsg
    \\
    // === Сообщения ===
    \\keymsg       <- binexpr (_ws kwpart)+
    \\             / binexpr
    \\kwpart       <- keyword _ws binexpr
    \\keyword      <- _identraw ':'
    \\
    \\binexpr      <- unaryexpr (_ws binmsg_tail)*
    \\binmsg_tail  <- binsel _ws unaryexpr
    \\binsel       <- [+\-*/=<>&@%~|!?,\\] [+\-*/=<>&@%~|!?,\\]*
    \\
    \\unaryexpr    <- primary (unarymsg)*
    \\unarymsg     <- _ws _identraw !':'
    \\
    // === Первичные выражения ===
    \\primary      <- block / dynarray / literal / variable / '(' _ws expr _ws ')'
    \\variable     <- _ws ('self' !_icont / 'super' !_icont / 'thisContext' !_icont / _ident) _ws
    \\
    // === Блоки ===
    \\block        <- '[' _ws blockargs? _ws blockbody? _ws ']'
    \\blockargs    <- (':' _ws variable)+ _ws '|'
    \\blockbody    <- stmtlist
    \\
    // === Динамические массивы ===
    \\dynarray     <- '{' _ws dynelems? _ws '}'
    \\dynelems     <- expr (_ws '.' _ws expr)* (_ws '.')?
    \\
    // === Литералы ===
    \\literal      <- number / string / symbol / char / bytearray / array / bool / nil
    \\
    // === Числа ===
    \\number       <- radixnum / float / integer
    \\radixnum     <- _ws [0-9]+ 'r' [0-9a-zA-Z]+ _ws
    \\float        <- _ws '-'? [0-9]+ '.' [0-9]+ (('e' / 'E') ('-' / '+')? [0-9]+)? _ws
    \\integer      <- _ws '-'? [0-9]+ _ws
    \\
    // === Строки ===
    \\string       <- _ws '\'' strchar* '\'' _ws
    \\strchar      <- '\'\'' / [^']
    \\
    // === Символы ===
    \\symbol       <- _ws '#' symval _ws
    \\symval       <- _identraw (':' _identraw ':')* ':'?
    \\             / binsel
    \\             / '\'' [^']* '\''
    \\
    // === Символьные литералы ===
    \\char         <- _ws '$' . _ws
    \\
    // === Байтовые массивы ===
    \\bytearray    <- _ws '#[' _ws byteelems? _ws ']' _ws
    \\byteelems    <- integer (_ws integer)*
    \\
    // === Литеральные массивы ===
    \\array        <- _ws '#(' _ws arritem* _ws ')' _ws
    \\arritem      <- literal _ws
    \\
    // === Bool / Nil ===
    \\bool         <- _ws ('true' !_icont / 'false' !_icont) _ws
    \\nil          <- _ws 'nil' !_icont _ws
    \\
    // === Идентификатор ===
    \\@silent _ident       <- !_reserved [a-zA-Z_] _icont*
    \\@silent _identraw    <- [a-zA-Z_] _icont*
    \\@silent _icont       <- [a-zA-Z0-9_]
    \\@silent _reserved    <- ('true' / 'false' / 'nil' / 'self' / 'super' / 'thisContext') !_icont
    \\
    // === Пробелы и комментарии ===
    \\@silent _ws          <- ([ \t\n\r] / _comment)*
    \\@silent _comment     <- '"' [^"]* '"'
);

// === Хелперы ===

fn expectParse(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    
    // 1. Попытка как скрипт (выражения)
    if (st.parse(arena.allocator(), "script", input)) |result| {
        if (result.pos == input.len) {
            std.debug.print("  OK (script): {s}\n", .{input[0..@min(input.len, 60)]});
            return;
        }
    } else |_| {}

    // 2. Попытка как программа (классы/методы)
    if (st.parse(arena.allocator(), "program", input)) |result| {
        if (result.pos == input.len) {
            std.debug.print("  OK (program): {s}\n", .{input[0..@min(input.len, 60)]});
            return;
        }
    } else |_| {}

    std.debug.print("  FAIL: \"{s}\"\n", .{ input[0..@min(input.len, 60)] });
    return error.TestUnexpectedResult;
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var c: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) c += 1;
    for (node.children) |child| c += countTag(child, tag);
    return c;
}

// ===================== TESTS =====================

// === Литералы ===

test "integers" {
    std.debug.print("\n-- st: integers --\n", .{});
    try expectParse("42");
    try expectParse("0");
    try expectParse("-7");
    try expectParse("123456");
}

test "floats" {
    std.debug.print("\n-- st: floats --\n", .{});
    try expectParse("3.14");
    try expectParse("-0.5");
    try expectParse("100.001");
    try expectParse("1.5e10");
    try expectParse("2.5E-3");
}

test "radix numbers" {
    std.debug.print("\n-- st: radix --\n", .{});
    try expectParse("16rFF");
    try expectParse("2r1010");
    try expectParse("8r777");
    try expectParse("16rDEADBEEF");
}

test "strings" {
    std.debug.print("\n-- st: strings --\n", .{});
    try expectParse("'hello'");
    try expectParse("''");
    try expectParse("'hello world'");
    try expectParse("'it''s'");
}

test "symbols" {
    std.debug.print("\n-- st: symbols --\n", .{});
    try expectParse("#foo");
    try expectParse("#at:put:");
    try expectParse("#+");
    try expectParse("#>=");
    try expectParse("#'hello world'");
}

test "characters" {
    std.debug.print("\n-- st: characters --\n", .{});
    try expectParse("$A");
    try expectParse("$x");
    try expectParse("$0");
    try expectParse("$ ");
}

test "literal arrays" {
    std.debug.print("\n-- st: arrays --\n", .{});
    try expectParse("#()");
    try expectParse("#(1 2 3)");
    try expectParse("#(1 'hello' #foo)");
    try expectParse("#(#(1 2) #(3 4))");
    try expectParse("#(true false nil)");
}

test "byte arrays" {
    std.debug.print("\n-- st: byte arrays --\n", .{});
    try expectParse("#[1 2 3]");
    try expectParse("#[0 255 128]");
    try expectParse("#[]");
}

test "booleans and nil" {
    std.debug.print("\n-- st: bool/nil --\n", .{});
    try expectParse("true");
    try expectParse("false");
    try expectParse("nil");
}

// === Переменные ===

test "variables" {
    std.debug.print("\n-- st: variables --\n", .{});
    try expectParse("x");
    try expectParse("myVar");
    try expectParse("self");
    try expectParse("super");
    try expectParse("thisContext");
}

// === Присваивание ===

test "assignment" {
    std.debug.print("\n-- st: assignment --\n", .{});
    try expectParse("x := 1");
    try expectParse("x := 'hello'");
    try expectParse("x := y");
    try expectParse("x := 1 + 2");
}

// === Временные переменные ===

test "temporaries" {
    std.debug.print("\n-- st: temps --\n", .{});
    // Это script с temps
    try expectParse("| x | x := 1");
    try expectParse("| x y z | x := 1");
    try expectParse("| temp result | temp := 0. result := temp + 1");
}

// === Унарные сообщения ===

test "unary messages" {
    std.debug.print("\n-- st: unary --\n", .{});
    try expectParse("3 factorial");
    try expectParse("'hello' size");
    try expectParse("x isNil");
    try expectParse("1 abs negated");
    try expectParse("x class name");
}

// === Бинарные сообщения ===

test "binary messages" {
    std.debug.print("\n-- st: binary --\n", .{});
    try expectParse("1 + 2");
    try expectParse("3 * 4");
    try expectParse("10 - 3");
    try expectParse("10 / 2");
    try expectParse("x = y");
    try expectParse("a < b");
    try expectParse("a >= b");
    try expectParse("1 + 2 * 3");
    try expectParse("x @ y");
}

// === Ключевые сообщения ===

test "keyword messages" {
    std.debug.print("\n-- st: keyword --\n", .{});
    try expectParse("x at: 1");
    try expectParse("x at: 1 put: 2");
    try expectParse("x ifTrue: y");
    try expectParse("x between: 1 and: 10");
    try expectParse("dict at: key ifAbsent: [nil]");
}

// === Приоритет ===

test "message priority" {
    std.debug.print("\n-- st: priority --\n", .{});
    try expectParse("2 factorial + 1");
    try expectParse("3 + 4 factorial");
    try expectParse("1 + 2 max: 3");
    try expectParse("x size + 1 max: 10");
}

// === Скобки ===

test "parentheses" {
    std.debug.print("\n-- st: parens --\n", .{});
    try expectParse("(1 + 2) * 3");
    try expectParse("(x at: 1) + 1");
    try expectParse("((1 + 2))");
    try expectParse("(x between: 1 and: 10) ifTrue: [y]");
}

// === Блоки ===

test "blocks" {
    std.debug.print("\n-- st: blocks --\n", .{});
    try expectParse("[1]");
    try expectParse("[x + 1]");
    try expectParse("[:x | x + 1]");
    try expectParse("[:x :y | x + y]");
    try expectParse("[1. 2. 3]");
    try expectParse("[:x | x print. x + 1]");
}

test "block messages" {
    std.debug.print("\n-- st: block msgs --\n", .{});
    try expectParse("[1 + 2] value");
    try expectParse("[:x | x * 2] value: 5");
    try expectParse("[:x :y | x + y] value: 3 value: 4");
}

test "nested blocks" {
    std.debug.print("\n-- st: nested blocks --\n", .{});
    try expectParse("[[:x | x + 1] value: 5]");
    try expectParse("[:x | [:y | x + y]]");
    try expectParse("x ifTrue: [y ifFalse: [z]]");
}

// === Динамические массивы ===

test "dynamic arrays" {
    std.debug.print("\n-- st: dynamic arrays --\n", .{});
    try expectParse("{1. 2. 3}");
    try expectParse("{1 + 2. 3 * 4}");
    try expectParse("{x. y. z}");
    try expectParse("{}");
}

// === Каскад ===

test "cascade" {
    std.debug.print("\n-- st: cascade --\n", .{});
    try expectParse("x add: 1; add: 2; add: 3");
    try expectParse("x add: 1; size");
    try expectParse("x print; yourself");
}

// === Возврат ===

test "return" {
    std.debug.print("\n-- st: return --\n", .{});
    try expectParse("^ 42");
    try expectParse("^ x + 1");
    try expectParse("^ self");
}

// === Множественные выражения ===

test "multiple statements" {
    std.debug.print("\n-- st: multi --\n", .{});
    try expectParse("x := 1. y := 2");
    try expectParse("x := 1. y := 2. x + y");
    try expectParse("x := 1. y := x + 1. ^ y");
}

// === Комментарии ===

test "comments" {
    std.debug.print("\n-- st: comments --\n", .{});
    try expectParse("\"a comment\" 42");
    try expectParse("x := 1 \"assign\" + 2");
    try expectParse("\"start\" x := 1. \"end\" ^ x");
}

// === Whitespace ===

test "whitespace" {
    std.debug.print("\n-- st: whitespace --\n", .{});
    try expectParse("  42  ");
    try expectParse("  x  :=  1  ");
    try expectParse("x\n:=\n1");
    try expectParse("  x   at:  1   put:  2  ");
}

// === Trailing dot ===

test "trailing dot" {
    std.debug.print("\n-- st: trailing dot --\n", .{});
    try expectParse("x := 1.");
    try expectParse("x := 1. y := 2.");
    try expectParse("x print.");
}

// === Управление потоком ===

test "control flow" {
    std.debug.print("\n-- st: control --\n", .{});
    try expectParse("x > 0 ifTrue: [1] ifFalse: [-1]");
    try expectParse("[x > 0] whileTrue: [x := x - 1]");
    try expectParse("1 to: 10 do: [:i | i print]");
    try expectParse("x isNil ifTrue: [^ nil]");
}

// === Коллекции ===

test "collection operations" {
    std.debug.print("\n-- st: collections --\n", .{});
    try expectParse("#(1 2 3) do: [:each | each print]");
    try expectParse("#(1 2 3) select: [:each | each > 1]");
    try expectParse("#(1 2 3) collect: [:each | each * 2]");
    try expectParse("#(1 2 3) inject: 0 into: [:sum :each | sum + each]");
}

// === Объекты ===

test "object style" {
    std.debug.print("\n-- st: object --\n", .{});
    try expectParse("OrderedCollection new");
    try expectParse("OrderedCollection new add: 1; add: 2; yourself");
    try expectParse("Dictionary new at: #key put: 'value'");
    try expectParse("Point x: 10 y: 20");
    try expectParse("(Point x: 3 y: 4) dist");
}

// === Сложные программы ===

test "factorial style" {
    std.debug.print("\n-- st: factorial --\n", .{});
    try expectParse(
        \\| n result |
        \\n := 5.
        \\result := 1.
        \\1 to: n do: [:i | result := result * i].
        \\^ result
    );
}

test "fibonacci style" {
    std.debug.print("\n-- st: fibonacci --\n", .{});
    try expectParse(
        \\| a b temp |
        \\a := 0.
        \\b := 1.
        \\1 to: 10 do: [:i |
        \\  temp := b.
        \\  b := a + b.
        \\  a := temp
        \\].
        \\^ b
    );
}

test "fizzbuzz style" {
    std.debug.print("\n-- st: fizzbuzz --\n", .{});
    try expectParse(
        \\1 to: 100 do: [:i |
        \\  (i \\ 15 = 0)
        \\    ifTrue: ['FizzBuzz' print]
        \\    ifFalse: [(i \\ 3 = 0)
        \\      ifTrue: ['Fizz' print]
        \\      ifFalse: [(i \\ 5 = 0)
        \\        ifTrue: ['Buzz' print]
        \\        ifFalse: [i print]]]
        \\]
    );
}

test "complex with temps" {
    std.debug.print("\n-- st: complex temps --\n", .{});
    try expectParse(
        \\| list total |
        \\list := OrderedCollection new.
        \\list add: 10; add: 20; add: 30.
        \\total := 0.
        \\list do: [:each | total := total + each].
        \\^ total
    );
}

// === Метод (pattern) ===

test "unary method pattern" {
    std.debug.print("\n-- st: unary method --\n", .{});
    try expectParse(
        \\printOn
        \\  | x |
        \\  x := self size.
        \\  ^ x
    );
}

test "binary method pattern" {
    std.debug.print("\n-- st: binary method --\n", .{});
    try expectParse(
        \\+ other
        \\  ^ self value + other value
    );
}

test "keyword method pattern" {
    std.debug.print("\n-- st: keyword method --\n", .{});
    try expectParse(
        \\at: index put: value
        \\  | old |
        \\  old := self at: index.
        \\  ^ old
    );
}

// === Прагмы ===

test "pragmas" {
    std.debug.print("\n-- st: pragmas --\n", .{});
    try expectParse(
        \\doSomething
        \\  <primitive: 42>
        \\  ^ self
    );
    try expectParse(
        \\category
        \\  <category: 'accessing'>
        \\  ^ self
    );
}

// === Класс ===

test "class definition" {
    std.debug.print("\n-- st: class definition --\n", .{});
    try expectParse(
        \\Object subclass: #MyClass
        \\  instanceVariableNames: 'a b c'
        \\  classVariableNames: ''
        \\  poolDictionaries: ''
        \\  category: 'MyCategory'
    );
}

// === Дерево ===

test "tree structure" {
    std.debug.print("\n-- st: tree --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try st.parse(arena.allocator(), "script",
        "| x | x := #(1 2 3) collect: [:each | each * 2]. ^ x"
    );
    peg.printTree(result.node, 2);

    try std.testing.expect(countTag(result.node, "assign") == 1);
    try std.testing.expect(countTag(result.node, "block") >= 1);
    try std.testing.expect(countTag(result.node, "array") >= 1);
    try std.testing.expect(countTag(result.node, "keyword") >= 1);
    try std.testing.expect(countTag(result.node, "temps") >= 1);
    try std.testing.expect(countTag(result.node, "returnstmt") >= 1);
    std.debug.print("  OK: tree verified\n", .{});
}

test "keyword tree" {
    std.debug.print("\n-- st: kw tree --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try st.parse(arena.allocator(), "script",
        "x at: 1 put: 2"
    );
    peg.printTree(result.node, 2);

    try std.testing.expect(countTag(result.node, "keymsg") >= 1);
    try std.testing.expect(countTag(result.node, "kwpart") == 2);
    try std.testing.expect(countTag(result.node, "keyword") == 2);
    std.debug.print("  OK: keyword tree\n", .{});
}

// === Ошибки ===

test "detailed errors" {
    std.debug.print("\n-- st: errors --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const r1 = st.parseDetailed(arena.allocator(), "script", "[");
    switch (r1) {
        .ok => |ok| std.debug.print("  '[' partial, pos={}\n", .{ok.pos}),
        .err => |e| std.debug.print("  '[' error at {}:{}: {s}\n", .{ e.line, e.col, e.expected }),
    }

    const r2 = st.parseDetailed(arena.allocator(), "script", "x := ");
    switch (r2) {
        .ok => |ok| std.debug.print("  'x := ' partial, pos={}\n", .{ok.pos}),
        .err => |e| std.debug.print("  'x := ' error at {}:{}: {s}\n", .{ e.line, e.col, e.expected }),
    }
}