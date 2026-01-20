# Changelog

All notable changes to deltaview.nvim will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Because lua is not compiled for a release, I am just choosing a number and specifying which commit I am describing.

## [Unreleased]

### Added

### Changed

### Fixed

## [0.1.0] - 2025-01-11

### Added
commit - 8a7bf251b420f1c75158a6c66a145ee26fbdccea

- Initial release of deltaview.nvim - 
- Inline diff viewing using git-delta for syntax highlighting
- `:DeltaView` command to view diff of current file against any git ref
- `:DeltaMenu` command to open file picker for modified files
- Cursor position synchronization between source and diff buffers
- Interactive file picker with smart sorting and navigation
- Custom UI with visual hunk ui and hunk navigation
- FZF integration for fuzzy finding with large changesets
- Help documentation (`:help deltaview`)

### Fixes

- Nil filepath validation - 587052f2f7f9229452ceb38f52f7e5d46523df41
- Line count parsing - fbc4303db0b65ac597c45c3a5f09c8f93393a6db
