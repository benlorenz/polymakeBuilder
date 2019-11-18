# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "polymake"
version = v"4.0r1"

# Collection of sources required to build polymake
sources = [
    GitSource("https://github.com/polymake/polymake.git", "a5e18b015e06e6a7785312910f8d9ee561c52fac")
    DirectorySource("./bundled")
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir/polymake

# workaround CompilerSupportLibraries issue with new gcc
rm "${libdir}"/libstdc++*

atomic_patch -p1 ../patches/cdd.patch
atomic_patch -p1 ../patches/relocatable.patch
if [[ $target == *darwin* ]]; then
  # we cannot run configure and instead provide config files
  mkdir -p build/Opt
  cp ../config/config-$target.ninja build/config.ninja
  cp ../config/build-Opt-$target.ninja build/Opt/build.ninja
  cp ../config/targets.ninja build/targets.ninja
  ln -s ../config.ninja build/Opt/config.ninja
  mkdir -p build/perlx/5.30.0/apple-darwin14
  cp ../config/perlx-config-$target.ninja build/perlx/5.30.0/apple-darwin14/config.ninja
  # for a modified JSON module and to make miniperl find the correct modules
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
              --without-singular \
              --with-libnormaliz=${prefix} \
              --without-native
fi

ninja -v -C build/Opt -j$(( nproc / 2 ))
# avoid having an empty shared object which binary builder doesnt like
[ -s build/Opt/lib/ideal.$dlext ] || \
$CXX -shared --sysroot=/opt/$target/$target/sys-root -o build/Opt/lib/ideal.$dlext -lc

ninja -v -C build/Opt install

# undo patch needed for building
if [[ $target == *darwin* ]]; then
atomic_patch -R -p1 ../patches/polymake-cross.patch
fi
install -m 444 -D support/*.pl $prefix/share/polymake/support/

# avoid conflicts between different perls
unset PERL5LIB
rm -f $prefix/lib/libperl.$dlext

# put automatic path detection in polymake and polymake-config
#/usr/bin/perl -pi -e 's#^   \$InstallTop.*#   use Cwd qw( abs_path );\n   use File::Basename qw( dirname );\n   \$InstallTop=abs_path(dirname(\$0)."/../share/polymake");#g' ${prefix}/bin/polymake
#/usr/bin/perl -pi -e 's#^   \$InstallArch.*#   \$InstallArch=abs_path(dirname(\$0)."/../lib/polymake");#g' ${prefix}/bin/polymake
#/usr/bin/perl -pi -e 's#^my \$InstallArch.*#use Cwd qw( abs_path );\nuse File::Basename qw( dirname );\nmy \$InstallArch=abs_path(dirname(\$0)."/../lib/polymake");#g' ${prefix}/bin/polymake-config

# FIXME: we need a working config.ninja for building wrappers...
#/usr/bin/perl -pi -e "s#${prefix}#REPLACEPREFIX#g" ${prefix}/lib/polymake/config.ninja

# replace miniperl
/usr/bin/perl -pi -e "s#miniperl-for-build#perl#" ${prefix}/lib/polymake/config.ninja ${prefix}/bin/polymake*

# remove sysroot and target argument
#/usr/bin/perl -pi -e 's/--sysroot[= ][^\s]+//g' ${prefix}/lib/polymake/config.ninja
#/usr/bin/perl -pi -e 's/-target[= ][^\s]+//g' ${prefix}/lib/polymake/config.ninja

# remove path and arch from compiler command
# TODO: at some point we should have a binarybuilder provided compiler?
#if [[ "$CC" == *"clang"* ]]; then
#  /usr/bin/perl -pi -e 's/^CC = \S+/CC = clang/g' ${prefix}/lib/polymake/config.ninja
#  /usr/bin/perl -pi -e 's/^CXX = \S+/CXX = clang++/g' ${prefix}/lib/polymake/config.ninja
#else
#  /usr/bin/perl -pi -e 's/^CC = \S+/CC = gcc/g' ${prefix}/lib/polymake/config.ninja
#  /usr/bin/perl -pi -e 's/^CXX = \S+/CXX = g++/g' ${prefix}/lib/polymake/config.ninja
#fi
# prepare rpath for binarybuilder
# to check: do we need this for darwin?
#if [[ $target == *linux* ]]; then
#  patchelf --set-rpath $(patchelf --print-rpath ${prefix}/lib/libpolymake.so | sed -e "s#${prefix}/lib/#\$ORIGIN/#g") ${prefix}/lib/libpolymake.so
#  for lib in ${prefix}/lib/polymake/lib/*.so; do
#    patchelf --set-rpath "\$ORIGIN/../.." $lib;
#  done
#  patchelf --set-rpath "\$ORIGIN/../../../../../../.." ${prefix}/lib/polymake/perlx/*/*/auto/Polymake/Ext/Ext.so
#fi

"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = expand_cxxstring_abis([
 Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(libstdcxx_version = v"3.4.23"))
 Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(libstdcxx_version = v"3.4.25"))
 Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(libstdcxx_version = v"3.4.26"))
 MacOS(:x86_64)
])

# The products that we will ensure are always built
products = [
    LibraryProduct("libpolymake", :libpolymake; dont_dlopen=true)
    ExecutableProduct("polymake", :polymake)
    ExecutableProduct("polymake-config", Symbol("polymake_config"))
]

# Dependencies that must be installed before this package can be built
dependencies = [
    # upstream
    Dependency(PackageSpec(name="GMP_jll", uuid="781609d7-10c4-51f6-84f2-b8444358ff6d"))
    Dependency(PackageSpec(name="MPFR_jll", uuid="3a97d323-0669-5f0c-9066-3539efd106a3"))
    Dependency(PackageSpec(name="boost_jll", uuid="28df3c45-c428-5900-9ff8-a3135698ca75"))
    Dependency(PackageSpec(name="CompilerSupportLibraries_jll", uuid="e66e0078-7015-5450-92f7-15fbd957f2ae"))
    Dependency(PackageSpec(name="lrslib_jll", uuid="3873f7d0-7b7c-52c3-bdf4-8ab39b8f337a"))
    Dependency(PackageSpec(name="normaliz_jll", uuid="6690c6e9-4e12-53b8-b8fd-4bffaef8839f"))
    Dependency(PackageSpec(name="PPL_jll", uuid="80dd9cbb-8b87-5171-a280-372cc418f402"))
    Dependency(PackageSpec(name="cddlib_jll", uuid="f07e07eb-5685-515a-97c8-3014f6152feb"))
    Dependency(PackageSpec(name="FLINT_jll", uuid="e134572f-a0d5-539d-bddf-3cad8db41a82"))
    Dependency(PackageSpec(name="bliss_jll", uuid="508c9074-7a14-5c94-9582-3d4bc1871065"))

    # local
    Dependency(PackageSpec(name="perl_jll", uuid="454b57e5-be5b-5d2e-8b87-0c7c7d0dfe4b"))

    #"singular_jll", #FIXME: not yet as artifact
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; preferred_gcc_version=v"7")

