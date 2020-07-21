#!/bin/bash

set -euxo pipefail

CMAKE_FLAGS="-DCMAKE_INSTALL_PREFIX=$PREFIX -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release"

if [[ "$target_platform" == linux* ]]; then
    # CFLAGS
    # JRG: Had to add -ldl to prevent linking errors (dlopen, etc)
    MINIMAL_CFLAGS+=" -O3 -ldl"
    CFLAGS+=" $MINIMAL_CFLAGS"
    CXXFLAGS+=" $MINIMAL_CFLAGS"

    # Use GCC
    CMAKE_FLAGS+=" -DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX"

    # CUDA_HOME is defined by nvcc metapackage
    CMAKE_FLAGS+=" -DCUDA_TOOLKIT_ROOT_DIR=${CUDA_HOME}"
    # From: https://github.com/floydhub/dl-docker/issues/59
    CMAKE_FLAGS+=" -DCMAKE_LIBRARY_PATH=${CUDA_HOME}/lib64/stubs"
    # CUDA tests won't build, disable for now
    # See https://github.com/openmm/openmm/issues/2258#issuecomment-462223634
    CMAKE_FLAGS+=" -DOPENMM_BUILD_CUDA_TESTS=OFF"

elif [[ "$target_platform" == osx* ]]; then
    CMAKE_FLAGS+=" -DCMAKE_OSX_SYSROOT=${CONDA_BUILD_SYSROOT}"
    CMAKE_FLAGS+=" -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++"
    CMAKE_FLAGS+=" -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET}"
fi

# Set location for FFTW3 on both linux and mac
CMAKE_FLAGS+=" -DFFTW_INCLUDES=${PREFIX}/include/"
CMAKE_FLAGS+=" -DFFTW_LIBRARY=${PREFIX}/lib/libfftw3f${SHLIB_EXT}"
CMAKE_FLAGS+=" -DFFTW_THREADS_LIBRARY=${PREFIX}/lib/libfftw3f_threads${SHLIB_EXT}"

# OpenCL ICD
if [[ "$opencl_impl" == icdloader ]]; then
    CMAKE_FLAGS+=" -DOPENCL_INCLUDE_DIR=${PREFIX}/include/"
    CMAKE_FLAGS+=" -DOPENCL_LIBRARY=${PREFIX}/lib/libOpenCL${SHLIB_EXT}"
elif [[ "$target_platform" == linux* ]]; then
    # If we don't use the ICD loader, on Linux we link to Nvidia's ICD
    # CUDA_HOME must be set!
    CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
    CMAKE_FLAGS+=" -DOPENCL_INCLUDE_DIR=${CUDA_HOME}/include/"
    CMAKE_FLAGS+=" -DOPENCL_LIBRARY=${CUDA_HOME}/lib/libOpenCL${SHLIB_EXT}"
elif [[ "$target_platform" == osx* ]]; then
    # If we don't use the ICD loader, on MacOS we link to Apple's ICD
    CMAKE_FLAGS+=" -DOPENCL_INCLUDE_DIR=/System/Library/Frameworks/OpenCL.framework/OpenCL/include/"
    CMAKE_FLAGS+=" -DOPENCL_LIBRARY=/System/Library/Frameworks/OpenCL.framework/OpenCL/lib/libOpenCL${SHLIB_EXT}"
fi

# Build in subdirectory and install.
mkdir -p build
cd build
cmake ${CMAKE_FLAGS} ${SRC_DIR}
make -j$CPU_COUNT
make -j$CPU_COUNT install PythonInstall

# Put examples into an appropriate subdirectory.
mkdir $PREFIX/share/openmm/
mv $PREFIX/examples $PREFIX/share/openmm/

# Fix some overlinking warnings/errors
for lib in ${PREFIX}/lib/plugins/*${SHLIB_EXT}; do
    ln -s $lib ${PREFIX}/lib/$(basename $lib) || true
done