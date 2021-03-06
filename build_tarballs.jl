# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder

name = "polymake"
version = v"4.0r1"

# Collection of sources required to build polymake
sources = [
    "https://github.com/polymake/polymake.git" =>
    "a5e18b015e06e6a7785312910f8d9ee561c52fac",

    "./bundled"
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/polymake
if [[ $target == *darwin* ]]; then
  mkdir -p build/Opt
  cp ../config/config-$target.ninja build/config.ninja
  cp ../config/build-Opt-$target.ninja build/Opt/build.ninja
  cp ../config/targets.ninja build/targets.ninja
  ln -s ../config.ninja build/Opt/config.ninja
  mkdir -p build/perlx/5.30.0/apple-darwin14
  cp ../config/perlx-config-$target.ninja build/perlx/5.30.0/apple-darwin14/config.ninja
  export PERL5LIB=/workspace/destdir/lib/perl5/5.30.0:/workspace/destdir/lib/perl5/5.30.0/darwin-2level:/workspace/srcdir/patches
  atomic_patch -p1 ../patches/polymake-cross.patch
else
  ./configure CFLAGS="-Wno-error" CC="$CC" CXX="$CXX" \
              PERL=${prefix}/bin/perl LDFLAGS="$LDFLAGS" \
              --prefix=${prefix} \
              --with-gmp=${prefix} \
              --with-cdd=${prefix} \
              --with-lrs=${prefix} \
              --with-bliss=${prefix} \
              --with-ppl=${prefix} \
              --with-flint=${prefix} \
              --with-singular=${prefix} \
              --with-libnormaliz=${prefix} \
              --without-native
fi

ninja -v -C build/Opt -j$(( nproc / 2 ))
# avoid having an empty shared object which binary builder doesnt like
[ -s build/Opt/lib/ideal.$dlext ] || \
$CXX -shared --sysroot=/opt/$target/$target/sys-root -o build/Opt/lib/ideal.$dlext -lc
ninja -v -C build/Opt install
if [[ $target == *darwin* ]]; then
# undo patch needed for building
atomic_patch -R -p1 ../patches/polymake-cross.patch
fi
install -m 444 -D support/*.pl $prefix/share/polymake/support/

# avoid conflicts between different perls
unset PERL5LIB
rm -f $prefix/lib/libperl.$dlext

# prepare paths for replacement after install
/usr/bin/perl -pi -e "s#${prefix}#REPLACEPREFIX#g" ${prefix}/lib/polymake/config.ninja ${prefix}/bin/polymake*
# replace miniperl
/usr/bin/perl -pi -e "s#miniperl-for-build#perl#" ${prefix}/lib/polymake/config.ninja ${prefix}/bin/polymake*
# remove sysroot and target argument
/usr/bin/perl -pi -e 's/--sysroot[= ][^\s]+//g' ${prefix}/lib/polymake/config.ninja
/usr/bin/perl -pi -e 's/-target[= ][^\s]+//g' ${prefix}/lib/polymake/config.ninja

# remove path and arch from compiler command
if [[ "$CC" == *"clang"* ]]; then
  /usr/bin/perl -pi -e 's/^CC = \S+/CC = clang/g' ${prefix}/lib/polymake/config.ninja
  /usr/bin/perl -pi -e 's/^CXX = \S+/CXX = clang++/g' ${prefix}/lib/polymake/config.ninja
else
  /usr/bin/perl -pi -e 's/^CC = \S+/CC = gcc/g' ${prefix}/lib/polymake/config.ninja
  /usr/bin/perl -pi -e 's/^CXX = \S+/CXX = g++/g' ${prefix}/lib/polymake/config.ninja
fi
# prepare rpath for binarybuilder
# to check: do we need this for darwin?
if [[ $target == *linux* ]]; then
  patchelf --set-rpath $(patchelf --print-rpath ${prefix}/lib/libpolymake.so | sed -e "s#${prefix}/lib/#\$ORIGIN/#g") ${prefix}/lib/libpolymake.so
  for lib in ${prefix}/lib/polymake/lib/*.so; do
    patchelf --set-rpath "\$ORIGIN/../.." $lib;
  done
  patchelf --set-rpath "\$ORIGIN/../../../../../../.." ${prefix}/lib/polymake/perlx/*/*/auto/Polymake/Ext/Ext.so
fi

"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = [
# singular doesnt support i686
# Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc6))
# Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc7))
# Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc8))
 Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc6))
 Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc7))
 Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc8))
 MacOS(:x86_64)
]

# The products that we will ensure are always built
# TODO: we cannot use libpolymake as product as this picks up libpolymake-apps ...
products(prefix) = [
#    LibraryProduct(prefix, "libpolymake", :libpolymake)
    ExecutableProduct(prefix,"polymake", :polymake)
    ExecutableProduct(prefix,"polymake-config", Symbol("polymake_config"))
]

# Dependencies that must be installed before this package can be built
dependencies = [
    "https://github.com/JuliaPackaging/Yggdrasil/releases/download/MPFR-v4.0.2-1/build_MPFR.v4.0.2.jl",
    "https://github.com/JuliaPackaging/Yggdrasil/releases/download/GMP-v6.1.2-1/build_GMP.v6.1.2.jl",
    "https://github.com/benlorenz/readlineBuilder/releases/download/v8.0/build_readline.v8.0.0.jl",
    "https://github.com/benlorenz/ncursesBuilder/releases/download/v6.1/build_ncurses.v6.1.0.jl",
    "https://github.com/benlorenz/perlBuilder/releases/download/v5.30.0-2/build_perl.v5.30.0.jl",
    "https://github.com/benlorenz/boostBuilder/releases/download/v1.71.0/build_boost.v1.71.0.jl",
    "https://github.com/benlorenz/pplBuilder/releases/download/v1.2/build_ppl.v1.2.0.jl",
    "https://github.com/benlorenz/lrslibBuilder/releases/download/v7.0/build_lrslib.v7.0.0.jl",
    "https://github.com/benlorenz/cddlibBuilder/releases/download/v0.94.0-j-1/build_cddlib.v0.94.0-j.jl",
    "https://github.com/benlorenz/blissBuilder/releases/download/v0.73/build_bliss.v0.73.0.jl",
    "https://github.com/benlorenz/normalizBuilder/releases/download/v3.7.4/build_normaliz.v3.7.4.jl",
    "https://github.com/thofma/Flint2Builder/releases/download/dd1021/build_libflint.v0.0.0-dd1021a6cbaca75d94e6e066c26a3a5622884a7c.jl",
    "https://github.com/thofma/NTLBuilder2/releases/download/v10.5.0-1/build_libntl.v10.5.0.jl",
    "https://github.com/wbhart/SingularBuilder/releases/download/0.0.2/build_libsingular.v0.0.1-2.jl",
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies)

