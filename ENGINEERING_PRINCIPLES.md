# Engineering Principles

## Vision

An engine that empowers creativity and never stands in its way.

## Mission

Build a reliable engine that lets developers focus on creating, not
troubleshooting the tools they depend on.

## Purpose of this document

The Untold Editor exists to serve that mission: it is one of the tools
developers depend on when working with the Untold Engine. This document
describes the engineering standards that guide day-to-day decisions in this
repository — what to build, how to build it, and what to check before it
ships. They apply to every contributor, maintainer, and reviewer working on
the editor.

These are working principles, not absolute rules. They exist to make
contributors think carefully about trade-offs, not to block reasonable
engineering judgment. Where a principle and a concrete requirement conflict,
say so explicitly in the PR or design discussion and explain the trade-off
being made.

---

## 1. Reliability comes first

A new feature is not an improvement if it makes the editor less reliable.

Prevent regressions, fix known defects, and maintain existing functionality.
Reliability should be considered throughout development, not just before a
release.

## 2. Test, test, test

Testing is part of development, not an activity performed after
implementation.

New features and bug fixes should include appropriate tests. Contributors
should test expected behavior, edge cases, failure conditions, and
interactions with existing systems.

Never disable or weaken tests simply to make a build pass.

## 3. Fail gracefully and explain what went wrong

The editor should never crash when a failure can be handled safely.

Recoverable failures should produce meaningful diagnostics that explain what
failed, why it failed, and, when possible, how the developer can resolve the
problem.

Use safe defaults or fallback resources when appropriate, but never silently
hide programming defects or leave a project or scene in an invalid state.

## 4. Keep the editor working

The editor should remain buildable, testable, and usable throughout
development.

Contributors are responsible for ensuring that their changes do not break
existing functionality or prevent others from continuing their work.

Major changes should be introduced incrementally when practical.

## 5. Keep the architecture simple

Favor clear, maintainable solutions over unnecessary abstractions and
speculative complexity.

Solve concrete requirements using existing systems whenever appropriate.

New architectural complexity should be justified by a demonstrated need.

## 6. Protect API compatibility

The editor's scene and asset file formats, and any interfaces it exposes,
represent a commitment to developers who depend on them.

Preserve existing formats and interfaces whenever practical. Prefer additive
changes when appropriate, and ensure that necessary breaking changes are
deliberate, documented, and accompanied by migration guidance.

## 7. Build tools that empower developers

The editor exists to reduce friction, improve iteration speed, and help
developers understand and resolve problems when composing scenes and
preparing assets for the Untold Engine.

Developers should spend their time creating, not fighting the tools they
depend on.

## 8. Measure before optimizing

Performance improvements should be guided by profiling, benchmarks, and
measurable evidence.

Evaluate performance gains alongside correctness, memory usage, complexity,
and maintainability.

Avoid introducing instability or unnecessary complexity for unverified
performance improvements.

## 9. Maintain clear ownership and responsibilities

Contributors should understand the systems they modify and how those changes
affect the rest of the editor and the assets/scenes it produces.

Respect established architectural boundaries, coordinate significant changes
with relevant maintainers, and document important technical decisions.

Ownership should establish accountability without preventing collaboration.

## 10. Continuously improve the editor and its development process

Recurring problems should be investigated and addressed at their source.

Improve diagnostics, automate repetitive tasks, simplify workflows, and
revisit architectural decisions when new requirements or evidence justify
doing so.

Every contribution should leave the editor, its tools, or its development
process in a better state.

---

## How these principles apply

- **Feature development** — new systems should be evaluated against
  reliability, simplicity, and compatibility with existing scene/asset
  formats before they're evaluated for scope or polish.
- **Bug fixes** — fix the root cause where practical rather than
  masking the symptom; add a test that would have caught the regression.
- **Testing** — tests are part of the change, not a follow-up task.
- **Architectural changes** — significant changes should be discussed with
  maintainers before implementation, and the trade-offs should be documented
  in the PR.
- **Code review** — reviewers check contributions against these principles
  in addition to correctness and style.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contributor workflow, and the
[Untold Engine's Engineering Principles](https://github.com/untoldengine/UntoldEngine/blob/develop/ENGINEERING_PRINCIPLES.md)
for the engine-side counterpart to this document.
