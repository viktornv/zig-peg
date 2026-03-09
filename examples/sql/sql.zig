const std = @import("std");
const peg = @import("peg");

const sql = peg.compile(
    \\query      <- _ws stmt _ws ';'? _ws
    \\@squashed stmt <- select / insert / update / delete / create / drop
    \\
    \\select     <- 'SELECT'i ![a-zA-Z0-9_] _ws columns
    \\              _ws 'FROM'i ![a-zA-Z0-9_] _ws tables
    \\              (_ws join)*
    \\              (_ws where)?
    \\              (_ws groupby)?
    \\              (_ws having)?
    \\              (_ws orderby)?
    \\              (_ws limit)?
    \\
    \\insert     <- 'INSERT'i ![a-zA-Z0-9_] _ws 'INTO'i ![a-zA-Z0-9_] _ws table
    \\              _ws '(' _ws collist _ws ')'
    \\              _ws 'VALUES'i ![a-zA-Z0-9_] _ws '(' _ws vallist _ws ')'
    \\
    \\update     <- 'UPDATE'i ![a-zA-Z0-9_] _ws table
    \\              _ws 'SET'i ![a-zA-Z0-9_] _ws setlist
    \\              (_ws where)?
    \\
    \\delete     <- 'DELETE'i ![a-zA-Z0-9_]
    \\              _ws 'FROM'i ![a-zA-Z0-9_] _ws table
    \\              (_ws where)?
    \\
    \\create     <- 'CREATE'i ![a-zA-Z0-9_] _ws 'TABLE'i ![a-zA-Z0-9_] _ws table
    \\              _ws '(' _ws coldefs _ws ')'
    \\
    \\drop       <- 'DROP'i ![a-zA-Z0-9_] _ws 'TABLE'i ![a-zA-Z0-9_] _ws table
    \\
    \\@squashed columns <- '*' / exprlist
    \\@squashed exprlist <- expr_alias (_ws ',' _ws expr_alias)*
    \\expr_alias <- expr (_ws 'AS'i ![a-zA-Z0-9_] _ws alias)?
    \\alias      <- _ident
    \\
    \\@squashed tables <- table_alias (_ws ',' _ws table_alias)*
    \\table_alias <- table _ws 'AS'i ![a-zA-Z0-9_] _ws alias
    \\             / table _ws !_keyword alias
    \\             / table
    \\table      <- _ident ('.' _ident)?
    \\
    \\join       <- jointype _ws 'JOIN'i ![a-zA-Z0-9_] _ws table_alias _ws 'ON'i ![a-zA-Z0-9_] _ws condition
    \\@squashed jointype <- 'LEFT'i ![a-zA-Z0-9_] (_ws 'OUTER'i ![a-zA-Z0-9_])? / 'RIGHT'i ![a-zA-Z0-9_] (_ws 'OUTER'i ![a-zA-Z0-9_])? / 'INNER'i ![a-zA-Z0-9_] / 'CROSS'i ![a-zA-Z0-9_] / ''
    \\
    \\where      <- 'WHERE'i ![a-zA-Z0-9_] _ws condition
    \\groupby    <- 'GROUP'i ![a-zA-Z0-9_] _ws 'BY'i ![a-zA-Z0-9_] _ws exprlist
    \\having     <- 'HAVING'i ![a-zA-Z0-9_] _ws condition
    \\orderby    <- 'ORDER'i ![a-zA-Z0-9_] _ws 'BY'i ![a-zA-Z0-9_] _ws ordlist
    \\@squashed ordlist <- orditem (_ws ',' _ws orditem)*
    \\orditem    <- expr (_ws ('ASC'i / 'DESC'i) ![a-zA-Z0-9_])?
    \\limit      <- 'LIMIT'i ![a-zA-Z0-9_] _ws _number (_ws 'OFFSET'i ![a-zA-Z0-9_] _ws _number)?
    \\
    \\@squashed setlist <- setitem (_ws ',' _ws setitem)*
    \\setitem    <- column _ws '=' _ws expr
    \\
    \\@squashed collist <- column (_ws ',' _ws column)*
    \\@squashed vallist <- expr (_ws ',' _ws expr)*
    \\
    \\@squashed coldefs <- coldef (_ws ',' _ws coldef)*
    \\coldef     <- column _ws coltype (_ws constraint)*
    \\coltype    <- 'INT'i ![a-zA-Z0-9_]
    \\             / 'INTEGER'i ![a-zA-Z0-9_]
    \\             / 'TEXT'i ![a-zA-Z0-9_]
    \\             / 'VARCHAR'i ![a-zA-Z0-9_] '(' _number ')'
    \\             / 'BOOLEAN'i ![a-zA-Z0-9_]
    \\             / 'FLOAT'i ![a-zA-Z0-9_]
    \\             / 'DATE'i ![a-zA-Z0-9_]
    \\             / 'TIMESTAMP'i ![a-zA-Z0-9_]
    \\constraint <- 'PRIMARY'i ![a-zA-Z0-9_] _ws 'KEY'i ![a-zA-Z0-9_]
    \\             / 'NOT'i ![a-zA-Z0-9_] _ws 'NULL'i ![a-zA-Z0-9_]
    \\             / 'UNIQUE'i ![a-zA-Z0-9_]
    \\             / 'DEFAULT'i ![a-zA-Z0-9_] _ws expr
    \\
    \\@squashed condition <- logic_or
    \\logic_or   <- logic_and (_ws 'OR'i ![a-zA-Z0-9_] _ws logic_and)*
    \\logic_and  <- logic_not (_ws 'AND'i ![a-zA-Z0-9_] _ws logic_not)*
    \\logic_not  <- 'NOT'i ![a-zA-Z0-9_] _ws logic_not / comparison / '(' _ws condition _ws ')'
    \\comparison <- expr _ws cmp_op _ws expr
    \\           /  expr _ws 'IN'i ![a-zA-Z0-9_] _ws '(' _ws vallist _ws ')'
    \\           /  expr _ws 'BETWEEN'i ![a-zA-Z0-9_] _ws expr _ws 'AND'i ![a-zA-Z0-9_] _ws expr
    \\           /  expr _ws 'LIKE'i ![a-zA-Z0-9_] _ws expr
    \\           /  expr _ws 'IS'i ![a-zA-Z0-9_] _ws 'NOT'i ![a-zA-Z0-9_] _ws 'NULL'i ![a-zA-Z0-9_]
    \\           /  expr _ws 'IS'i ![a-zA-Z0-9_] _ws 'NULL'i ![a-zA-Z0-9_]
    \\@squashed cmp_op <- '<=' / '>=' / '<>' / '!=' / '<' / '>' / '='
    \\
    \\@squashed expr <- func / column / value / '(' _ws expr _ws ')'
    \\func       <- _ident _ws '(' _ws funcargs _ws ')'
    \\@squashed funcargs <- '*' / exprlist / ''
    \\column     <- _ident (_ws '.' _ws _ident)?
    \\value      <- string / number / null / bool
    \\string     <- '\'' [^']* '\''
    \\number     <- '-'? _number ('.' _number)?
    \\null       <- 'NULL'i ![a-zA-Z0-9_]
    \\bool       <- 'TRUE'i ![a-zA-Z0-9_] / 'FALSE'i ![a-zA-Z0-9_]
    \\
    \\@silent _keyword   <- ('SELECT'i / 'FROM'i / 'WHERE'i / 'JOIN'i / 'INNER'i / 'LEFT'i / 'RIGHT'i / 'CROSS'i / 'OUTER'i / 'ON'i / 'ORDER'i / 'GROUP'i / 'HAVING'i / 'LIMIT'i / 'OFFSET'i / 'SET'i / 'VALUES'i / 'INTO'i / 'AND'i / 'OR'i / 'NOT'i / 'AS'i / 'ASC'i / 'DESC'i / 'IN'i / 'BETWEEN'i / 'LIKE'i / 'IS'i / 'NULL'i / 'TRUE'i / 'FALSE'i / 'INSERT'i / 'UPDATE'i / 'DELETE'i / 'CREATE'i / 'DROP'i / 'TABLE'i / 'PRIMARY'i / 'KEY'i / 'UNIQUE'i / 'DEFAULT'i) ![a-zA-Z0-9_]
    \\@silent _ident     <- !_keyword [a-zA-Z_] [a-zA-Z0-9_]*
    \\@silent _number    <- [0-9]+
    \\@silent _ws        <- [ \t\n\r]*
);

// --- Helpers ---

fn expectParse(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try sql.parse(arena.allocator(), "query", input);
    if (result.pos != input.len) {
        std.debug.print("  FAIL: parsed {}/{} of \"{s}\"\n", .{ result.pos, input.len, input[0..@min(input.len, 60)] });
        return error.TestUnexpectedResult;
    }
    std.debug.print("  OK: {s}\n", .{input[0..@min(input.len, 60)]});
}

fn expectFail(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    if (sql.parse(arena.allocator(), "query", input)) |r| {
        if (r.pos == input.len) return error.ShouldHaveFailed;
        std.debug.print("  PARTIAL (ok): \"{s}\"\n", .{input[0..@min(input.len, 40)]});
    } else |_| {
        std.debug.print("  REJECTED (ok): \"{s}\"\n", .{input[0..@min(input.len, 40)]});
    }
}

fn countTag(node: peg.Node, tag: []const u8) usize {
    var c: usize = 0;
    if (std.mem.eql(u8, node.tag, tag)) c += 1;
    for (node.children) |child| c += countTag(child, tag);
    return c;
}

fn findTag(node: peg.Node, tag: []const u8) ?peg.Node {
    if (std.mem.eql(u8, node.tag, tag)) return node;
    for (node.children) |child| {
        if (findTag(child, tag)) |found| return found;
    }
    return null;
}

// ===================== TESTS =====================

// --- SELECT ---

test "select simple" {
    std.debug.print("\n-- sql: select simple --\n", .{});
    try expectParse("SELECT * FROM users");
    try expectParse("SELECT name FROM users");
    try expectParse("SELECT name, age FROM users");
    try expectParse("SELECT id, name, email FROM users");
}

test "select case insensitive" {
    std.debug.print("\n-- sql: select case --\n", .{});
    try expectParse("select * from users");
    try expectParse("Select name From users");
    try expectParse("sElEcT * fRoM users");
}

test "select where" {
    std.debug.print("\n-- sql: select where --\n", .{});
    try expectParse("SELECT * FROM users WHERE id = 1");
    try expectParse("SELECT * FROM users WHERE name = 'Alice'");
    try expectParse("SELECT * FROM users WHERE age > 18");
    try expectParse("SELECT * FROM users WHERE age >= 18 AND active = TRUE");
    try expectParse("SELECT * FROM users WHERE age < 30 OR name = 'Bob'");
    try expectParse("SELECT * FROM users WHERE NOT active = FALSE");
}

test "select comparison ops" {
    std.debug.print("\n-- sql: select cmp ops --\n", .{});
    try expectParse("SELECT * FROM t WHERE a = 1");
    try expectParse("SELECT * FROM t WHERE a < 1");
    try expectParse("SELECT * FROM t WHERE a > 1");
    try expectParse("SELECT * FROM t WHERE a <= 1");
    try expectParse("SELECT * FROM t WHERE a >= 1");
    try expectParse("SELECT * FROM t WHERE a <> 1");
    try expectParse("SELECT * FROM t WHERE a != 1");
}

test "select in between like" {
    std.debug.print("\n-- sql: select in/between/like --\n", .{});
    try expectParse("SELECT * FROM users WHERE id IN (1, 2, 3)");
    try expectParse("SELECT * FROM users WHERE age BETWEEN 18 AND 65");
    try expectParse("SELECT * FROM users WHERE name LIKE '%alice%'");
}

test "select is null" {
    std.debug.print("\n-- sql: select is null --\n", .{});
    try expectParse("SELECT * FROM users WHERE email IS NULL");
    try expectParse("SELECT * FROM users WHERE email IS NOT NULL");
}

test "select qualified columns" {
    std.debug.print("\n-- sql: qualified columns --\n", .{});
    try expectParse("SELECT users.name FROM users");
    try expectParse("SELECT u.name, u.email FROM users");
    try expectParse("SELECT * FROM users WHERE users.id = 1");
}

test "select alias explicit" {
    std.debug.print("\n-- sql: select alias AS --\n", .{});
    try expectParse("SELECT name AS n FROM users");
    try expectParse("SELECT name AS n, age AS a FROM users");
    try expectParse("SELECT * FROM users AS u");
    try expectParse("SELECT COUNT(*) AS total FROM users");
}

test "select alias implicit" {
    std.debug.print("\n-- sql: select alias implicit --\n", .{});
    try expectParse("SELECT u.name FROM users u");
    try expectParse("SELECT * FROM users u WHERE u.id = 1");
    try expectParse("SELECT u.name, o.total FROM users u, orders o");
}

test "select order by" {
    std.debug.print("\n-- sql: order by --\n", .{});
    try expectParse("SELECT * FROM users ORDER BY name");
    try expectParse("SELECT * FROM users ORDER BY name ASC");
    try expectParse("SELECT * FROM users ORDER BY age DESC");
    try expectParse("SELECT * FROM users ORDER BY name ASC, age DESC");
}

test "select limit" {
    std.debug.print("\n-- sql: limit --\n", .{});
    try expectParse("SELECT * FROM users LIMIT 10");
    try expectParse("SELECT * FROM users LIMIT 10 OFFSET 20");
    try expectParse("SELECT * FROM users ORDER BY id LIMIT 5");
}

test "select group by having" {
    std.debug.print("\n-- sql: group by --\n", .{});
    try expectParse("SELECT city, COUNT(*) FROM users GROUP BY city");
    try expectParse("SELECT city, COUNT(*) FROM users GROUP BY city HAVING COUNT(*) > 5");
}

test "select functions" {
    std.debug.print("\n-- sql: functions --\n", .{});
    try expectParse("SELECT COUNT(*) FROM users");
    try expectParse("SELECT MAX(age) FROM users");
    try expectParse("SELECT MIN(age), AVG(age) FROM users");
    try expectParse("SELECT SUM(amount) FROM orders");
    try expectParse("SELECT UPPER(name) FROM users");
}

test "select join" {
    std.debug.print("\n-- sql: join --\n", .{});
    try expectParse("SELECT * FROM users JOIN orders ON users.id = orders.user_id");
    try expectParse("SELECT * FROM users INNER JOIN orders ON users.id = orders.user_id");
    try expectParse("SELECT * FROM users LEFT JOIN orders ON users.id = orders.user_id");
    try expectParse("SELECT * FROM users LEFT OUTER JOIN orders ON users.id = orders.user_id");
    try expectParse("SELECT * FROM users RIGHT JOIN orders ON users.id = orders.user_id");
    try expectParse("SELECT * FROM users CROSS JOIN orders ON users.id = orders.user_id");
}

test "select join with alias" {
    std.debug.print("\n-- sql: join alias --\n", .{});
    try expectParse("SELECT * FROM users u JOIN orders o ON u.id = o.user_id");
    try expectParse("SELECT * FROM users AS u LEFT JOIN orders AS o ON u.id = o.user_id");
    try expectParse("SELECT u.name, o.total FROM users u INNER JOIN orders o ON u.id = o.user_id");
}

test "select multiple tables" {
    std.debug.print("\n-- sql: multi table --\n", .{});
    try expectParse("SELECT * FROM users, orders");
    try expectParse("SELECT * FROM users u, orders o");
    try expectParse("SELECT u.name, o.total FROM users AS u, orders AS o");
}

test "select complex" {
    std.debug.print("\n-- sql: complex select --\n", .{});
    try expectParse(
        \\SELECT u.name, COUNT(o.id) AS order_count
        \\FROM users u
        \\LEFT JOIN orders o ON u.id = o.user_id
        \\WHERE u.active = TRUE
        \\GROUP BY u.name
        \\HAVING COUNT(o.id) > 0
        \\ORDER BY order_count DESC
        \\LIMIT 10
    );
}

test "select all clauses" {
    std.debug.print("\n-- sql: all clauses --\n", .{});
    try expectParse(
        \\SELECT u.name, u.email, COUNT(o.id) AS cnt
        \\FROM users AS u
        \\INNER JOIN orders AS o ON u.id = o.user_id
        \\WHERE u.active = TRUE AND o.total > 100
        \\GROUP BY u.name, u.email
        \\HAVING COUNT(o.id) >= 3
        \\ORDER BY cnt DESC, u.name ASC
        \\LIMIT 20 OFFSET 10
    );
}

// --- INSERT ---

test "insert" {
    std.debug.print("\n-- sql: insert --\n", .{});
    try expectParse("INSERT INTO users (name) VALUES ('Alice')");
    try expectParse("INSERT INTO users (name, age) VALUES ('Bob', 30)");
    try expectParse("INSERT INTO users (name, age, active) VALUES ('Eve', 25, TRUE)");
    try expectParse("INSERT INTO users (email) VALUES (NULL)");
}

test "insert case insensitive" {
    std.debug.print("\n-- sql: insert case --\n", .{});
    try expectParse("insert into users (name) values ('Alice')");
    try expectParse("Insert Into users (name) Values ('Bob')");
}

// --- UPDATE ---

test "update" {
    std.debug.print("\n-- sql: update --\n", .{});
    try expectParse("UPDATE users SET name = 'Alice'");
    try expectParse("UPDATE users SET name = 'Bob', age = 31");
    try expectParse("UPDATE users SET active = FALSE WHERE id = 1");
    try expectParse("UPDATE users SET age = 26 WHERE name = 'Eve' AND active = TRUE");
}

// --- DELETE ---

test "delete" {
    std.debug.print("\n-- sql: delete --\n", .{});
    try expectParse("DELETE FROM users");
    try expectParse("DELETE FROM users WHERE id = 1");
    try expectParse("DELETE FROM users WHERE active = FALSE AND age < 18");
}

// --- CREATE TABLE ---

test "create table" {
    std.debug.print("\n-- sql: create table --\n", .{});
    try expectParse("CREATE TABLE users (id INT)");
    try expectParse("CREATE TABLE users (id INT, name TEXT)");
    try expectParse("CREATE TABLE users (id INTEGER PRIMARY KEY, name VARCHAR(255) NOT NULL, email TEXT UNIQUE)");
    try expectParse("CREATE TABLE orders (id INT PRIMARY KEY, amount FLOAT, created DATE)");
}

test "create table constraints" {
    std.debug.print("\n-- sql: create constraints --\n", .{});
    try expectParse("CREATE TABLE t (id INT PRIMARY KEY)");
    try expectParse("CREATE TABLE t (name TEXT NOT NULL)");
    try expectParse("CREATE TABLE t (email TEXT UNIQUE)");
    try expectParse("CREATE TABLE t (active BOOLEAN DEFAULT TRUE)");
    try expectParse("CREATE TABLE t (id INT PRIMARY KEY NOT NULL)");
}

// --- DROP TABLE ---

test "drop table" {
    std.debug.print("\n-- sql: drop table --\n", .{});
    try expectParse("DROP TABLE users");
    try expectParse("drop table orders");
}

// --- VALUES ---

test "value types" {
    std.debug.print("\n-- sql: value types --\n", .{});
    try expectParse("SELECT * FROM t WHERE a = 42");
    try expectParse("SELECT * FROM t WHERE a = -7");
    try expectParse("SELECT * FROM t WHERE a = 3.14");
    try expectParse("SELECT * FROM t WHERE a = 'hello'");
    try expectParse("SELECT * FROM t WHERE a = TRUE");
    try expectParse("SELECT * FROM t WHERE a = FALSE");
    try expectParse("SELECT * FROM t WHERE a IS NULL");
}

// --- WHITESPACE ---

test "whitespace" {
    std.debug.print("\n-- sql: whitespace --\n", .{});
    try expectParse("SELECT * FROM users");
    try expectParse("  SELECT  *  FROM  users  ");
    try expectParse("SELECT\n*\nFROM\nusers");
    try expectParse("SELECT\t*\tFROM\tusers");
    try expectParse(
        \\SELECT
        \\  name,
        \\  age
        \\FROM
        \\  users
        \\WHERE
        \\  age > 18
    );
}

// --- SEMICOLONS ---

test "semicolons" {
    std.debug.print("\n-- sql: semicolons --\n", .{});
    try expectParse("SELECT * FROM users;");
    try expectParse("SELECT * FROM users ;");
    try expectParse("INSERT INTO users (name) VALUES ('Alice');");
    try expectParse("DELETE FROM users WHERE id = 1;");
}

// --- TREE ---

test "tree select" {
    std.debug.print("\n-- sql: tree select --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try sql.parse(arena.allocator(), "query",
        \\SELECT u.name, COUNT(o.id) AS cnt
        \\FROM users u
        \\JOIN orders o ON u.id = o.user_id
        \\WHERE u.active = TRUE
        \\ORDER BY cnt DESC
        \\LIMIT 10
    );
    peg.printTree(result.node, 2);

    try std.testing.expect(countTag(result.node, "select") == 1);
    try std.testing.expect(countTag(result.node, "join") >= 1);
    try std.testing.expect(countTag(result.node, "where") == 1);
    try std.testing.expect(countTag(result.node, "orderby") == 1);
    try std.testing.expect(countTag(result.node, "limit") == 1);
    try std.testing.expect(countTag(result.node, "alias") >= 1);
    try std.testing.expect(countTag(result.node, "func") >= 1);
    std.debug.print("  OK: select tree verified\n", .{});
}

test "tree insert" {
    std.debug.print("\n-- sql: tree insert --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try sql.parse(arena.allocator(), "query",
        "INSERT INTO users (name, age) VALUES ('Alice', 30)"
    );
    peg.printTree(result.node, 2);
    try std.testing.expect(countTag(result.node, "insert") == 1);
    try std.testing.expect(countTag(result.node, "column") == 2);
    try std.testing.expect(countTag(result.node, "value") >= 2);
    std.debug.print("  OK: insert tree\n", .{});
}

test "tree create" {
    std.debug.print("\n-- sql: tree create --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try sql.parse(arena.allocator(), "query",
        "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(255) NOT NULL)"
    );
    peg.printTree(result.node, 2);
    try std.testing.expect(countTag(result.node, "create") == 1);
    try std.testing.expect(countTag(result.node, "coldef") == 2);
    try std.testing.expect(countTag(result.node, "coltype") == 2);
    try std.testing.expect(countTag(result.node, "constraint") >= 2);
    std.debug.print("  OK: create tree\n", .{});
}

// --- WALKER / ANALYSIS ---

const QueryInfo = struct {
    stmt_type: []const u8,
    table_count: usize,
    column_count: usize,
    has_where: bool,
    has_join: bool,
    has_orderby: bool,
    has_limit: bool,
    has_groupby: bool,
};

fn analyzeQuery(input: []const u8) !QueryInfo {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try sql.parse(arena.allocator(), "query", input);
    const node = result.node;

    const stmt_type: []const u8 = if (findTag(node, "select") != null) "SELECT"
        else if (findTag(node, "insert") != null) "INSERT"
        else if (findTag(node, "update") != null) "UPDATE"
        else if (findTag(node, "delete") != null) "DELETE"
        else if (findTag(node, "create") != null) "CREATE"
        else if (findTag(node, "drop") != null) "DROP"
        else "UNKNOWN";

    return .{
        .stmt_type = stmt_type,
        .table_count = countTag(node, "table"),
        .column_count = countTag(node, "column"),
        .has_where = countTag(node, "where") > 0,
        .has_join = countTag(node, "join") > 0,
        .has_orderby = countTag(node, "orderby") > 0,
        .has_limit = countTag(node, "limit") > 0,
        .has_groupby = countTag(node, "groupby") > 0,
    };
}

test "query analysis" {
    std.debug.print("\n-- sql: query analysis --\n", .{});

    const q1 = try analyzeQuery("SELECT name, age FROM users WHERE active = TRUE ORDER BY name LIMIT 10");
    std.debug.print("  {s}: tables={}, cols={}, where={}, order={}, limit={}\n", .{
        q1.stmt_type, q1.table_count, q1.column_count, q1.has_where, q1.has_orderby, q1.has_limit,
    });
    try std.testing.expectEqualStrings("SELECT", q1.stmt_type);
    try std.testing.expect(q1.has_where);
    try std.testing.expect(q1.has_orderby);
    try std.testing.expect(q1.has_limit);

    const q2 = try analyzeQuery("INSERT INTO users (name, age) VALUES ('Alice', 30)");
    std.debug.print("  {s}: cols={}\n", .{ q2.stmt_type, q2.column_count });
    try std.testing.expectEqualStrings("INSERT", q2.stmt_type);

    const q3 = try analyzeQuery("UPDATE users SET name = 'Bob' WHERE id = 1");
    std.debug.print("  {s}: where={}\n", .{ q3.stmt_type, q3.has_where });
    try std.testing.expectEqualStrings("UPDATE", q3.stmt_type);
    try std.testing.expect(q3.has_where);

    const q4 = try analyzeQuery("DELETE FROM users WHERE id = 1");
    std.debug.print("  {s}: where={}\n", .{ q4.stmt_type, q4.has_where });
    try std.testing.expectEqualStrings("DELETE", q4.stmt_type);

    const q5 = try analyzeQuery(
        \\SELECT u.name FROM users u
        \\LEFT JOIN orders o ON u.id = o.user_id
        \\GROUP BY u.name
    );
    std.debug.print("  {s}: join={}, groupby={}\n", .{ q5.stmt_type, q5.has_join, q5.has_groupby });
    try std.testing.expect(q5.has_join);
    try std.testing.expect(q5.has_groupby);

    const q6 = try analyzeQuery("CREATE TABLE users (id INT PRIMARY KEY, name TEXT NOT NULL)");
    std.debug.print("  {s}: tables={}\n", .{ q6.stmt_type, q6.table_count });
    try std.testing.expectEqualStrings("CREATE", q6.stmt_type);

    const q7 = try analyzeQuery("DROP TABLE users");
    std.debug.print("  {s}\n", .{q7.stmt_type});
    try std.testing.expectEqualStrings("DROP", q7.stmt_type);

    std.debug.print("  OK: all analyses passed\n", .{});
}

// --- DETAILED ERRORS ---

test "detailed errors" {
    std.debug.print("\n-- sql: detailed errors --\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const r1 = sql.parseDetailed(arena.allocator(), "query", "SELECT FROM users");
    switch (r1) {
        .ok => |ok| std.debug.print("  'SELECT FROM' partial, pos={}\n", .{ok.pos}),
        .err => |e| std.debug.print("  'SELECT FROM' error at {}:{}: {s}\n", .{ e.line, e.col, e.expected }),
    }

    const r2 = sql.parseDetailed(arena.allocator(), "query", "INSERT users");
    switch (r2) {
        .ok => |ok| std.debug.print("  'INSERT users' partial, pos={}\n", .{ok.pos}),
        .err => |e| std.debug.print("  'INSERT users' error at {}:{}: {s}\n", .{ e.line, e.col, e.expected }),
    }

    const r3 = sql.parseDetailed(arena.allocator(), "query", "SELECT * WHERE id = 1");
    switch (r3) {
        .ok => |ok| std.debug.print("  'SELECT * WHERE' partial, pos={}\n", .{ok.pos}),
        .err => |e| std.debug.print("  'SELECT * WHERE' error at {}:{}: {s}\n", .{ e.line, e.col, e.expected }),
    }
}

// --- INVALID ---

test "invalid queries" {
    std.debug.print("\n-- sql: invalid --\n", .{});
    try expectFail("");
    try expectFail("SELECT");
    try expectFail("FROM users");
    try expectFail("INSERT users");
    try expectFail("UPDATE");
    try expectFail("DELETE users");
}