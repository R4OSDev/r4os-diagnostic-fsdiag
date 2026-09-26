# FSDIAG.R4X

`FSDIAG.R4X` is an independent R4OS diagnostic program implemented in Zig.

## Package

- Version: `0.1.11`
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

`FSDIAG E /PAGECACHE` selects an explicitly attached FAT32 test volume E:
for the large-stream/writeback and selective-durability checks. The TEMP
directory must already exist. The pressure fixture needs 512-byte FAT
clusters; larger clusters take the direct write path and do not create its
expected dirty payload pages. The storage-owner check needs a separate block
device whose first mounted letter is E:. Assign the prepared partition
through R4PART after removing its automatically assigned mount letter and
freeing E: in the private test image. The extra disk needs a partition table.
The existing NTFS metadata and cold-read
probes remain on C:. Managed C: and D: are both NTFS; a missing or non-FAT
selection fails before creating the large stream. The normal full diagnostic
still uses its historical D:-FAT fixtures for the other FAT-specific checks.
No physical drive is chosen automatically.
