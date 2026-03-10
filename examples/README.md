# Examples Index

Examples are grouped by domain and mapped to dedicated test commands.

## Data Formats

- `json/json.zig` - JSON values, arrays, objects, escapes (`zig build test-json`)
- `ini/ini.zig` - INI sections, pairs, comments (`zig build test-ini`)
- `csv/csv.zig` - CSV records with quoted and multiline fields (`zig build test-csv`)
- `toml/toml.zig` - TOML tables, dotted keys, arrays (`zig build test-toml`)
- `yaml/yaml.zig` - YAML subset for docker-compose-like files (`zig build test-yaml`)
- `xml/xml.zig` - XML practical syntax (`zig build test-xml`)
- `uri/uri.zig` - URI grammar subset (`zig build test-uri`)
- `markdown/markdown.zig` - markdown-oriented parsing sample (`zig build test-md`)

## Languages

- `basic/basic.zig` - BASIC-like statements and expressions (`zig build test-basic`)
- `sql/sql.zig` - SQL subset with statements and clauses (`zig build test-sql`)
- `css/css.zig` - CSS selectors and rule syntax sample (`zig build test-css`)
- `ruby/ruby.zig` - Ruby subset with control-flow and expressions (`zig build test-ruby`)
- `smalltalk/smalltalk.zig` - Smalltalk subset grammar (`zig build test-smalltalk`)
- `component_pascal/component_pascal.zig` - Component Pascal subset (`zig build test-component-pascal`)
- `lang1c/lang1c.zig` - 1C language subset grammar (`zig build test-1c`)
- `lisp/lisp.zig` - Lisp S-expressions and evaluation-style tree usage (`zig build test-lisp`)
- `python_expr/python_expr.zig` - Python-like expressions with left-recursive form (`zig build test-python-expr`)

## Protocols / APIs

- `graphql/graphql.zig` - GraphQL document parsing (`zig build test-graphql`)
- `graphql_strict/graphql_strict.zig` - GraphQL with stricter semantic profile (`zig build test-graphql-strict`)
- `http/http.zig` - HTTP message parsing (`zig build test-http`)
- `http_strict/http_strict.zig` - HTTP with stricter semantic profile (`zig build test-http-strict`)

## Run Everything

- All suites: `zig build test`
- Core engine tests only: `zig build test-main`

## Example Test Minimum

For each `examples/*/*.zig`, keep at least this minimum:

- Happy-path parse tests for the main grammar constructs.
- Invalid input tests (`expectFail`/error checks), not just successful parses.
- At least one tree/structure assertion (`countTag`/`expectEqual*`) to verify AST shape.
- Detailed error coverage (`parseDetailed`) for grammars where diagnostics matter.
