class Mrgingham < Formula
  include Language::Python::Shebang
  include Language::Python::Virtualenv

  desc "Chessboard corner finder for camera calibration"
  homepage "https://github.com/dkogan/mrgingham"
  url "https://github.com/dkogan/mrgingham/archive/8775c0938e8187f93e9272c76bb3bcb83a95e111.tar.gz"
  version "1.28-5-g8775c09"
  sha256 "520deafc6d5588c190b4997000729e5339208976512ecb59936ac19c739965ec"
  license all_of: ["LGPL-2.1-or-later", "MIT"]

  depends_on "pkgconf" => :build
  depends_on "python-setuptools" => :build
  depends_on "gnuplot"
  depends_on "numpy"
  depends_on "opencv"
  depends_on "python-packaging"
  depends_on "python@3.14"
  depends_on "vnlog"

  uses_from_macos "perl" => :build

  resource "mrbuild" do
    url "https://github.com/dkogan/mrbuild/archive/refs/tags/v1.21.tar.gz"
    sha256 "a5667b6bc2adbce8dbf1072364a54cde973e155ed74408a3f1c87b426c31521e"
  end

  resource "numpysane" do
    url "https://files.pythonhosted.org/packages/16/3e/9ff84572ceb48c1c5ce08000192d13c2f904a650fb34a876e3f7f83acf79/numpysane-0.45.tar.gz"
    sha256 "caebeccc2c92d373ee3d850f45d7724cab1067e912efe8a8fa54167f5d1b4a82"
  end

  resource "gnuplotlib" do
    url "https://files.pythonhosted.org/packages/88/81/24068edcc7b383d776dedc7509aec1352abd6746c3448b3761668cb56738/gnuplotlib-0.47.tar.gz"
    sha256 "35ad06a4adf16dba0e4be0f74615e7beb6b8e0358c4cf5c0f98fef85bc46aac8"
  end

  # Build with OpenCV 5. Not sent upstream yet.
  patch :DATA

  def python3
    "python3.14"
  end

  def install
    # mrgingham-observe-pixel-uncertainty and the tests need numpysane and
    # gnuplotlib. The venv sees numpy, vnlog and packaging in Homebrew's
    # site-packages.
    venv = virtualenv_create(libexec, python3)
    venv.pip_install resources.reject { |r| r.name == "mrbuild" }, build_isolation: false
    rewrite_shebang python_shebang_rewrite_info(libexec/"bin/python"), "mrgingham-observe-pixel-uncertainty"

    (buildpath/"mrbuild").install resource("mrbuild")

    # DEB_HOST_*= stops mrbuild treating a host with dpkg-architecture (such
    # as Ubuntu) as a Debian cross-build, which looks for Debian's Python.
    # mrbuild finds numpy with pkg-config on Linux; ask Python instead.
    site_packages = Language::Python.site_packages(python3)
    args = %W[
      VERSION=#{version}
      USE_DEBIAN_PATHS=
      DEB_HOST_MULTIARCH=
      DEB_HOST_GNU_TYPE=
      PYTHON_VERSION_FOR_EXTENSIONS=#{python3.delete_prefix("python")}
      _INCLUDENUMPY_FROM_PYTHON=1
      DESTDIR=#{prefix}
      INSTALL_ROOT_LIB=/lib
      INSTALL_ROOT_BIN=/bin
      INSTALL_ROOT_INCLUDE=/include/mrgingham
      INSTALL_ROOT_MAN=/share/man
      PY3_MODULE_PATH=#{site_packages}
      INSTALL_ROOT_PY3_MODULES=/#{site_packages}
    ]
    # On Linux, mrbuild's install runs "chrpath -d", which also deletes the
    # RPATH that points at Homebrew's lib.
    args << "_STRIP_RPATH_FILES=true" if OS.linux?
    # opencv5.pc lists every OpenCV module; link only the ones in use
    ENV.append "LDFLAGS", OS.mac? ? "-Wl,-dead_strip_dylibs" : "-Wl,--as-needed"

    system "make", *args
    system libexec/"bin/python", "test/test--mrgingham-find-board"
    system "make", "install", *args

    # On macOS, mrbuild deletes the @loader_path rpaths it linked with, and
    # its Python extension never gets LDFLAGS. Point both at lib.
    if OS.mac?
      ext = Dir[prefix/site_packages/"mrgingham*.so"].first
      [bin/"mrgingham", Pathname(ext)].each do |f|
        MachO::Tools.add_rpath(f.to_s, rpath(source: f.dirname), strict: false)
        MachO.codesign!(f) if Hardware::CPU.arm?
      end
    end
  end

  test do
    (testpath/"board.py").write <<~PY
      import numpy as np

      # A 10x10-corner chessboard with 50-pixel squares, slightly blurred
      n, square, margin = 11, 50, 80
      image = np.full((n*square + 2*margin,) * 2, 255.)
      for i in range(n):
          for j in range(n):
              if (i + j) % 2 == 0:
                  image[margin + i*square: margin + (i+1)*square,
                        margin + j*square: margin + (j+1)*square] = 0
      k = np.array((1., 4., 6., 4., 1.)) / 16.
      for axis in (0, 1):
          image = np.apply_along_axis(lambda r: np.convolve(r, k, 'same'), axis, image)
      image = image.astype(np.uint8)

      with open("board.pgm", "wb") as f:
          f.write(b"P5 %d %d 255\\n" % (image.shape[1], image.shape[0]))
          f.write(image.tobytes())

      import mrgingham
      corners = mrgingham.find_board(image, gridn=10)
      assert corners.shape == (100, 2), corners
    PY
    system python3, "board.py"

    output = shell_output("#{bin}/mrgingham board.pgm")
    assert_equal 100, output.lines.count { |l| l.start_with?("board.pgm ") }

    output = shell_output("#{bin}/mrgingham-observe-pixel-uncertainty --help")
    assert_match "observed point distribution", output
  end
end

__END__
diff --git a/Makefile b/Makefile
index ee4d7cc..ad0b17f 100644
--- a/Makefile
+++ b/Makefile
@@ -24,10 +24,10 @@ BIN_SOURCES += test-dump-chessboard-corners.cc test-dump-blobs.cc test-find-grid
 LIB_SOURCES := find_grid.cc find_blobs.cc find_chessboard_corners.cc mrgingham.cc ChESS.c
 
 # The opencv people (or maybe the Debian people?) have renamed the opencv.pc
-# file in opencv 4. So now I look for both version 4 and the default. What will
-# happen with opencv5? We'll see!
-CXXFLAGS_CV := $(shell pkg-config --cflags opencv4 2>/dev/null || pkg-config --cflags opencv 2>/dev/null)
-LDLIBS_CV   := $(shell pkg-config --libs   opencv4 2>/dev/null || pkg-config --libs   opencv 2>/dev/null)
+# file in opencv 4, and again in opencv 5. So I look for each of these, newest
+# first
+CXXFLAGS_CV := $(shell pkg-config --cflags opencv5 2>/dev/null || pkg-config --cflags opencv4 2>/dev/null || pkg-config --cflags opencv 2>/dev/null)
+LDLIBS_CV   := $(shell pkg-config --libs   opencv5 2>/dev/null || pkg-config --libs   opencv4 2>/dev/null || pkg-config --libs   opencv 2>/dev/null)
 CCXXFLAGS += $(CXXFLAGS_CV)
 LDLIBS    += $(LDLIBS_CV) -lpthread
 
diff --git a/find_blobs.cc b/find_blobs.cc
index af625dd..c510df9 100644
--- a/find_blobs.cc
+++ b/find_blobs.cc
@@ -1,4 +1,4 @@
-#include <opencv2/features2d/features2d.hpp>
+#include <opencv2/features2d.hpp>
 #include <opencv2/highgui/highgui.hpp>
 
 #include "point.hh"
