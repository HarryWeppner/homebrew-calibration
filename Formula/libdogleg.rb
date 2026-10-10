class Libdogleg < Formula
  desc "Large-scale nonlinear least-squares optimization library"
  homepage "https://github.com/dkogan/libdogleg"
  url "https://github.com/dkogan/libdogleg/archive/refs/tags/v0.18.tar.gz"
  sha256 "d97ef0c149463f84e9bd40c8852da444605a38bac432b5b2774de3dd15180bab"
  license "LGPL-3.0-or-later"

  bottle do
    root_url "https://github.com/HarryWeppner/homebrew-calibration/releases/download/libdogleg-0.18"
    rebuild 1
    sha256 cellar: :any, arm64_tahoe:   "6eadadcfdcf278524763d4961b6367b96adcd515c5a5a1400ae589c632700a9b"
    sha256 cellar: :any, arm64_sequoia: "9a9805f2da0188dd7cc7fa45c85e859b2356f6b8290f77e1d95f771e5bca4e67"
    sha256 cellar: :any, arm64_linux:   "3f95e35fd890b9e0a8b6dc3916709d29f9867e214ec0da012ff388a541612ec4"
    sha256 cellar: :any, x86_64_linux:  "016d0789aee6e20e5ad97e382c200cae1e37d3265f1ce53021a25e948145979f"
  end

  depends_on "harryweppner/calibration/mrbuild" => :build
  depends_on "openblas"
  depends_on "suite-sparse"

  uses_from_macos "perl" => :build

  def install
    # Each project's choose_mrbuild.mk uses ./mrbuild if it exists
    mrbuild = formula_opt_include("harryweppner/calibration/mrbuild")/"mrbuild"
    (buildpath/"mrbuild").install_symlink mrbuild.children
    (buildpath/"mrbuild").install_symlink formula_opt_bin("harryweppner/calibration/mrbuild") => "bin"

    # mrbuild takes the version from git or debian/changelog, and the tarball
    # has neither. USE_DEBIAN_PATHS= skips its Debian layout guesses and files
    # the manpage under man3.
    args = %W[
      VERSION=#{version}
      USE_DEBIAN_PATHS=
      DESTDIR=#{prefix}
      INSTALL_ROOT_LIB=/lib
      INSTALL_ROOT_INCLUDE=/include
      INSTALL_ROOT_MAN=/share/man
    ]
    # On Linux, mrbuild's install runs "chrpath -d", which also deletes the
    # RPATH that points at Homebrew's lib. On macOS it only deletes the
    # @loader_path entries it added itself.
    args << "_STRIP_RPATH_FILES=true" if OS.linux?
    system "make", *args
    %w[sparse dense dense-products-packed-upper dense-products-unpacked].each do |mode|
      system "./sample", "--check", mode
    end
    system "make", "install", *args
  end

  test do
    (testpath/"test.c").write <<~C
      #include <math.h>
      #include <stdio.h>
      #include <dogleg.h>

      /* Fit y = a*exp(b*t) to points generated with a=2, b=-0.5 */
      #define N 10
      static void f(const double* p, double* x, double* J, void* cookie)
      {
        (void)cookie;
        for (int i = 0; i < N; i++) {
          double t = i, e = exp(p[1] * t);
          x[i] = p[0] * e - 2.0 * exp(-0.5 * t);
          J[2 * i + 0] = e;
          J[2 * i + 1] = p[0] * t * e;
        }
      }

      int main(void)
      {
        double p[2] = {1.0, 0.0};
        dogleg_parameters2_t params;
        dogleg_getDefaultParameters(&params);
        dogleg_optimize_dense2(p, 2, N, f, NULL, &params, NULL);
        printf("%.6f %.6f\\n", p[0], p[1]);
        return !(fabs(p[0] - 2.0) < 1e-6 && fabs(p[1] + 0.5) < 1e-6);
      }
    C
    system ENV.cc, "test.c", "-I#{include}", "-I#{formula_opt_include("suite-sparse")}",
           "-L#{lib}", "-ldogleg", "-lm", "-o", "test"
    assert_equal "2.000000 -0.500000", shell_output("./test").strip
  end
end
