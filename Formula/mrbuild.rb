require "language/perl"

class Mrbuild < Formula
  include Language::Perl::Shebang

  desc "Make-based build system for C/C++ libraries, tools and Python extensions"
  homepage "https://github.com/dkogan/mrbuild"
  # master, for the checks before the next release
  url "https://github.com/dkogan/mrbuild/archive/e92a04403419c1c5711035268d81bad6e4d809a8.tar.gz"
  version "1.21-14-ge92a044"
  sha256 "712e4819d5459be77fbf3f96eee1e890da9bc42d64a45418b160bd65f88017d9"
  license "MIT"

  uses_from_macos "perl"

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
