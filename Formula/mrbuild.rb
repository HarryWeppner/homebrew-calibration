require "language/perl"

class Mrbuild < Formula
  include Language::Perl::Shebang

  desc "Make-based build system for C/C++ libraries, tools and Python extensions"
  homepage "https://github.com/dkogan/mrbuild"
  url "https://github.com/dkogan/mrbuild/archive/refs/tags/v1.21.tar.gz"
  sha256 "a5667b6bc2adbce8dbf1072364a54cde973e155ed74408a3f1c87b426c31521e"
  license "MIT"

  bottle do
    root_url "https://github.com/HarryWeppner/homebrew-calibration/releases/download/mrbuild-1.21"
    sha256 cellar: :any_skip_relocation, arm64_tahoe:   "186ea44b2ba862d3f7a294fc4661e8955eef6410a42096378114a3d9150fed89"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "f01d842f6fa1316e66c16190611fcd975de5494ac16060f9d47abc254f884f16"
    sha256 cellar: :any_skip_relocation, arm64_linux:   "fa324768420bf1a82978fdad300c728a068b3b8f5715d88467e30a85e6a06b3a"
    sha256 cellar: :any_skip_relocation, x86_64_linux:  "8860ae5af8aee33e08c6f833f1f762da6ab4daec98c17d833d4704db5287f605"
  end

  uses_from_macos "perl"

  # macOS: name libraries libxxx.ABI.dylib, not libxxx.dylib.ABI.
  # https://github.com/dkogan/mrbuild/pull/8
  patch do
    file "Patches/mrbuild/macos-dylib-names.patch"
  end

  def install
    # Where Debian's package puts them, and where projects' choose_mrbuild.mk
    # looks: include/mrbuild and bin
    (include/"mrbuild").install "Makefile.common.header", "Makefile.common.footer"
    bin.install "bin/make-pod-from-help"
    rewrite_shebang detected_perl_shebang, bin/"make-pod-from-help"
  end

  test do
    (testpath/"hello.c").write <<~C
      #include "hello.h"
      int hello_answer(void) { return 42; }
    C
    (testpath/"hello.h").write "int hello_answer(void);\n"
    (testpath/"hello-tool.c").write <<~C
      #include <stdio.h>
      #include "hello.h"
      int main(void) { printf("%d\\n", hello_answer()); return 0; }
    C
    (testpath/"Makefile").write <<~MAKE
      include #{include}/mrbuild/Makefile.common.header
      PROJECT_NAME := hello
      ABI_VERSION  := 1
      TAIL_VERSION := 2
      LIB_SOURCES  := hello.c
      BIN_SOURCES  := hello-tool.c
      DIST_INCLUDE := hello.h
      include #{include}/mrbuild/Makefile.common.footer
    MAKE

    system "make"
    assert_equal "42", shell_output("./hello-tool").strip

    system "make", "install", "DESTDIR=#{testpath}/inst", "USE_DEBIAN_PATHS=",
           "INSTALL_ROOT_LIB=/lib", "INSTALL_ROOT_BIN=/bin", "INSTALL_ROOT_INCLUDE=/include"
    libs = (testpath/"inst/lib").children.map { |f| f.basename.to_s }.sort
    expected = if OS.mac?
      %w[libhello.1.2.dylib libhello.1.dylib libhello.dylib]
    else
      %w[libhello.so libhello.so.1 libhello.so.1.2]
    end
    assert_equal expected, libs
    assert_path_exists testpath/"inst/include/hello.h"

    # make-pod-from-help turns argparse-style --help output into POD
    (testpath/"tool").write <<~EOS
      #!/bin/sh
      cat <<'HELP'
      usage: tool [-h]

      Says hello

      Synopsis:

        $ tool
        hello

      optional arguments:
        -h, --help  show this help message and exit
      HELP
    EOS
    chmod "+x", testpath/"tool"
    pod = shell_output("#{bin}/make-pod-from-help ./tool")
    assert_match "Says hello", pod
    assert_match "=head1 SYNOPSIS", pod
  end
end
