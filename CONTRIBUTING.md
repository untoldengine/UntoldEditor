# Contributing to Untold Editor

Thanks for your interest in contributing to the Untold Editor.

Read the [Engineering Principles](ENGINEERING_PRINCIPLES.md) first — they
describe the standards all contributions are expected to follow: reliability,
testing, graceful failure handling, compatibility with existing scene/asset
formats, architectural simplicity, and measured performance work.

## Workflow

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/my-feature`).
3. Make your change, with tests where appropriate.
4. Commit your changes with a clear, descriptive message.
5. Push the branch and open a Pull Request.

The PR template will walk you through a short checklist covering tests,
compatibility, failure handling, and documentation.

## Scope

The Untold Editor is a scene-composition companion to the
[Untold Engine](https://github.com/untoldengine/UntoldEngine) — see the
README's "Editor Scope" section for what is and isn't in scope for this
repository. Changes to engine systems (rendering, physics, scripting, etc.)
belong in the engine repository, not here.

## Code of Conduct

All contributors are expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
