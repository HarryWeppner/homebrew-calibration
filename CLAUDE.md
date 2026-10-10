# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A Homebrew tap (`harryweppner/calibration`) for Dima Kogan's camera-calibration
tools. Targets: macOS on Apple Silicon and Homebrew on Linux (x86_64, arm64).
Homebrew has no Intel-macOS OpenCV bottles, so Intel Macs are out of scope.
README.md is the user-facing doc.

## Plan

The goal (agreed with Dima, October 2026) is homebrew-core, with each project
as its own formula, in dependency order:

1. **mrbuild**: the build system, needed at build time by all the others.
2. **libdogleg**: needs `suite-sparse`.
3. **vnlog**: Perl tools, the C library `libvnlog`, and Perl and Python modules.
4. **mrgingham**: needs OpenCV.
5. **mrcal**: the C library, the Python package and the `mrcal-*` tools.

This tap is the proving ground until then. A formula is done when:

- `brew install --build-from-source` succeeds;
- `brew test` and `brew audit --strict --new` pass;
- `brew linkage` is clean;
- `brew test-bot` passes in CI on macOS 15 and 26 and on x86_64 and arm64 Linux.

Keep the `test do` blocks quick. Upstream's full test suites belong in the
build, if anywhere: mrcal's `test-nosampling` is far too slow for `test do`.

Phases:

1. **Upstream fixes and releases.** homebrew-core forbids downstream-only
   patches and builds only from tags. Open PRs (October 2026): mrbuild #6–#10
   (#10 sits on #7), mrcal #60–#63, vnlog #12, libdogleg #4. Releases needed:
   mrbuild (at least #8), mrgingham with OpenCV 5 and the Homebrew-aware
   `choose_mrbuild.mk`, mrcal with #60–#63. Dima is adding Homebrew lookup to
   each `choose_mrbuild.mk` himself (vnlog v1.44 has it).
2. **The tap.** Five formulae, CI on the full matrix; switch each to its
   release tarball and drop each patch or workaround as the fixes land.
3. **homebrew-core.** One PR, one commit per formula in the order above,
   submitted by Harry (not Dima: the notability bar triples for the repo
   owner). Disclose the AI use in the PR, and answer reviewers personally,
   per Homebrew's AI policy.

Notability (30 forks, 30 watchers or 75 stars; 90/90/225 for self-submission),
October 2026: mrcal 326 stars, vnlog 174, mrgingham 72 (16 forks, just short),
libdogleg 24, mrbuild 9. libdogleg and mrbuild need an exception, argued as
required dependencies of mrcal; mrgingham may too.

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
| vnlog | v1.44 |
| mrgingham | `09b2055` (v1.28-7, upstream's OpenCV 5 support) |
| mrcal | `119d5b06` (v2.5.2-263) |

A tap can use commit pins; homebrew-core needs releases (see the plan).
Upstream's macOS wheel build is a working recipe for the macOS dependencies:
`mrcal/packaging/build-deps-{common,macos}.sh`.

## Findings that shape the formulae

- **mrbuild** is build-only Makefile fragments plus `make-pod-from-help`. Its
  formula installs them as Debian does, in `include/mrbuild` and `bin`. The
  others depend on it at build time and symlink it into `./mrbuild`, which
  every project's `choose_mrbuild.mk` checks first (newer ones also look in
  `$(HOMEBREW_PREFIX)/include/mrbuild`).
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
- **Python extensions.** mrbuild runs `dpkg-architecture`, found on Ubuntu
  and on this Fedora host. If it answers, mrbuild assumes a Debian cross-build
  and looks for Debian's sysconfig file. Pass `DEB_HOST_MULTIARCH=` and
  `DEB_HOST_GNU_TYPE=` (empty), `PYTHON_VERSION_FOR_EXTENSIONS=3.14`, and
  `_INCLUDENUMPY_FROM_PYTHON=1` (on Linux mrbuild asks `pkg-config numpy`,
  which Homebrew lacks).
- **Linux rpaths.** mrbuild's install runs `chrpath -d` when `chrpath` exists,
  which deletes Homebrew's RPATH too, and the libraries then load the host's
  `/lib64/libcholmod.so`. Pass `_STRIP_RPATH_FILES=true` on Linux.
  `brew linkage --test` catches this as "Unwanted system libraries".
- **macOS library names.** mrbuild names macOS libraries Linux-style
  (`libxxx.dylib.ABI`), and `brew audit` rejects them as non-libraries. The fix
  is on the `brew` branch of `~/Code/mrbuild`, and the tap carries it as
  `Patches/mrbuild/macos-dylib-names.patch`, applied to each formula's mrbuild
  resource (`patch do file ... end`). It builds `libxxx.ABI.TAIL.dylib` with
  install name `libxxx.ABI.dylib`; `libxxx.dylib.ABI` stays in the build tree
  as a symlink for project Makefiles (mrcal's refers to it), uninstalled.
- **GNU getopt.** `mrgingham-rotate-corners` and `mrcal-rotate-corners` parse
  options with GNU `getopt -l`. macOS's BSD getopt has no long options, so
  both formulae depend on `gnu-getopt` on macOS and point the scripts at it.
  Without it, mrgingham's manpage generation fails.
- **macOS rpaths.** mrbuild strips its `@loader_path` rpaths on macOS, and
  links Python extensions without `LDFLAGS`. The mrgingham formula adds rpaths
  to `bin/mrgingham` and the extension with `MachO::Tools.add_rpath`, then
  re-signs them, and likewise mrcal's extensions. `brew linkage` passes on
  macOS in CI.
- **OpenCV.** Homebrew's `opencv` is 5.0 (`opencv5.pc`, headers under
  `include/opencv5`). Upstream's `09b2055` supports it: it tries `opencv4`
  first, then `opencv5`, and includes `opencv2/features/features.hpp` on 5.
  In a formula build Homebrew's pkg-config can't see the host's OpenCV 4, so
  it finds 5.
  - `opencv5.pc` lists every module. Link with `-Wl,--as-needed` (Linux) or
    `-Wl,-dead_strip_dylibs` (macOS) to keep the five that mrgingham uses.
- **stb** isn't in Homebrew. It's header-only, so use a pinned `resource`.
  mrcal's `USE_LOCAL_STB_IMPLEMENTATION` defaults on for macOS; set it on Linux
  too. mrcal only needs `stb_image.h`, found as `<stb/stb_image.h>`.
- **Python packages** not in Homebrew are bundled as `resource`s, per
  Homebrew's Python rules.
  - Not in Homebrew: numpysane and gnuplotlib (mrgingham and mrcal), shapely
    (mrcal). mrgingham puts them in a `libexec` virtualenv with system site
    packages, which its Python script's shebang points at.
  - `pypi_packages package_name: "", extra_packages: ...` lets
    `brew update-python-resources` resolve them, as homebrew-core requires;
    neither project is on PyPI. mrgingham doesn't depend on `gnuplot` (it
    pulls in Qt, only for `--show`); a caveat says so.
  - In Homebrew: `numpy`, `scipy`, `gnuplot`, `python-packaging` (numpysane
    needs `packaging` on Python 3.12+, which lacks distutils) and `cv2` (from
    `opencv`). Building numpysane, gnuplotlib and pyyaml needs
    `python-setuptools`.
  - Always pass `build_isolation: false` to `pip_install`. With isolation, pip
    fetches build dependencies from PyPI and builds them from source; for
    shapely that means compiling numpy.
  - shapely 2.2 builds with meson-python, which Homebrew lacks. meson-python
    and pyproject-metadata are pure Python, so mrcal stages their sources as
    build-only resources on the `PYTHONPATH`, alongside Homebrew's Cython
    (in `cython`'s libexec). It also needs `ninja`, `pkgconf` and `geos`.
  - meson must run under the same Python as the build: on macOS, Cython's
    link test looks for the Python running meson, and fails ("Cython requires
    python3 dependency") when Homebrew's `meson` uses a newer one (it moved
    to python@3.15 in October 2026). So meson is a build-only resource too,
    and `MESON=.../meson.py` makes meson-python run it with python3.14.
  - mrcal's own package goes in python@3.14's site-packages, and its bundled
    packages in a `libexec` venv. A `.pth` file each way lets
    `python3.14 -c "import mrcal"` and the tools both work.
  - Python extension modules go into python@3.14's site-packages, so
    `python3.14 -c "import mrgingham"` works.
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
  suite, and Linuxbrew hosts may lack `/bin/zsh`. The formula doesn't need it:
  the build runs only `test/test--mrgingham-find-board`, with the venv's
  Python.
- **livecheck.** With no `livecheck` block, livecheck matches every git tag.
  mrcal's `2023-07-26--triangulated-features-merged` tag then sorts as newer
  than 2.5.2, so autobump would open bogus PRs. mrgingham and mrcal restrict
  livecheck to `vX.Y[.Z]` tags. Their commit-pinned versions read as newer
  than upstream, so autobump leaves them alone until a new release; it then
  probably can't rewrite a commit URL, so switch those to tag URLs by hand.
- **mrcal's tests.** `make test-nosampling` takes about a minute, so the
  build runs it. It needs zsh (a build dependency on Linux).
  `test-optimizer-callback.py` fails on upstream master; the formula drops it
  from `test.sh` with `inreplace`, as calibration-containers' patch does.
- **mrcal's near-singularity test** fails 6 of 1350 checks on Apple Silicon.
  mrcal's results match Linux's; at a rotation of exactly pi, r and -r are the
  same rotation, and the test's numpy reference takes the sign from roundoff.
  The tap carries an interim patch,
  `Patches/mrcal/test-near-singularity-either-form.patch`, that skips only
  checks hitting that ambiguity (none on Linux). The upstream fix should
  compare against the closer form instead, converting the reference gradient.
- **mrcal's upstream fixes**, on the `brew` branch of `~/Code/mrcal` and
  inline in the formula (`patch :DATA`, the diff from the pin to `brew`):
  - Install `_attribute.h`: `mrcal.h` and `basic-geometry.h` include it, and
    `DIST_INCLUDE` missed it.
  - `minimath_generate.pl` used List::MoreUtils only for `pairwise`; it now
    uses `map`, so the build needs no CPAN module. The generated header is
    byte-identical.
- **mrcal runs `mrgingham` and `vnl-filter`** as commands (corner finding in
  `calibration.py`, `mrcal-is-within-valid-intrinsics-region`), so it depends
  on both formulae.
- **Alternative:** mrcal's pip wheels already cover Apple Silicon Macs (with
  vnlog and gnuplot), but have no mrgingham. A tap with just mrgingham and
  vnlog, used alongside `pip install mrcal`, is a cheaper fallback.

## Local development

Linuxbrew is installed at `/home/linuxbrew/.linuxbrew`.

`brew tap NAME PATH` clones the checkout, so uncommitted edits are invisible
to `brew`. The tap directory here is instead a symlink to this checkout:
`$(brew --repository)/Library/Taps/harryweppner/homebrew-calibration`.

`brew update` updates this checkout like any tap: it stashes uncommitted
changes and switches to `main`. Commit first, or afterwards run
`git checkout <branch> && git stash pop`. `HOMEBREW_NO_AUTO_UPDATE=1` stops
`brew install` from triggering it.

Homebrew 7 refuses to load formulae from untrusted taps. Naming a formula on
the command line trusts it, but its dependencies from this tap stay untrusted,
so run `brew trust harryweppner/calibration` (it's recorded in
`~/.homebrew/trust.json`). Trust is keyed by the tap's git remote, or by the
tap name when the tap is a symlink with no remote, so swapping between a clone
and the symlink needs trusting again. Both are trusted on this host.

```sh
brew tap harryweppner/calibration ~/Code/homebrew-calibration   # once
brew install --build-from-source harryweppner/calibration/NAME
brew test harryweppner/calibration/NAME
brew audit --strict --new harryweppner/calibration/NAME
brew linkage harryweppner/calibration/NAME
```

- Don't run `brew tap-new` or other developer commands casually: they switch
  on the global developer mode (`brew developer off` reverts it). `brew audit`,
  `brew style` and `brew livecheck` count, so turn it off after a session of
  formula work.
- macOS can't be tested locally. Open a PR: `.github/workflows/tests.yml`
  runs `brew test-bot` on GitHub's macOS and Linux runners (about 30 and 55
  minutes for all four formulae). test-bot only builds formulae that a PR
  changes. To publish a green PR's bottles, run the `publish.yml` workflow
  with its number; `brew pr-pull` pushes to `main` and closes the PR, then
  `git pull` here.

## Conventions

- Commit messages carry no attribution lines.
- Upstream fixes go on a branch named `brew` in the checkouts under `~/Code`:
  `mrbuild`, `libdogleg`, `vnlog`, `mrgingham` and `mrcal`. The formula
  carries them as patches until upstream merges them.
- The GitHub remote is `HarryWeppner/homebrew-calibration`, public. It's a
  temporary demonstration until upstream hosts the tap; then leave a
  `tap_migrations.json` pointing at the new tap before archiving or deleting.
