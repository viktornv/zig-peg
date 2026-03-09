const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const peg_mod = b.addModule("peg", .{
        .root_source_file = b.path("src/peg.zig"),
    });

    const bench_exe = b.addExecutable(.{
        .name = "peg-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "peg", .module = peg_mod },
            },
        }),
    });
    const run_bench = b.addRunArtifact(bench_exe);
    if (b.args) |args| {
        run_bench.addArgs(args);
    }
    const bench_step = b.step("bench", "Run PEG microbenchmarks");
    bench_step.dependOn(&run_bench.step);

    const test_step = b.step("test", "Run all tests");

    const test_files = [_]struct { path: []const u8, name: []const u8 }{
        .{ .path = "src/main.zig", .name = "test-main" },
        .{ .path = "examples/json/json.zig", .name = "test-json" },
        .{ .path = "examples/ini/ini.zig", .name = "test-ini" },
        .{ .path = "examples/lisp/lisp.zig", .name = "test-lisp" },
        .{ .path = "examples/uri/uri.zig", .name = "test-uri" },
        .{ .path = "examples/markdown/markdown.zig", .name = "test-md" },
        .{ .path = "examples/csv/csv.zig", .name = "test-csv" },
        .{ .path = "examples/toml/toml.zig", .name = "test-toml" },
        .{ .path = "examples/ruby/ruby.zig", .name = "test-ruby" },
        .{ .path = "examples/yaml/yaml.zig", .name = "test-yaml" },
        .{ .path = "examples/xml/xml.zig", .name = "test-xml" },
        .{ .path = "examples/graphql/graphql.zig", .name = "test-graphql" },
        .{ .path = "examples/http/http.zig", .name = "test-http" },
        .{ .path = "examples/graphql_strict/graphql_strict.zig", .name = "test-graphql-strict" },
        .{ .path = "examples/http_strict/http_strict.zig", .name = "test-http-strict" },
        .{ .path = "examples/component_pascal/component_pascal.zig", .name = "test-component-pascal" },
        .{ .path = "examples/css/css.zig", .name = "test-css" },
        .{ .path = "examples/basic/basic.zig", .name = "test-basic" },
        .{ .path = "examples/sql/sql.zig", .name = "test-sql" },
        .{ .path = "examples/lang1c/lang1c.zig", .name = "test-1c" },
        .{ .path = "examples/smalltalk/smalltalk.zig", .name = "test-smalltalk" },
        .{ .path = "examples/python_expr/python_expr.zig", .name = "test-python-expr" },
    };

    for (test_files) |tf| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(tf.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "peg", .module = peg_mod },
                },
            }),
        });

        const run = b.addRunArtifact(t);
        test_step.dependOn(&run.step);

        const individual_step = b.step(tf.name, tf.name);
        individual_step.dependOn(&run.step);
    }
}