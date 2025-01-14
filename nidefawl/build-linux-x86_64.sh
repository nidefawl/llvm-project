#!/bin/bash
set -e
LLVM_SRC_PATH=./llvm-project

CLEAN=
CXX_FLAGS=
# CXX_FLAGS+="-march=native "
# CXX_FLAGS+="-mtune=native "
C_FLAGS=$CXX_FLAGS
EXTRA_ARGS=""

BUILD_TAG="linux-x86_64"
BUILD="build-${BUILD_TAG}"
BUILDDIR_TOOLCHAIN="${BUILD}"
INSTALL_PREFIX="llvm-${BUILD_TAG}"

BOOT_TC=
if [ ! -z "$BOOT_TC" ]; then
  export CC="${BOOT_TC}/bin/clang"
  export CXX="${BOOT_TC}/bin/clang++"
  # use lld if found
  [ -e "${BOOT_TC}/bin/ld.lld" ] && {
    EXTRA_ARGS+="-DLLVM_USE_LINKER=lld "
    EXTRA_ARGS+="-DLLVM_ENABLE_LTO=thin "
  }
  export PATH=$BOOT_TC/bin:$PATH
  export LD_LIBRARY_PATH=$BOOT_TC/lib/x86_64-unknown-linux-gnu
else
  export CC="clang-18"
  export CXX="clang++-18"
  # use lld if found
  /usr/bin/which "ld.lld" &> /dev/null && {
    EXTRA_ARGS+="-DLLVM_USE_LINKER=lld-18 "
    EXTRA_ARGS+="-DLLVM_ENABLE_LTO=thin "
  }
fi

checkVersion() {
  found=$(which $1) && version=$($found --version | head -n 1) && {
    echo "$found: $version"
  } || {
    >&2 echo "$1 not found" && exit 1
  }
}

checkVersion $CC
checkVersion $CXX
checkVersion cmake
checkVersion python3
checkVersion ninja

/usr/bin/which "llvm-config" && {
  echo "llvm-config found in path, cannot build" && exit 1
}

printf "#include <cstddef>\nint main(){return sizeof(size_t);}" \
  | $CXX -x c++ -stdlib=libc++ -v - || {
  >&2 echo "Need libc++ for this to work"
  exit 1
}

CLANG_MAJOR=$(sed -n 's/\s*set(LLVM_VERSION_MAJOR \([0-9]\+\))/\1/p' $LLVM_SRC_PATH/cmake/Modules/LLVMVersion.cmake)
CLANG_MINOR=$(sed -n 's/\s*set(LLVM_VERSION_MINOR \([0-9]\+\))/\1/p' $LLVM_SRC_PATH/cmake/Modules/LLVMVersion.cmake)
CLANG_PATCH=$(sed -n 's/\s*set(LLVM_VERSION_PATCH \([0-9]\+\))/\1/p' $LLVM_SRC_PATH/cmake/Modules/LLVMVersion.cmake)
CLANG_VERSION="$CLANG_MAJOR.$CLANG_MINOR.$CLANG_PATCH"
echo "Building CLANG_VERSION $CLANG_VERSION"
echo "Building CC $CC"
echo "Building CXX $CXX"
sleep 1

[ -z "$CLEAN" ] || {
  rm -rf $BUILDDIR_TOOLCHAIN
  rm -rf $INSTALL_PREFIX
}
mkdir -p $BUILDDIR_TOOLCHAIN


set -x

RUN_CMAKE_CONFIG_STEP=true
BUILD_RUNTIMES=true
BUILD_LLVM=true

# rerunning cmake configure on existing build doesn't work too well
$RUN_CMAKE_CONFIG_STEP && $BUILD_RUNTIMES && rm -Rf "${BUILDDIR_TOOLCHAIN}/runtimes"

$RUN_CMAKE_CONFIG_STEP && $BUILD_RUNTIMES && cmake -Wno-dev --warn-uninitialized \
    -S$LLVM_SRC_PATH/runtimes \
    -B${BUILDDIR_TOOLCHAIN}/runtimes-memsan \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DLLVM_USE_SANITIZER=MemoryWithOrigins \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}/runtimes-memsan" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="x86_64-unknown-linux-gnu" \
    -DLLVM_HOST_TRIPLE="x86_64-unknown-linux-gnu" \
    -DCMAKE_C_COMPILER_TARGET="x86_64-unknown-linux-gnu" \
    -DCMAKE_CXX_COMPILER_TARGET="x86_64-unknown-linux-gnu" \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;libcxxabi;libcxx" \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DCOMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=FALSE \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DLIBCXX_ABI_UNSTABLE=ON \
    -DLIBCXX_ENABLE_SHARED=ON \
    -DLIBCXX_ENABLE_STATIC=ON \
    -DLIBCXX_USE_COMPILER_RT=ON \
    -DLIBCXX_CXX_ABI=libcxxabi \
    -DLIBCXX_INCLUDE_TESTS=OFF \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    -DLIBCXXABI_INCLUDE_TESTS=OFF \
    -DLIBCXXABI_USE_COMPILER_RT=ON \
    -DSANITIZER_CXX_ABI=libcxxabi \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    $EXTRA_ARGS

$BUILD_RUNTIMES && cmake --build "${BUILDDIR_TOOLCHAIN}/runtimes-memsan" --target install

$RUN_CMAKE_CONFIG_STEP && $BUILD_RUNTIMES && cmake -Wno-dev --warn-uninitialized \
    -S$LLVM_SRC_PATH/runtimes \
    -B${BUILDDIR_TOOLCHAIN}/runtimes \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="x86_64-unknown-linux-gnu" \
    -DLLVM_HOST_TRIPLE="x86_64-unknown-linux-gnu" \
    -DCMAKE_C_COMPILER_TARGET="x86_64-unknown-linux-gnu" \
    -DCMAKE_CXX_COMPILER_TARGET="x86_64-unknown-linux-gnu" \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;libcxxabi;libcxx" \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DLIBCXX_ABI_UNSTABLE=ON \
    -DLIBCXX_ENABLE_SHARED=ON \
    -DLIBCXX_ENABLE_STATIC=ON \
    -DLIBCXX_USE_COMPILER_RT=ON \
    -DLIBCXX_CXX_ABI=libcxxabi \
    -DLIBCXX_INCLUDE_TESTS=OFF \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    -DLIBCXXABI_INCLUDE_TESTS=OFF \
    -DLIBCXXABI_USE_COMPILER_RT=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DCOMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=FALSE \
    -DSANITIZER_CXX_ABI=libcxxabi \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    $EXTRA_ARGS

$BUILD_RUNTIMES && cmake --build "${BUILDDIR_TOOLCHAIN}/runtimes" --target install

$RUN_CMAKE_CONFIG_STEP && $BUILD_LLVM && cmake -Wno-dev --warn-uninitialized \
    -S$LLVM_SRC_PATH/llvm \
    -B${BUILDDIR_TOOLCHAIN}/toolchain \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} \
    -DCMAKE_PREFIX_PATH=${INSTALL_PREFIX} \
    -DLLVM_LINK_LLVM_DYLIB=ON \
    -DLLVM_TARGETS_TO_BUILD="Native" \
    -DCMAKE_CROSSCOMPILING=OFF \
    -DCMAKE_SYSTEM_NAME="Linux" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="x86_64-unknown-linux-gnu" \
    -DLLVM_HOST_TRIPLE="x86_64-unknown-linux-gnu" \
    -DCMAKE_C_COMPILER_TARGET="x86_64-unknown-linux-gnu" \
    -DCMAKE_CXX_COMPILER_TARGET="x86_64-unknown-linux-gnu" \
    -DCLANG_RESOURCE_DIR="" \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
    -DLLVM_ENABLE_PROJECTS="clang;lld;lldb;clang-tools-extra" \
    -DLLVM_INSTALL_TOOLCHAIN_ONLY=OFF \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DCLANG_DEFAULT_RTLIB=compiler-rt \
    -DCLANG_DEFAULT_UNWINDLIB=libgcc \
    -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
    -DCLANG_DEFAULT_LINKER=lld \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_GO_TESTS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_RUNTIMES=OFF \
    -DLLVM_ENABLE_OCAMLDOC=OFF \
    -DLLVM_BUILD_TESTS=OFF \
    -DCLANG_INCLUDE_TESTS=OFF \
    -DLLVM_STATIC_LINK_CXX_STDLIB=OFF \
    -DLLVM_VERSION_SUFFIX=${BUILD_TAG} \
    -DCMAKE_CXX_FLAGS="$CXX_FLAGS" \
    -DCMAKE_C_FLAGS="$C_FLAGS" \
    $EXTRA_ARGS

$BUILD_LLVM && cmake --build "${BUILDDIR_TOOLCHAIN}/toolchain" --parallel 6 --target llvm-tblgen
$BUILD_LLVM && cmake --build "${BUILDDIR_TOOLCHAIN}/toolchain" --parallel 9 --target install/strip

# the install prefix for the compiler-rt builtin .a files is not correct
# fix it manually for now
if [ -d "${INSTALL_PREFIX}/lib/clang/19" ]; then
  pushd "${INSTALL_PREFIX}/lib/clang/19"
  if [ ! -d lib ]; then
    mkdir lib
    pushd lib
    ln -s ../../../x86_64-unknown-linux-gnu
    popd
  fi
  popd
fi

# steal the local runtimes and provide them for packaging, what is the worst that could happen?
# in theory this should work
cp /lib/x86_64-linux-gnu/libc++abi.so.1 /build/llvm/llvm-linux-x86_64/lib && \
    cp /lib/x86_64-linux-gnu/libc++.so.1 /build/llvm/llvm-linux-x86_64/lib && \
    cp /lib/x86_64-linux-gnu/libunwind.so.1 /build/llvm/llvm-linux-x86_64/lib

cp /lib/x86_64-linux-gnu/libncurses.so.6 /build/llvm/llvm-linux-x86_64/lib && \
    cp /lib/x86_64-linux-gnu/libform.so.6 /build/llvm/llvm-linux-x86_64/lib && \
    cp /lib/x86_64-linux-gnu/libtinfo.so.6 /build/llvm/llvm-linux-x86_64/lib && \
    cp /lib/x86_64-linux-gnu/libpanel.so.6 /build/llvm/llvm-linux-x86_64/lib

tar -cjSf toolchain.bz2 --transform "s%^llvm-linux-x86_64%llvm-clang-${CLANG_VERSION}-ubuntu-22.04-x86_64%" llvm-linux-x86_64