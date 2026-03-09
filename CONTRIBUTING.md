# Contributing

Thanks for contributing to this PEG library.

## Local Setup

- Zig 0.15.1 (matches current CI setup)
- Clone repository and run commands from project root

## Test Commands

- Core engine tests: `zig build test-main`
- Full test suite: `zig build test`
- Single example suite: `zig build test-<name>` (see `build.zig` and `examples/README.md`)
- Benchmarks: `zig build bench`

Suggested pre-PR sequence:

1. `zig build test-main`
2. One or more relevant `zig build test-...` suites for changed grammars/examples
3. `zig build test` when environment resources allow

## Documentation

- Keep `Readme.md` compact and index-like.
- Place detailed guides in `docs/`.
- Update links when files are renamed or moved.

## Grammar and API Expectations

- Keep grammar behavior explicit (`_ws`, `@silent`, parse options).
- Avoid hidden behavior or implicit parser rules.
- Do not change public API contracts without updating docs and tests together.

## Pull Request Guidelines

- Keep changes scoped and focused.
- Include/adjust tests for behavior changes.
- Update relevant docs for user-visible behavior.
- Prefer clear, neutral wording in documentation.
- If behavior is breaking, include migration notes in the PR description.
- Follow `.github/PULL_REQUEST_TEMPLATE.md` for summary, tests, and impact reporting.
