# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A Homebrew tap (`harryweppner/calibration`) for Dima Kogan's camera-calibration
tools. Targets: macOS on Apple Silicon and Homebrew on Linux (x86_64, arm64).
Homebrew has no Intel-macOS OpenCV bottles, so Intel Macs are out of scope.
README.md is the user-facing doc.

## Plan

Formulae, in this order (each depends on the earlier ones):

1. **libdogleg**: needs `suite-sparse`.
2. **vnlog**: Perl tools, the C library `libvnlog`, and Perl and Python modules.
3. **mrgingham**: needs OpenCV.
4. **mrcal**: the C library, the Python package and the `mrcal-*` tools.

A formula is done when:

- `brew install --build-from-source` succeeds;
- `brew test` and `brew audit --strict --new` pass;
- `brew linkage` is clean;
- `brew test-bot` passes in CI on macOS and Linux.

Keep the `test do` blocks quick. Upstream's full test suites belong in the
build, if anywhere: mrcal's `test-nosampling` is far too slow for `test do`.

Later, with upstream's agreement, propose formulae to homebrew-core:

- vnlog first;
- then libdogleg as a dependency of mrcal;
- then mrcal.

The barriers:

- homebrew-core needs tagged stable releases.
- Its notability threshold is 30 forks, 30 watchers or 75 stars, and three
  times that for a self-submission. In October 2026 the projects stood at:
  - mrcal: 326 stars;
  - vnlog: 174 stars;
  - mrgingham: 72 stars and 16 forks, just short;
  - libdogleg: 24 stars.

mrcal's install docs ask anyone who wants it in Homebrew to get in touch.

## Versions, patches and sources

Track the pins and patches in `~/Code/calibration-containers`, which builds the
same tools as Podman images:

- `sources.lock` holds the upstream URL and ref.
- `patches/NAME/*.patch` holds the fixes.
- `.cache/src/NAME/` holds exported, patched sources, handy for grepping.

The pins in October 2026:

| Source | Pin |
|---|---|
| mrbuild | v1.21 |
| libdogleg | v0.18 |
| vnlog | v1.43 |
| mrgingham | `8775c09` (v1.28-5) |
| mrcal | `119d5b06` (v2.5.2-263) |

A tap can use commit pins. homebrew-core would need releases: mrgingham v1.28,
mrcal v2.5.2. Upstream's macOS wheel build is a working recipe for the macOS
dependencies: `mrcal/packaging/build-deps-{common,macos}.sh`.

## Findings that shape the formulae

- **mrbuild** is build-only Makefile fragments, not packaged in Homebrew. Make
  it a `resource` in each formula, not a formula. mrbuild already supports
  macOS: it builds `.dylib`s, handles numpy includes, and deletes rpaths.
- **Install paths.** Pass mrbuild's `INSTALL_ROOT_*` and `DESTDIR` explicitly.
  The Linux defaults guess Debian or Fedora layouts (`USRLIB`).
  - `PY3_MODULE_PATH` comes from `distutils`, which Python 3.12+ lacks. Set
    `INSTALL_ROOT_PY3_MODULES` yourself, or add `python-setuptools` as a build
    dependency.
  - Install libdogleg's header as `include/dogleg.h` (`INSTALL_ROOT_INCLUDE`),
    since mrcal does `#include <dogleg.h>`.
  - Pass `VERSION=#{version}`: mrbuild reads the version from git or
    `debian/changelog`, and a release tarball has neither.
  - Pass `USE_DEBIAN_PATHS=` (empty). It stops mrbuild calling
    `dpkg-architecture` on Ubuntu, and it moves manpages into `manN/`.
- **Linux rpaths.** mrbuild's install runs `chrpath -d` when `chrpath` exists,
  which deletes Homebrew's RPATH too, and the libraries then load the host's
  `/lib64/libcholmod.so`. Pass `_STRIP_RPATH_FILES=true` on Linux.
  `brew linkage --test` catches this as "Unwanted system libraries".
- **macOS rpaths.** mrbuild strips rpaths on macOS. Check with `brew linkage`
  that the Python extension modules still find `libmrcal` and `libmrgingham`.
- **OpenCV.** Homebrew's `opencv` is 5.0, and `opencv@4` exists.
  - mrgingham's Makefile only tries `pkg-config opencv4` and `opencv`. Either
    depend on `opencv@4` or patch in `opencv5`.
  - Check that `cv::imread` still arrives via `highgui.hpp` under OpenCV 5.
  - Upstream has never built mrgingham on macOS.
- **stb** isn't in Homebrew. It's header-only, so use a pinned `resource`.
  mrcal's `USE_LOCAL_STB_IMPLEMENTATION` defaults on for macOS; set it on Linux
  too.
- **Python packages** not in Homebrew are bundled as `resource`s, per
  Homebrew's Python rules.
  - Not in Homebrew: numpysane and gnuplotlib (mrgingham and mrcal), shapely
    (mrcal).
  - In Homebrew: `numpy`, `scipy` and `gnuplot`.
  - mrcal's interactive viewers need pyfltk and GL_image_display. Leave them
    out at first.
- **vnlog** needs `mawk`, and `moreutils` for `vnl-ts`.
  - Its CPAN runtime modules become `resource`s in `libexec`, with `PERL5LIB`
    wrappers: List::MoreUtils (which needs List::MoreUtils::XS and
    Exporter::Tiny) and Text::Table (which needs Text::Aligner). v1.43 doesn't
    use String::ShellQuote. Its tests also need IPC::Run and Text::Diff (which
    needs Algorithm::Diff), installed in the build tree only.
  - The tools must stay together in `libexec/bin`: `vnl-join` runs
    `perl $RealBin/vnl-sort`, which fails on a shell wrapper.
  - `vnl-gen-header` emits `#include <vnlog/vnlog.h>`, so the headers go in
    `include/vnlog/`.
  - Its GNUmakefile uses `define VAR =`, which needs GNU make 3.82+. Build
    with `gmake` on macOS.
  - `vnl-sort`, `vnl-join` and `vnl-tail` wrap the system `sort`, `join` and
    `tail`, which are BSD versions on macOS. The test suite, which runs in the
    build, detects non-GNU `join` and `uniq` and then runs fewer tests.
- **mrgingham's zsh patch** (find `zsh` on the PATH) only matters for its test
  suite, and Linuxbrew hosts may lack `/bin/zsh`.
- **mrcal's test patch** skips `test-optimizer-callback.py`, which fails on
  upstream master. It's only needed if the build runs the test suite.
- **Alternative:** mrcal's pip wheels already cover Apple Silicon Macs (with
  vnlog and gnuplot), but have no mrgingham. A tap with just mrgingham and
  vnlog, used alongside `pip install mrcal`, is a cheaper fallback.

## Local development

Linuxbrew is installed at `/home/linuxbrew/.linuxbrew`.

`brew tap NAME PATH` clones the checkout, so uncommitted edits are invisible
to `brew`. The tap directory here is instead a symlink to this checkout:
`$(brew --repository)/Library/Taps/harryweppner/homebrew-calibration`.

```sh
brew tap harryweppner/calibration ~/Code/homebrew-calibration   # once
brew install --build-from-source harryweppner/calibration/NAME
brew test harryweppner/calibration/NAME
brew audit --strict --new harryweppner/calibration/NAME
brew linkage harryweppner/calibration/NAME
```

- Don't run `brew tap-new` or other developer commands casually: they switch
  on the global developer mode (`brew developer off` reverts it).
- macOS can't be tested locally. Use GitHub's macOS runners via
  `.github/workflows/tests.yml` (the `brew tap-new` template), once the repo
  is on GitHub.

## Conventions

- Commit messages carry no attribution lines.
- Upstream fixes go on a branch named `brew` in the checkouts under `~/Code`:
  `mrbuild`, `libdogleg`, `vnlog`, `mrgingham` and `mrcal`. The formula
  carries them as patches until upstream merges them.
- There is no GitHub remote yet. Creating `HarryWeppner/homebrew-calibration`
  is a separate step that needs the owner's go-ahead.
