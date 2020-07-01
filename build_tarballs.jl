# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "polymake"
version = v"4.1.1"

# Collection of sources required to build polymake
sources = [
    GitSource("https://github.com/polymake/polymake.git", "8704ebbba9f8cc2b07f824a283ffed49a8c036be")
    DirectorySource("./bundled")
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/polymake

perl_version=5.30.3

atomic_patch -p1 ../patches/relocatable.patch
if [[ $target == *darwin* ]]; then
  # we cannot run configure and instead provide config files
  mkdir -p build/Opt
  mkdir -p build/perlx/$perl_version/apple-darwin14
  cp ../config/config-$target.ninja build/config.ninja
  cp ../config/build-Opt-$target.ninja build/Opt/build.ninja
  cp ../config/targets.ninja build/targets.ninja
  ln -s ../config.ninja build/Opt/config.ninja
  cp ../config/perlx-config-$target.ninja build/perlx/$perl_version/apple-darwin14/config.ninja
  # for a modified pure perl JSON module and to make miniperl find the correct modules
  export PERL5LIB=$prefix/lib/perl5/$perl_version:$prefix/lib/perl5/$perl_version/darwin-2level:$WORKSPACE/srcdir/patches
  atomic_patch -p1 ../patches/polymake-cross.patch
  atomic_patch -p1 ../patches/polymake-cross-build.patch
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
              --without-singular \
              --with-libnormaliz=${prefix} \
              --without-native
fi

ninja -v -C build/Opt -j8
# $(( nproc / 2 ))

ninja -v -C build/Opt install

# undo patch needed for building
if [[ $target == *darwin* ]]; then
  atomic_patch -R -p1 ../patches/polymake-cross-build.patch
fi
install -m 444 -D support/*.pl $prefix/share/polymake/support/

# replace miniperl
sed -i -e "s/miniperl-for-build/perl/" ${libdir}/polymake/config.ninja ${bindir}/polymake*
# replace binary path with env
sed -i -e "s#$bindir/perl#/usr/bin/env perl#g" ${libdir}/polymake/config.ninja ${bindir}/polymake*
# remove target and sysroot
sed -i -e "s#--sysroot[ =]\S\+##g" ${libdir}/polymake/config.ninja
sed -i -e "s#-target[ =]\S\+##g" ${libdir}/polymake/config.ninja

install_license COPYING
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = expand_cxxstring_abis([
 MacOS(:x86_64)
 Linux(:x86_64, libc=:glibc)
 Linux(:i686, libc=:glibc)
])

# The products that we will ensure are always built
products = [
    LibraryProduct("libpolymake", :libpolymake; dont_dlopen=true)
    ExecutableProduct("polymake", :polymake)
    ExecutableProduct("polymake-config", Symbol("polymake_config"))
]

# Dependencies that must be installed before this package can be built
dependencies = [
    Dependency(PackageSpec(name="Perl_jll", uuid="83958c19-0796-5285-893e-a1267f8ec499", version=v"5.30.3"))
    Dependency("GMP_jll")
    Dependency("MPFR_jll")
    Dependency("boost_jll")
    Dependency("CompilerSupportLibraries_jll")
    Dependency("lrslib_jll")
    Dependency("PPL_jll")
    Dependency("cddlib_jll")
    Dependency("bliss_jll")
    Dependency(PackageSpec(name="FLINT_jll", uuid="e134572f-a0d5-539d-bddf-3cad8db41a82",version=v"2.6.0"))
    Dependency("normaliz_jll")
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; preferred_gcc_version=v"7")

