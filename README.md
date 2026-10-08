# homebrew-calibration

Unofficial Homebrew formulae for the camera-calibration toolchain by Dima
Kogan, for macOS (Apple Silicon) and Homebrew on Linux:

- [vnlog](https://github.com/dkogan/vnlog): the text-table tools and libraries
- [mrgingham](https://github.com/dkogan/mrgingham): the chessboard corner finder
- [mrcal](https://github.com/dkogan/mrcal): the calibration solver and tools
- [libdogleg](https://github.com/dkogan/libdogleg): the optimizer mrcal uses

No formulae are published yet. The versions and patches track the pins in
[calibration-containers](https://github.com/HarryWeppner/calibration-containers),
which builds the same tools as Podman images. Report bugs in the tools
upstream, and problems with the formulae here.

## Install

```sh
brew tap harryweppner/calibration
brew install mrgingham mrcal vnlog
```

Or in a `Brewfile`:

```ruby
tap "harryweppner/calibration"
brew "mrgingham"
```

## Developing

```sh
brew tap harryweppner/calibration ~/Code/homebrew-calibration   # use this checkout
brew install --build-from-source harryweppner/calibration/NAME
brew test harryweppner/calibration/NAME
brew audit --strict harryweppner/calibration/NAME
```

Pull requests are built and tested by `brew test-bot` on macOS and Linux
(`.github/workflows/tests.yml`). To publish a pull request's bottles, run the
`brew pr-pull` workflow (`publish.yml`) with its number, or `brew pr-pull`
locally.
