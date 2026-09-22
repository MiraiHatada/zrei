# copilot review instructions for zrei

## philosophy and architecture

- minimal audio engine / synthesizer in zig, zero external dependencies.
- follow Functional Core, Imperative Shell (FCIS) and Sans I/O.
  - core logic: pure stateful machine. strictly no syscalls, no dynamic allocations, and no I/O.
  - shell: handles OS, files, and formatting.
- `STANDARDS.MD` is the absolute authority. when standard zig advice conflicts with it, `STANDARDS.MD` wins.
- never guess zig syntax or stdlib behaviors from outdated llm memory. trust local std source and actual compiler.

## review priorities

1. correctness and stability
   - oscillator math, phase accumulator wrap-around, timing, and numerical stability.
   - keep `if`/`switch` out of sample loops.

2. memory and stack
   - caller-allocated buffer: audio buffers must be provided by the caller. no allocations inside render loops.
   - pass by value: pass read-only structs by value (`arg: Struct`). use `*Struct` only for mutation. do not suggest `*const Struct` unless required by address identity (`@fieldParentPtr`) or C ABI.
   - 64kb stack: assume 64kb stack limit. no local arrays > 4kb on stack. no recursion.
   - grouped element thinking (`ArenaAllocator`, `FixedBufferAllocator`).

3. error model and lifecycle
   - follow the 3-tier error model:
     - assert programmer bugs and invariant violations only. input validation is not an invariant.
     - return `!T` for unpreventable environment / system failures (I/O, OOM).
     - return algebraic types (`bool`, `enum`, `?T`, `union(enum)`) for expected domain branches.
   - maintain cleanup symmetry: paired `init`/`deinit`, `errdefer` rollbacks on chained resource acquisitions.

4. code style and conventions
   - no leading underscores on struct fields (`_field` is forbidden).
   - abstract reader/writer parameters must be named `source`/`sink`.
   - no top-level namespace imports (e.g. `const time = std.time;` is forbidden). alias types, not namespaces.
   - remove unused `@import`.

5. testing
   - use `std.testing.allocator` to ensure leak-free execution.
   - prefer `expectEqual` for primitives and `expectEqualDeep` / `expectEqualStrings` for slices and compound types.
   - do not abuse `@as` when type coercion is obvious.
   - keep tests deterministic and flat (avoid `if`/`switch` in tests; use direct unwraps or `orelse return error`).
   - prefer in-memory fixed buffers (`fixed` reader/writer) over ad-hoc mocks.

## review behavior

- report actionable findings only.
- explain the exact technical impact and rationale for each finding.
- do not complain about personal style.
- do not invent problems if the code is correct and well-tested.
- consider the full repository context before making a finding.
