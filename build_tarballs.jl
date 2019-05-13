# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder

name = "polymake"
version = v"3.4"

# Collection of sources required to build polymake
sources = [
    "https://github.com/polymake/polymake.git" =>
    "6b81bed91f0582ec34ab1ba0d3197cfdcb36263c",

]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/polymake
./configure CFLAGS="-Wno-error" CC="$CC" CXX="$CXX" \
            PERL=${prefix}/bin/perl LDFLAGS="$LDFLAGS" \
            --prefix=${prefix} \
            --with-gmp=${prefix} \
            --with-cdd=${prefix} \
            --with-lrs=${prefix} \
            --with-bliss=${prefix} \
            --with-ppl=${prefix} \
            --with-libnormaliz=${prefix} \
            --without-native
ninja -v -C build/Opt -j$(( nproc / 2 ))
# avoid having an empty shared object which binary builder doesnt like
[ -s build/Opt/lib/ideal.so ] || \
$CXX -shared -Wl,--as-needed --sysroot=/opt/$target/$target/sys-root -o build/Opt/lib/ideal.$dlext -lc
ninja -v -C build/Opt install
# prepare paths for replacement after install
/workspace/destdir/bin/perl -pi -e "s#${prefix}#REPLACEPREFIX#g" ${prefix}/lib/polymake/config.ninja ${prefix}/bin/polymake-config ${prefix}/bin/polymake
# remove sysroot argument
/workspace/destdir/bin/perl -pi -e 's/--sysroot[= ][^ ]+//g' ${prefix}/lib/polymake/config.ninja
# fix compiler command
if [ "$CC" == *"clang"* ]; then
/workspace/destdir/bin/perl -pi -e 's/^CC = .*/CC = clang/g' ${prefix}/lib/polymake/config.ninja
/workspace/destdir/bin/perl -pi -e 's/^CXX = .*/CXX = clang++/g' ${prefix}/lib/polymake/config.ninja
else
/workspace/destdir/bin/perl -pi -e 's/^CC = .*/CC = gcc/g' ${prefix}/lib/polymake/config.ninja
/workspace/destdir/bin/perl -pi -e 's/^CXX = .*/CXX = g++/g' ${prefix}/lib/polymake/config.ninja
fi
# prepare rpath for binarybuilder
patchelf --set-rpath $(patchelf --print-rpath ${prefix}/lib/libpolymake.so | sed -e "s#${prefix}/lib/#\$ORIGIN/#g") ${prefix}/lib/libpolymake.so
for lib in ${prefix}/lib/polymake/lib/*.so; do
   patchelf --set-rpath "\$ORIGIN/../.." $lib;
done
patchelf --set-rpath "\$ORIGIN/../../../../../../.." ${prefix}/lib/polymake/perlx/*/*/auto/Polymake/Ext/Ext.so
# tests need Time::HiRes ...
# /workspace/destdir/bin/perl perl/polymake --script run_testcases --examples '*'

"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
#TODO: platforms = supported_platforms()
platforms = [
 Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc6))
 Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc7))
 Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc8))
 Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc6))
 Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc7))
 Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc8))
# Linux(:aarch64, libc=:glibc, compiler_abi=CompilerABI(:gcc6))
# Linux(:aarch64, libc=:glibc, compiler_abi=CompilerABI(:gcc7))
# Linux(:aarch64, libc=:glibc, compiler_abi=CompilerABI(:gcc8))
# Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc6))
# Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc7))
# Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc8))
# Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(:gcc6))
# Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(:gcc7))
# Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(:gcc8))
# Linux(:i686, libc=:musl, compiler_abi=CompilerABI(:gcc6))
# Linux(:i686, libc=:musl, compiler_abi=CompilerABI(:gcc7))
# Linux(:i686, libc=:musl, compiler_abi=CompilerABI(:gcc8))
# Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(:gcc6))
# Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(:gcc7))
# Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(:gcc8))
# Linux(:aarch64, libc=:musl, compiler_abi=CompilerABI(:gcc6))
# Linux(:aarch64, libc=:musl, compiler_abi=CompilerABI(:gcc7))
# Linux(:aarch64, libc=:musl, compiler_abi=CompilerABI(:gcc8))
# Linux(:armv7l, libc=:musl, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc6))
# Linux(:armv7l, libc=:musl, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc7))
# Linux(:armv7l, libc=:musl, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc8))
# MacOS(:x86_64)
# FreeBSD(:x86_64)
# Windows(:i686, compiler_abi=CompilerABI(:gcc6))
# Windows(:i686, compiler_abi=CompilerABI(:gcc7))
# Windows(:i686, compiler_abi=CompilerABI(:gcc8))
# Windows(:x86_64, compiler_abi=CompilerABI(:gcc6))
# Windows(:x86_64, compiler_abi=CompilerABI(:gcc7))
# Windows(:x86_64, compiler_abi=CompilerABI(:gcc8))
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
    "https://github.com/bicycle1885/ZlibBuilder/releases/download/v1.0.4/build_Zlib.v1.2.11.jl",
    "https://github.com/bicycle1885/XML2Builder/releases/download/v1.0.2/build_XML2Builder.v2.9.9.jl",
    "https://github.com/JuliaPackaging/Yggdrasil/releases/download/MPFR-v4.0.2-1/build_MPFR.v4.0.2.jl",
    "https://github.com/JuliaPackaging/Yggdrasil/releases/download/GMP-v6.1.2-1/build_GMP.v6.1.2.jl",
    "https://github.com/benlorenz/perlBuilder/releases/download/v5.28.2/build_perl.v5.28.2.jl",
    "https://github.com/benlorenz/XSLTBuilder/releases/download/v1.1.33/build_XSLTBuilder.v1.1.33.jl",
    "https://github.com/benlorenz/boostBuilder/releases/download/v1.70.0/build_boost.v1.70.0.jl",
    "https://github.com/benlorenz/pplBuilder/releases/download/v1.2/build_ppl.v1.2.0.jl",
    "https://github.com/benlorenz/lrslibBuilder/releases/download/v7.0/build_lrslib.v7.0.0.jl",
    "https://github.com/benlorenz/cddlibBuilder/releases/download/v0.94.0-j-1/build_cddlib.v0.94.0-j.jl",
    "https://github.com/benlorenz/blissBuilder/releases/download/v0.73/build_bliss.v0.73.0.jl",
    "https://github.com/benlorenz/normalizBuilder/releases/download/v3.7.2/build_normaliz.v3.7.2.jl",
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies)

