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
   patches and builds only from tags. Done on 2026-11-03: every fix the tap
   carried is in a release, and the tap builds all five from release
   tarballs with no patches and no mrbuild workarounds.
   - mrbuild v1.22 (= master 1cf4d70): macOS names 3c964ff, Linux rpaths
     8a5c059, native-is-not-cross 252b31d and e92a044, numpy fallback
     17414c2, module path eeba340, no `private` bac23f8 (#12), and
     cross-builds driven by `dpkg-buildpackage`'s `DEB_*` (#11 and #13
     closed). The reply on #13 with the 2026-10-24 re-check was never
     posted, and v1.22 made it moot.
   - libdogleg v0.18 works. #4 (licence version) is merged but untagged;
     a new tag is optional.
   - vnlog v1.45 takes `all` from List::Util (f8c55a6, after #12), so the
     formula has no List::MoreUtils.
   - mrgingham v1.29 has the OpenCV 5 support (v1.28 doesn't build against
     Homebrew's OpenCV 5).
   - mrcal v2.5.3 (2026-11-03, = `release-2.5` 0cb3581a), a packaging
     release from `release-2.5`: #61 and #65, Dima's version of #68
     (49539dd0), #67, and #69 (#60 for `release-2.5`, cherry-picked). Base
     any new mrcal PRs on `release-2.5`; master will become 3.0 and has
     half-done work.
   - Tap PR #4 (check only) proved the unpatched set before the tag: run
     41473835339 on 0cb3581a, green on all four platforms. Close it once
     the `release-tags` PR lands.
   - Follow-up, not in the first homebrew-core PR: `mrcal-stereo --viz
     stereo` (pyfltk and GL_image_display). It works on Linux in a
     prototype; pyfltk 1.4.5.0 doesn't build with SWIG 4.5, and
     GL_image_display needs `-lstb` and `-lX11` fixes and probably an
     OpenGL 3.3 core context on macOS. Reported to Dima on 2026-11-03.
2. **The tap.** Five formulae on release tarballs, CI on the full matrix.
   `brew audit --strict --new --online` passes, and `brew
   update-python-resources --print-only` reproduces mrgingham's and mrcal's
   PyPI resources (2026-11-03). The tap's audit doesn't check notability.
3. **homebrew-core.** One PR, one commit per formula in the order above,
   submitted by Harry (not Dima: the notability bar triples for the repo
   owner). Disclose the AI use in the PR, and answer reviewers personally,
   per Homebrew's AI policy.

Notability (30 forks, 30 watchers or 75 stars; 90/90/225 for self-submission),
2026-10-23: mrcal 332 stars and 35 forks, vnlog 174 stars, mrgingham 73 stars
(16 forks, just short), libdogleg 24 stars, mrbuild 9 stars. libdogleg and
mrbuild need an exception, argued as required dependencies of mrcal; mrgingham
may too. GL_image_display (for `--viz stereo`) has 2 stars, 0 forks and 1
watcher (2026-11-03), so it waits for a follow-up PR rather than adding a
fourth exception to the first one.

## Versions, patches and sources

Track the pins and patches in `~/Code/calibration-containers`, which builds the
same tools as Podman images:

- `sources.lock` holds the upstream URL and ref.
- `patches/NAME/*.patch` holds the fixes.
- `.cache/src/NAME/` holds exported, patched sources, handy for grepping.

The tap's versions in November 2026, all release tags:

| Source | Version |
|---|---|
| mrbuild | v1.22 |
| libdogleg | v0.18 |
| vnlog | v1.45 |
| mrgingham | v1.29 |
| mrcal | v2.5.3 |

calibration-containers' pins date from October 2026 and are older.
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
  - Set `INSTALL_ROOT_PY3_MODULES`. mrbuild up to v1.21 took
    `PY3_MODULE_PATH` from `distutils`, which Python 3.12+ lacks; v1.22
    falls back to `sysconfig` (eeba340).
  - Install libdogleg's header as `include/dogleg.h` (`INSTALL_ROOT_INCLUDE`),
    since mrcal does `#include <dogleg.h>`.
  - Pass `VERSION=#{version}`: mrbuild reads the version from git or
    `debian/changelog`, and a release tarball has neither.
  - Pass `USE_DEBIAN_PATHS=` (empty). It stops mrbuild calling
    `dpkg-architecture` on Ubuntu, and it moves manpages into `manN/`.
- **Python extensions.** Pass `PYTHON_VERSION_FOR_EXTENSIONS=3.15`.
  mrbuild up to v1.21 also needed `DEB_HOST_MULTIARCH=`,
  `DEB_HOST_GNU_TYPE=` and `_INCLUDENUMPY_FROM_PYTHON=1` on hosts with
  `dpkg-architecture` (Ubuntu, this Fedora host), which it took for a Debian
  cross-build. v1.22 needs none: native builds are native (252b31d), numpy
  falls back to Python (17414c2), and tools are unprefixed unless
  cross-building (e92a044).
- **Linux rpaths.** mrbuild up to v1.21 ran `chrpath -d` at install when
  `chrpath` exists, which deleted Homebrew's RPATH too, and the libraries
  then loaded the host's `/lib64/libcholmod.so` (`brew linkage --test`:
  "Unwanted system libraries"). v1.22 strips only its own `$ORIGIN` entries
  (8a5c059), reading the RPATH with plain `objdump` in native builds
  (e92a044). CI's images have no `chrpath`, so only a local build here
  shows this.
- **macOS library names.** mrbuild up to v1.21 named macOS libraries
  Linux-style (`libxxx.dylib.ABI`), which `brew audit` rejects as
  non-libraries. v1.22 (3c964ff) builds `libxxx.ABI.TAIL.dylib` with install
  name `libxxx.ABI.dylib`; mrcal needs #65 (`$(call
  MRBUILD_LIBSO_ABI,libmrcal)`, in 2.5.3) to build with it.
- **GNU make on macOS** is 3.81. vnlog's `define VAR =` needs 3.82, as did
  mrbuild's `private` (2b9f5f3) until #12 removed it. To test make 3.81 on
  Linux, build it from the GNU tarball with `CFLAGS="-O2 -std=gnu89
  -D__alloca=alloca -Dbsd_signal=signal -D__stat=stat -Wno-error
  -Wno-implicit-function-declaration -Wno-incompatible-pointer-types
  -Wno-int-conversion"`; it reproduces macOS's `private` error.
- **GNU getopt.** `mrgingham-rotate-corners` and `mrcal-rotate-corners` parse
  options with GNU `getopt -l`. macOS's BSD getopt has no long options, so
  mrgingham depends on `gnu-getopt` on macOS and points the script at it;
  without it, its manpage generation fails. mrcal 2.5.x has no
  `mrcal-rotate-corners`, so mrcal doesn't need this (master does).
- **macOS rpaths.** mrbuild names macOS libraries `@rpath/libfoo.N.dylib`,
  links with `@loader_path` rpaths, and deletes every `@loader_path` rpath at
  install (`Makefile.common.footer`), so installed binaries and extensions
  can't find their libraries. The mrgingham formula adds rpaths to
  `bin/mrgingham` and the extension with `MachO::Tools.add_rpath`, then
  re-signs them, and likewise mrcal's extensions. `brew linkage` passes on
  macOS in CI.
  - mrbuild keeps rpaths that don't start with `@loader_path`, so passing
    `-Wl,-rpath,#{lib}` in `LDFLAGS` might replace the `MachO` code
    (untested). mrcal links its extensions with `$(LDFLAGS)`, but
    mrgingham's Makefile (v1.29, line 118) doesn't, so its extension would
    need an upstream one-liner.
- **OpenCV.** Homebrew's `opencv` is 5.0 (`opencv5.pc`, headers under
  `include/opencv5`). Upstream's `09b2055` supports it: it tries `opencv4`
  first, then `opencv5`, and includes `opencv2/features/features.hpp` on 5
  (in v1.29).
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
  - The formulae use python@3.15, the Python Homebrew's own Python formulae
    use. In October 2026 `opencv` moved to it (5.0.0_12 ships `cv2` for
    3.15 only), as did `cython`, `meson`, `python-packaging` and
    `python-setuptools`; `numpy` and `scipy` ship for both 3.14 and 3.15.
    Under 3.14, mrcal's build-time tests fail with "No module named 'cv2'".
    Python 3.15's argparse also rejects a help string with an unescaped `%`
    when the argument is added ("badly formed help string"); mrcal master
    fixed its one case in ce5d2517, and #67 brought that to 2.5.3.
    When Homebrew moves again, move vnlog, mrgingham and mrcal together.
  - shapely 2.2 builds with meson-python, which Homebrew lacks. meson-python
    and pyproject-metadata are pure Python, so mrcal stages their sources as
    build-only resources on the `PYTHONPATH`, alongside Homebrew's Cython
    (in `cython`'s libexec), and builds with Homebrew's `meson`. It also
    needs `ninja`, `pkgconf` and `geos`.
  - meson must run under the same Python as the build: on macOS, Cython's
    link test looks for the Python running meson, and fails ("Cython requires
    python3 dependency") otherwise. Homebrew's `meson` and the formulae are
    both on python@3.15, so that holds now.
  - mrcal's own package goes in python@3.15's site-packages, and its bundled
    packages in a `libexec` venv. A `.pth` file each way lets
    `python3.15 -c "import mrcal"` and the tools both work.
  - Python extension modules go into python@3.15's site-packages, so
    `python3.15 -c "import mrgingham"` works.
  - `mrcal-stereo --viz stereo` needs pyfltk and GL_image_display; they're
    left out for now (see the plan). The `mrcal-show-*` tools plot with
    Homebrew's `gnuplot` (qt, pngcairo, pdfcairo, svg): checked on Linux on
    2026-11-03, not yet on macOS.
- **vnlog** needs `mawk`, and `moreutils` for `vnl-ts`.
  - Its CPAN runtime modules become `resource`s in `libexec`, with `PERL5LIB`
    wrappers: Text::Table (which needs Text::Aligner). v1.45 takes `all`
    from List::Util, so List::MoreUtils is gone; v1.43 dropped
    String::ShellQuote. Its tests also need IPC::Run and Text::Diff (which
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
  livecheck to `vX.Y[.Z]` tags. All five formulae use tag URLs now, so
  autobump can bump them. Its PRs fail with "HOMEBREW_GITHUB_API_TOKEN
  credentials do not have sufficient scope" (cause unconfirmed).
- **mrcal's tests.** `make test-nosampling` takes about a minute, so the
  build runs it. It needs zsh (a build dependency on Linux).
  `test-optimizer-callback.py` fails on master, after its regularization
  rework (Dima closed mrcal#63, which regenerated its reference data). 2.5.x
  doesn't have the rework, and the test passes there (24 of 24).
- **mrcal's near-singularity test** fails 6 of 1350 checks on Apple Silicon.
  mrcal's results match Linux's; at a rotation of exactly pi, r and -r are the
  same rotation, and the test's numpy reference takes the sign from roundoff.
  It's platform-dependent: skipping just the flipped cases dropped 1 case on
  Linux (1347 checks) and 2 on macOS (1344). mrcal#68 compared against the
  closer form instead; Dima committed his own version (49539dd0, in 2.5.3),
  and every check passes on all four platforms.
- **mrcal's upstream fixes**, both in 2.5.3:
  - Install `_attribute.h`: `mrcal.h` and `basic-geometry.h` include it, and
    `DIST_INCLUDE` missed it (#60 on master, #69 on `release-2.5`).
  - `minimath_generate.pl` used List::MoreUtils only for `pairwise`; it now
    uses `map`, so the build needs no CPAN module (#61). The generated
    header is byte-identical.
- **mrcal runs `mrgingham` and `vnl-filter`** as commands (corner finding in
  `calibration.py`, `mrcal-is-within-valid-intrinsics-region`), so it depends
  on both formulae.
- **Alternative:** mrcal's pip wheels already cover Apple Silicon Macs (with
  vnlog and gnuplot), but have no mrgingham. A tap with just mrgingham and
  vnlog, used alongside `pip install mrcal`, is a cheaper fallback.

## Local development

Linuxbrew is installed at `/home/linuxbrew/.linuxbrew`; `~/.bashrc.d/linuxbrew.sh`
puts it on the PATH. This host has `dpkg-dev` and `chrpath` (but no
`x86_64-linux-gnu-objdump`), which is what made mrbuild's Debian guesses and
rpath stripping show up here and not in CI.

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
and the symlink needs trusting again. The symlink is trusted on this host.

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
- The first `brew style` or `brew audit` installs Homebrew's style gems into
  its vendor bundle. Don't run one while a `brew install` is running: on
  2026-10-28 that crashed an install in its "fix install linkage" step.
- To work on another branch while the tap checkout stays on `main` (for
  installs), use a `git worktree`; `brew style` takes file paths.
- macOS can't be tested locally. Open a PR: `.github/workflows/tests.yml`
  runs `brew test-bot` on GitHub's macOS and Linux runners (about 30 and 55
  minutes for all four formulae). test-bot only builds formulae that a PR
  changes. On a platform where a formula has no bottle yet, test-bot ignores
  its failed build and the job still shows green ("1 failed step ignored!"),
  so check the job's annotations, not just the check mark. To publish a green
  PR's bottles, run the `publish.yml` workflow
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
