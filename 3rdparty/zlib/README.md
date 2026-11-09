# Bundled zlib

The application links `libz.a` in this directory, built from the unmodified
upstream source in `zlib-1.4/`. Both Debug and Release use these matching headers.
The static library contains arm64 and x86_64 code targeting macOS 14.6.

Upstream release: https://github.com/madler/zlib/releases/tag/v1.4
Source archive: https://github.com/madler/zlib/releases/download/v1.4/zlib-1.4.tar.gz
SHA-256: `02dd159783677a749c04adbdd02b55b8a2bcc7e054f51b76b549199a916ad584`
License: see `zlib-1.4/LICENSE`.

Run `python3 Scripts/build-zlib.py` from the repository root to rebuild. It builds
both architectures in temporary directories, runs upstream's `make test` for
each, and copies the resulting libraries only after both suites pass. Rosetta
is required to run the Intel tests on Apple Silicon. The copies in this directory
are retained for compatibility with the existing source distribution.
