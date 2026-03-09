const std = @import("std");
const peg = @import("peg");

const lang1c = peg.compile(
    \\module       <- _ws (stmt _sep)* _ws
    \\@squashed stmt <- compound / if_stmt / for_stmt / foreach_stmt / while_stmt
    \\              / try_stmt / raise_stmt / return_stmt / continue_stmt / break_stmt
    \\              / goto_stmt / label_stmt / addhandler / removehandler
    \\              / execute_stmt / vardecl / assign / proccall
    \\@squashed compound <- procedure / function
    \\procedure    <- KW_proc ident '(' params? ')' export? _sep
    \\               (stmt _sep)*
    \\               KW_endproc
    \\function     <- KW_func ident '(' params? ')' export? _sep
    \\               (stmt _sep)*
    \\               KW_endfunc
    \\params       <- param (',' param)*
    \\param        <- KW_val ident ('=' expr)? / ident ('=' expr)?
    \\@squashed export <- KW_export
    \\if_stmt      <- KW_if expr KW_then _sep
    \\               (stmt _sep)*
    \\               elseif_part*
    \\               else_part?
    \\               KW_endif
    \\elseif_part  <- KW_elseif expr KW_then _sep
    \\               (stmt _sep)*
    \\else_part    <- KW_else _sep
    \\               (stmt _sep)*
    \\for_stmt     <- KW_for ident '=' expr KW_to expr (KW_do)? _sep
    \\               (stmt _sep)*
    \\               KW_endfor
    \\foreach_stmt <- KW_foreach ident KW_in expr (KW_do)? _sep
    \\               (stmt _sep)*
    \\               KW_endfor
    \\while_stmt   <- KW_while expr KW_do _sep
    \\               (stmt _sep)*
    \\               KW_endwhile
    \\try_stmt     <- KW_try _sep
    \\               (stmt _sep)*
    \\               KW_except _sep
    \\               (stmt _sep)*
    \\               KW_endtry
    \\raise_stmt    <- KW_raise (expr)?
    \\return_stmt   <- KW_return (expr)?
    \\continue_stmt <- KW_continue
    \\break_stmt    <- KW_break
    \\goto_stmt     <- KW_goto '~' ident
    \\label_stmt    <- '~' ident ':'
    \\execute_stmt  <- KW_execute '(' expr ')'
    \\addhandler    <- KW_addhandler expr ',' expr
    \\removehandler <- KW_removehandler expr ',' expr
    \\vardecl      <- KW_var vardecllist
    \\vardecllist  <- vardeclitem (',' vardeclitem)*
    \\vardeclitem  <- ident (KW_export)?
    \\assign       <- lvalue '=' expr
    \\proccall     <- memberexpr
    \\expr         <- ternary
    \\@squashed ternary <- logic_or
    \\ternaryop    <- '?' _ws '(' _ws expr _ws ',' _ws expr _ws ',' _ws expr _ws ')'
    \\logic_or     <- logic_and (KW_or logic_and)*
    \\logic_and    <- logic_not (KW_and logic_not)*
    \\logic_not    <- KW_not logic_not / comparison
    \\comparison   <- addition (_ws cmp_op _ws addition)?
    \\cmp_op       <- '<=' / '>=' / '<>' / '<' / '>' / '='
    \\addition     <- multiplication (_ws add_op _ws multiplication)*
    \\add_op       <- '+' / '-'
    \\multiplication <- unary (_ws mul_op _ws unary)*
    \\mul_op       <- '*' / '/' / '%'
    \\unary        <- _ws ('-' _ws unary / '+' _ws unary / memberexpr)
    \\memberexpr   <- primary (accessor)*
    \\accessor     <- '.' ident '(' _ws arglist? _ws ')'
    \\             / '.' ident
    \\             / '[' _ws expr _ws ']'
    \\             / '(' _ws arglist? _ws ')'
    \\primary      <- ternaryop / newexpr / literal / ident / '(' _ws expr _ws ')'
    \\newexpr      <- KW_new ident ('(' _ws arglist? _ws ')')?
    \\             / KW_new '(' _ws arglist? _ws ')'
    \\arglist      <- argitem (_ws ',' _ws argitem)*
    \\@squashed argitem <- expr / ''
    \\@squashed lvalue <- memberexpr
    \\literal      <- string / number / date / bool / undefined / null
    \\string       <- _ws '"' strchar* '"' _ws
    \\strchar      <- '""' / [^"\n]
    \\number       <- _ws [0-9]+ ('.' [0-9]+)? _ws
    \\date         <- _ws '\'' _datebody '\'' _ws
    \\@silent _datebody    <- [0-9] [0-9] [0-9] [0-9] [0-9] [0-9] [0-9] [0-9]
    \\               ([0-9] [0-9] [0-9] [0-9] [0-9] [0-9])?
    \\bool         <- KW_true / KW_false
    \\undefined    <- KW_undefined
    \\null         <- KW_null
    \\ident        <- _ws !_keyword _identchar _identrest* _ws
    \\@silent _identchar   <- [a-zA-Z_\x80-\xff]
    \\@silent _identrest   <- [a-zA-Z0-9_\x80-\xff]
    \\KW_proc          <- _ws ('Процедура' / 'Procedure'i) !_identrest _ws
    \\KW_endproc       <- _ws ('КонецПроцедуры' / 'EndProcedure'i) !_identrest _ws
    \\KW_func          <- _ws ('Функция' / 'Function'i) !_identrest _ws
    \\KW_endfunc       <- _ws ('КонецФункции' / 'EndFunction'i) !_identrest _ws
    \\KW_var           <- _ws ('Перем' / 'Var'i) !_identrest _ws
    \\KW_val           <- _ws ('Знач' / 'Val'i) !_identrest _ws
    \\KW_if            <- _ws ('Если' / 'If'i) !_identrest _ws
    \\KW_then          <- _ws ('Тогда' / 'Then'i) !_identrest _ws
    \\KW_elseif        <- _ws ('ИначеЕсли' / 'ElsIf'i) !_identrest _ws
    \\KW_else          <- _ws ('Иначе' / 'Else'i) !_identrest _ws
    \\KW_endif         <- _ws ('КонецЕсли' / 'EndIf'i) !_identrest _ws
    \\KW_for           <- _ws ('Для' / 'For'i) !_identrest _ws
    \\KW_to            <- _ws ('По' / 'To'i) !_identrest _ws
    \\KW_foreach       <- _ws ('ДляКаждого' / 'Для каждого' / 'ForEach'i) !_identrest _ws
    \\KW_in            <- _ws ('Из' / 'В' / 'In'i) !_identrest _ws
    \\KW_endfor        <- _ws ('КонецЦикла' / 'EndDo'i) !_identrest _ws
    \\KW_while         <- _ws ('Пока' / 'While'i) !_identrest _ws
    \\KW_do            <- _ws ('Цикл' / 'Do'i) !_identrest _ws
    \\KW_endwhile      <- _ws ('КонецЦикла' / 'EndDo'i) !_identrest _ws
    \\KW_try           <- _ws ('Попытка' / 'Try'i) !_identrest _ws
    \\KW_except        <- _ws ('Исключение' / 'Except'i) !_identrest _ws
    \\KW_endtry        <- _ws ('КонецПопытки' / 'EndTry'i) !_identrest _ws
    \\KW_raise         <- _ws ('ВызватьИсключение' / 'Raise'i) !_identrest _ws
    \\KW_return        <- _ws ('Возврат' / 'Return'i) !_identrest _ws
    \\KW_continue      <- _ws ('Продолжить' / 'Continue'i) !_identrest _ws
    \\KW_break         <- _ws ('Прервать' / 'Break'i) !_identrest _ws
    \\KW_goto          <- _ws ('Перейти' / 'Goto'i) !_identrest _ws
    \\KW_execute       <- _ws ('Выполнить' / 'Execute'i) !_identrest _ws
    \\KW_and           <- _ws ('И' / 'And'i) !_identrest _ws
    \\KW_or            <- _ws ('Или' / 'Or'i) !_identrest _ws
    \\KW_not           <- _ws ('Не' / 'Not'i) !_identrest _ws
    \\KW_true          <- _ws ('Истина' / 'True'i) !_identrest _ws
    \\KW_false         <- _ws ('Ложь' / 'False'i) !_identrest _ws
    \\KW_undefined     <- _ws ('Неопределено' / 'Undefined'i) !_identrest _ws
    \\KW_null          <- _ws ('NULL' / 'Null') !_identrest _ws
    \\KW_export        <- _ws ('Экспорт' / 'Export'i) !_identrest _ws
    \\KW_new           <- _ws ('Новый' / 'New'i) !_identrest _ws
    \\KW_addhandler    <- _ws ('ДобавитьОбработчик' / 'AddHandler'i) !_identrest _ws
    \\KW_removehandler <- _ws ('УдалитьОбработчик' / 'RemoveHandler'i) !_identrest _ws
    \\@silent _keyword     <- ( 'КонецПроцедуры' / 'КонецФункции' / 'КонецЕсли' / 'КонецЦикла'
    \\              / 'КонецПопытки' / 'ВызватьИсключение' / 'ДобавитьОбработчик'
    \\              / 'УдалитьОбработчик' / 'Неопределено' / 'Продолжить'
    \\              / 'Исключение' / 'Выполнить' / 'ДляКаждого' / 'ИначеЕсли'
    \\              / 'Процедура' / 'Прервать' / 'Перейти' / 'Возврат'
    \\              / 'Попытка' / 'Функция' / 'Экспорт' / 'Истина'
    \\              / 'Тогда' / 'Иначе' / 'Новый' / 'Перем' / 'Пока' / 'Цикл'
    \\              / 'Если' / 'Знач' / 'Ложь' / 'Для' / 'Или'
    \\              / 'По' / 'Из' / 'Не' / 'И'
    \\              / 'EndProcedure'i / 'EndFunction'i / 'Procedure'i / 'Function'i
    \\              / 'ForEach'i / 'EndDo'i / 'EndIf'i / 'EndTry'i
    \\              / 'AddHandler'i / 'RemoveHandler'i
    \\              / 'Undefined'i / 'Continue'i / 'Execute'i
    \\              / 'Except'i / 'Export'i / 'Return'i
    \\              / 'ElsIf'i / 'While'i / 'Break'i / 'Raise'i
    \\              / 'False'i / 'Then'i / 'Else'i / 'Goto'i / 'True'i
    \\              / 'NULL' / 'Null'
    \\              / 'Var'i / 'Val'i / 'For'i / 'New'i / 'Try'i / 'And'i / 'Not'i
    \\              / 'If'i / 'In'i / 'To'i / 'Or'i / 'Do'i
    \\              ) !_identrest
    \\@silent _ws          <- ([ \t\n\r] / _comment)*
    \\@silent _sep         <- _ws (';' _ws)*
    \\@silent _comment     <- '//' [^\n]*
);

// === Тестовые хелперы ===

fn expectParse(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try lang1c.parse(arena.allocator(), "module", input);
    if (result.pos != input.len) {
        std.debug.print("  FAIL: parsed {}/{}\n", .{ result.pos, input.len });
        return error.TestUnexpectedResult;
    }
    std.debug.print("  OK\n", .{});
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (lang1c.parse(arena.allocator(), "module", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
        std.debug.print("  PARTIAL (ok)\n", .{});
    } else |_| {
        std.debug.print("  REJECTED (ok)\n", .{});
    }
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var c: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) c += 1;
    for (node.children) |child| c += countTag(child, tag);
    return c;
}

// ===================== ТЕСТЫ =====================

test "variable declaration" {
    std.debug.print("\n-- 1c: var decl --\n", .{});
    const cases = [_][]const u8{
        "Var x;",
        "Перем x;",
        "Var x, y, z;",
        "Перем x, y, z;",
        "Var x Export;",
        "Перем x Экспорт;",
    };
    for (cases) |input| try expectParse(input);
}

test "assignment" {
    std.debug.print("\n-- 1c: assign --\n", .{});
    const cases = [_][]const u8{
        "x = 1;",
        "x = 1 + 2;",
        "x = \"hello\";",
        "x = True;",
        "x = Истина;",
        "x = False;",
        "x = Ложь;",
        "x = Undefined;",
        "x = Неопределено;",
        "x = NULL;",
    };
    for (cases) |input| try expectParse(input);
}

test "literals number" {
    std.debug.print("\n-- 1c: number --\n", .{});
    const cases = [_][]const u8{ "x = 0;", "x = 42;", "x = 3.14;", "x = 100.00;" };
    for (cases) |input| try expectParse(input);
}

test "literals string" {
    std.debug.print("\n-- 1c: string --\n", .{});
    const cases = [_][]const u8{
        "x = \"\";",
        "x = \"hello\";",
        "x = \"hello world\";",
        "x = \"he said \"\"hi\"\"\";",
    };
    for (cases) |input| try expectParse(input);
}

test "literals date" {
    std.debug.print("\n-- 1c: date --\n", .{});
    const cases = [_][]const u8{
        "x = '20240101';",
        "x = '20240315120000';",
    };
    for (cases) |input| try expectParse(input);
}

test "literals bool" {
    std.debug.print("\n-- 1c: bool --\n", .{});
    const cases = [_][]const u8{
        "x = True;",
        "x = Истина;",
        "x = False;",
        "x = Ложь;",
        "x = Undefined;",
        "x = Неопределено;",
        "x = NULL;",
        "x = Null;",
    };
    for (cases) |input| try expectParse(input);
}

test "arithmetic" {
    std.debug.print("\n-- 1c: arithmetic --\n", .{});
    const cases = [_][]const u8{
        "x = 1 + 2;",
        "x = 10 - 3;",
        "x = 2 * 3;",
        "x = 10 / 3;",
        "x = 10 % 3;",
        "x = (1 + 2) * 3;",
        "x = -5;",
        "x = +5;",
    };
    for (cases) |input| try expectParse(input);
}

test "comparison" {
    std.debug.print("\n-- 1c: comparison --\n", .{});
    const cases = [_][]const u8{
        "x = a = b;",
        "x = a <> b;",
        "x = a < b;",
        "x = a > b;",
        "x = a <= b;",
        "x = a >= b;",
    };
    for (cases) |input| try expectParse(input);
}

test "logic" {
    std.debug.print("\n-- 1c: logic --\n", .{});
    try expectParse("x = a And b;");
    try expectParse("x = a И b;");
    try expectParse("x = a Or b;");
    try expectParse("x = a ИЛИ b;");
    try expectParse("x = Not a;");
    try expectParse("x = НЕ a;");
    try expectParse("x = a And b Or c;");
    try expectParse("x = a И b ИЛИ c;");
    try expectParse("x = Not (a And b);");
    try expectParse("x = НЕ (a И b);");
}

test "ternary" {
    std.debug.print("\n-- 1c: ternary --\n", .{});
    try expectParse("x = ?(a > 0, a, -a);");
    try expectParse("x = ?(True, 1, 0);");
    try expectParse("x = ?(Истина, 1, 0);");
}

test "procedure call" {
    std.debug.print("\n-- 1c: proc call --\n", .{});
    try expectParse("Message(\"hello\");");
    try expectParse("Сообщить(\"hello\");");
    try expectParse("DoSomething();");
    try expectParse("Calc(1, 2, 3);");
    try expectParse("Калс(1, 2, 3);");
    try expectParse("Calc(1, , 3);");
    try expectParse("Калс(1, , 3);");
}

test "method call" {
    std.debug.print("\n-- 1c: method call --\n", .{});
    try expectParse("obj.Method();");
    try expectParse("obj.Method(1, 2);");
    try expectParse("obj.Prop.Method();");
    try expectParse("arr[0].Method();");
}

test "member access" {
    std.debug.print("\n-- 1c: member access --\n", .{});
    try expectParse("x = obj.Property;");
    try expectParse("x = obj.Sub.Property;");
    try expectParse("x = arr[0];");
    try expectParse("x = arr[i + 1];");
    try expectParse("x = map[\"key\"];");
}

test "new expression" {
    std.debug.print("\n-- 1c: new --\n", .{});
    try expectParse("x = New Array;");
    try expectParse("x = Новый Массив;");
    try expectParse("x = New Array();");
    try expectParse("x = New Array(10);");
    try expectParse("x = New Structure(\"Key\", \"Value\");");
    try expectParse("x = New Map;");
}

test "if statement" {
    std.debug.print("\n-- 1c: if --\n", .{});
    try expectParse(
        \\If x > 0 Then
        \\  y = x;
        \\EndIf;
    );
    try expectParse(
        \\Если x > 0 Тогда
        \\  y = x;
        \\КонецЕсли;
    );
    try expectParse(
        \\If x > 0 Then
        \\  y = 1;
        \\Else
        \\  y = 0;
        \\EndIf;
    );
    try expectParse(
        \\Если x > 0 Тогда
        \\  y = 1;
        \\Иначе
        \\  y = 0;
        \\КонецЕсли;
    );
    try expectParse(
        \\If x > 10 Then
        \\  y = 3;
        \\ElsIf x > 5 Then
        \\  y = 2;
        \\ElsIf x > 0 Then
        \\  y = 1;
        \\Else
        \\  y = 0;
        \\EndIf;
    );
    try expectParse(
        \\Если x > 10 Тогда
        \\  y = 3;
        \\ИначеЕсли x > 5 Тогда
        \\  y = 2;
        \\ИначеЕсли x > 0 Тогда
        \\  y = 1;
        \\Иначе
        \\  y = 0;
        \\КонецЕсли;
    );
}

test "for loop" {
    std.debug.print("\n-- 1c: for --\n", .{});
    try expectParse(
        \\For i = 0 To 10
        \\  x = x + i;
        \\EndDo;
    );
    try expectParse(
        \\Для i = 0 По 10 Цикл
        \\  x = x + i;
        \\КонецЦикла;
    );
}

test "foreach loop" {
    std.debug.print("\n-- 1c: foreach --\n", .{});
    try expectParse(
        \\ForEach item In collection
        \\  Process(item);
        \\EndDo;
    );
    try expectParse(
        \\Для каждого item В коллекции Цикл
        \\  Process(item);
        \\КонецЦикла;
    );
}

test "while loop" {
    std.debug.print("\n-- 1c: while --\n", .{});
    try expectParse(
        \\While x > 0 Do
        \\  x = x - 1;
        \\EndDo;
    );
    try expectParse(
        \\Пока x > 0 Цикл
        \\  x = x - 1;
        \\КонецЦикла;
    );
}

test "try except" {
    std.debug.print("\n-- 1c: try --\n", .{});
    try expectParse(
        \\Try
        \\  x = Dangerous();
        \\Except
        \\  x = 0;
        \\EndTry;
    );
    try expectParse(
        \\Попытка
        \\  x = Dangerous();
        \\Исключение
        \\  x = 0;
        \\КонецПопытки;
    );
}

test "return continue break" {
    std.debug.print("\n-- 1c: return/continue/break --\n", .{});
    try expectParse("Return;");
    try expectParse("Возврат;");
    try expectParse("Return 42;");
    try expectParse("Возврат 42;");
    try expectParse("Continue;");
    try expectParse("Продолжить;");
    try expectParse("Break;");
    try expectParse("Прервать;");
}

test "goto label" {
    std.debug.print("\n-- 1c: goto --\n", .{});
    try expectParse(
        \\~Start:
        \\x = x + 1;
        \\If x < 10 Then
        \\  Goto ~Start;
        \\EndIf;
    );
    try expectParse(
        \\~Start:
        \\x = x + 1;
        \\Если x < 10 Тогда
        \\  Перейти ~Start;
        \\КонецЕсли;
    );
}

test "raise" {
    std.debug.print("\n-- 1c: raise --\n", .{});
    try expectParse("Raise;");
    try expectParse("ВызватьИсключение;");
    try expectParse("Raise \"Error occurred\";");
    try expectParse("ВызватьИсключение \"Error occurred\";");
}

test "execute" {
    std.debug.print("\n-- 1c: execute --\n", .{});
    try expectParse("Execute(\"x = 1\");");
    try expectParse("Execute(code);");
    try expectParse("Выполнить(\"x = 1\");");
    try expectParse("Выполнить(code);");
}

test "handlers" {
    std.debug.print("\n-- 1c: handlers --\n", .{});
    try expectParse("AddHandler obj.OnChange, handler;");
    try expectParse("ДобавитьОбработчик obj.OnChange, handler;");
    try expectParse("RemoveHandler obj.OnChange, handler;");
    try expectParse("УдалитьОбработчик obj.OnChange, handler;");
}

test "procedure" {
    std.debug.print("\n-- 1c: procedure --\n", .{});
    try expectParse(
        \\Procedure DoWork()
        \\  x = 1;
        \\EndProcedure
    );
    try expectParse(
        \\Procedure Calc(a, b)
        \\  result = a + b;
        \\  Message(result);
        \\EndProcedure
    );

    try expectParse(
        \\Procedure Init(Val x, y = 10)
        \\  z = x + y;
        \\EndProcedure
    );
}

test "procedure export" {
    std.debug.print("\n-- 1c: procedure export --\n", .{});
    try expectParse(
        \\Procedure PublicProc() Export
        \\  Return;
        \\EndProcedure
    );
    try expectParse(
        \\Процедура PublicProc() Экспорт
        \\  Возврат;
        \\КонецПроцедуры
    );
}

test "function" {
    std.debug.print("\n-- 1c: function --\n", .{});
    try expectParse(
        \\Function GetValue()
        \\  Return 42;
        \\EndFunction
    );
    try expectParse(
        \\Function Add(a, b)
        \\  Return a + b;
        \\EndFunction
    );
    try expectParse(
        \\Function Max(a, b) Export
        \\  If a > b Then
        \\    Return a;
        \\  Else
        \\    Return b;
        \\  EndIf;
        \\EndFunction
    );
    try expectParse(
        \\Функция GetValue()
        \\  Возврат 42;
        \\КонецФункции
    );
    try expectParse(
        \\Функция Add(a, b)
        \\  Возврат a + b;
        \\КонецФункции
    );
    try expectParse(
        \\Функция Max(a, b) Экспорт
        \\  Если a > b Тогда    
        \\    Возврат a;
        \\  Иначе
        \\    Возврат b;
        \\  КонецЕсли;
        \\КонецФункции
    );
}

test "comments" {
    std.debug.print("\n-- 1c: comments --\n", .{});
    try expectParse("// this is a comment\nx = 1;");
    try expectParse("x = 1; // inline comment\ny = 2;");
}

test "multiline" {
    std.debug.print("\n-- 1c: multiline --\n", .{});
    try expectParse(
        \\Var total;
        \\total = 0;
        \\For i = 1 To 10
        \\  total = total + i;
        \\EndDo;
        \\Message(total);
    );
}

// --- Русские ключевые слова ---

test "russian keywords" {
    std.debug.print("\n-- 1c: russian --\n", .{});
    try expectParse("\xd0\x9f\xd0\xb5\xd1\x80\xd0\xb5\xd0\xbc \xd1\x85;");
    try expectParse("\xd1\x85 = \xd0\x98\xd1\x81\xd1\x82\xd0\xb8\xd0\xbd\xd0\xb0;");
    try expectParse("\xd1\x85 = \xd0\x9b\xd0\xbe\xd0\xb6\xd1\x8c;");
    try expectParse("\xd1\x85 = \xd0\x9d\xd0\xb5\xd0\xbe\xd0\xbf\xd1\x80\xd0\xb5\xd0\xb4\xd0\xb5\xd0\xbb\xd0\xb5\xd0\xbd\xd0\xbe;");
}

test "russian if" {
    std.debug.print("\n-- 1c: russian if --\n", .{});
    // Если х > 0 Тогда\n  у = х;\nКонецЕсли;
    try expectParse("\xd0\x95\xd1\x81\xd0\xbb\xd0\xb8 \xd1\x85 > 0 \xd0\xa2\xd0\xbe\xd0\xb3\xd0\xb4\xd0\xb0\n  \xd1\x83 = \xd1\x85;\n\xd0\x9a\xd0\xbe\xd0\xbd\xd0\xb5\xd1\x86\xd0\x95\xd1\x81\xd0\xbb\xd0\xb8;");
}

test "russian procedure" {
    std.debug.print("\n-- 1c: russian proc --\n", .{});
    // Процедура Тест()\n  Возврат;\nКонецПроцедуры
    try expectParse("\xd0\x9f\xd1\x80\xd0\xbe\xd1\x86\xd0\xb5\xd0\xb4\xd1\x83\xd1\x80\xd0\xb0 \xd0\xa2\xd0\xb5\xd1\x81\xd1\x82()\n  \xd0\x92\xd0\xbe\xd0\xb7\xd0\xb2\xd1\x80\xd0\xb0\xd1\x82;\n\xd0\x9a\xd0\xbe\xd0\xbd\xd0\xb5\xd1\x86\xd0\x9f\xd1\x80\xd0\xbe\xd1\x86\xd0\xb5\xd0\xb4\xd1\x83\xd1\x80\xd1\x8b");
}

test "complex program" {
    std.debug.print("\n-- 1c: complex --\n", .{});
    try expectParse(
        \\// Complex 1C program
        \\Var result;
        \\
        \\Function Factorial(n)
        \\  If n <= 1 Then
        \\    Return 1;
        \\  EndIf;
        \\  Return n * Factorial(n - 1);
        \\EndFunction
        \\
        \\Procedure ProcessData(data) Export
        \\  Var total;
        \\  total = 0;
        \\  ForEach item In data
        \\    Try
        \\      total = total + item.Value;
        \\    Except
        \\      Continue;
        \\    EndTry;
        \\  EndDo;
        \\  result = total;
        \\EndProcedure
        \\
        \\Function CreateReport(title, Val maxRows = 100) Export
        \\  Var report;
        \\  report = New Structure("Title, Rows", title, New Array);
        \\  For i = 0 To maxRows
        \\    If i > 50 Then
        \\      Break;
        \\    EndIf;
        \\    report.Rows.Add(i);
        \\  EndDo;
        \\  Return report;
        \\EndFunction
    );
    try expectParse(
        \\Процедура ProcessData(data) Экспорт
        \\  Перем total;
        \\  total = 0;
        \\  Для каждого item В data Цикл
        \\    Попытка
        \\      total = total + item.Value;
        \\    Исключение
        \\      Продолжить;
        \\    КонецПопытки;
        \\  КонецЦикла;
        \\  result = total;
        \\КонецПроцедуры
    );
    try expectParse(
        \\Функция CreateReport(title, Val maxRows = 100) Экспорт
        \\  Перем report;
        \\  report = Новый Структура("Title, Rows", title, Новый Массив);
        \\  Для i = 0 По maxRows Цикл
        \\    Если i > 50 Тогда
        \\      Прервать;
        \\    КонецЕсли;
        \\    report.Rows.Add(i);
        \\  КонецЦикла;
        \\  Возврат report;
        \\КонецФункции
    );
}

test "tree structure" {
    std.debug.print("\n-- 1c: tree --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try lang1c.parse(arena.allocator(), "module",
        \\Function Add(a, b)
        \\  Return a + b;
        \\EndFunction
    );
    peg.printTree(result.node, 2);
    try std.testing.expect(countTag(result.node, "function") == 1);
    try std.testing.expect(countTag(result.node, "return_stmt") == 1);
    try std.testing.expect(countTag(result.node, "params") == 1);
    
    std.debug.print("  OK: tree verified\n", .{});
}

test "detailed errors" {
    std.debug.print("\n-- 1c: errors --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const r1 = lang1c.parseDetailed(arena.allocator(), "module", "If x Then\nEndIf");
    switch (r1) {
        .ok => |ok| std.debug.print("  'If without ;' parsed {}/{}\n", .{ ok.pos, 15 }),
        .err => |e| std.debug.print("  error at {}:{}: {s}\n", .{ e.line, e.col, e.expected }),
    }
}