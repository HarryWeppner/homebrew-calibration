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
- **macOS rpaths.** mrbuild strips its `@loader_path` rpaths on macOS, and
  links Python extensions without `LDFLAGS`. The mrgingham formula adds rpaths
  to `bin/mrgingham` and the extension with `MachO::Tools.add_rpath`, then
  re-signs them. This is untested until CI runs on macOS; check `brew linkage`
  there.
- **OpenCV.** Homebrew's `opencv` is 5.0 (`opencv5.pc`, headers under
  `include/opencv5`), and `opencv@4` exists. mrgingham builds with 5.0 after
  one fix, on the `brew` branch of `~/Code/mrgingham` and inline in the
  formula (`patch :DATA`): try `pkg-config opencv5`, and include
  `opencv2/features2d.hpp`, since 5.0 dropped
  `opencv2/features2d/features2d.hpp`. `cv::imread` still arrives via
  `highgui.hpp`.
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
    (in `cython`'s libexec). It also needs `meson`, `ninja`, `pkgconf` and
    `geos`.
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
