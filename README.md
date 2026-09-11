# FSDIAG.R4X

`FSDIAG.R4X` is an independent R4OS diagnostic program implemented in Zig.

## Package

- Version: `0.1.10`
- Image target: `/R4OS/SOFTWARE/TERMINAL/DIAG/FSDIAG.R4X`
- Image scope: `test`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

## Build

On Windows:

    Build.bat

On Linux or macOS:

    ./Build.sh

The build starters resolve the current local R4OS dependency checkouts through
`Settings.R4S`. The URL and hash entries in `build.zig.zon` record the
last verified standalone dependency identities; workspace builds use the
mapped local checkouts.

## Documentation

Detailed German technical notes from the migration are preserved in
`DOCUMENTATION.de.txt`. Source-transfer provenance is recorded in
`PROVENANCE.txt`.

`FSDIAG /FATDIR` explicitly checks directory growth on the internal boot FAT.
It requires an absent `\boot\FGROW079` directory, fills its first cluster,
performs an atomic replacement needing a new backup entry, then creates and
enumerates a maximum-length name across cluster boundaries. It verifies
both FAT mirrors, neighboring contents and complete directory reclamation.
Existing fixtures are never reused; a failed probe keeps its directory for
inspection. This mode is separate from the normal diagnostic and needs no
large files or long performance run.

## License

Original R4OS material is licensed under Apache License 2.0. See `LICENSE`
and `NOTICE`. Any repository-specific external material is documented in
`THIRD_PARTY_NOTICES.md`.
