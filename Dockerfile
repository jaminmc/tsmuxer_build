FROM ubuntu:24.04
LABEL org.opencontainers.image.description="Build environment for tsMuxer with Qt6 and C++20 support"

ENV TZ=Europe/London
ENV DEBIAN_FRONTEND=noninteractive

# ============================================================================
# Core build dependencies for tsMuxer Linux build
# ============================================================================
RUN apt-get update && apt-get install -y \
    nano \
    software-properties-common \
    build-essential \
    g++ \
    libc6-dev \
    libfreetype6-dev \
    zlib1g-dev \
    clang \
    git \
    patch \
    lzma-dev \
    libxml2-dev \
    libssl-dev \
    python3 \
    curl \
    wget \
    openssl \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    xz-utils \
    bzip2 \
    gperf \
    bison \
    flex \
    texinfo \
    help2man \
    libncurses-dev \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Install Qt 6.7+ for Linux using aqtinstall (Ubuntu 24.04 only has Qt 6.4)
# ============================================================================
# Use latest Qt6 available via aqtinstall (check: aqt list-qt linux desktop)
# MXE provides Qt 6.10.2 for Windows - use closest available for Linux
ENV QT_VERSION=6.8.2
ENV QT_PATH=/opt/qt
RUN apt-get update && apt-get install -y \
    python3-pip \
    libxcb1-dev \
    libxcb-cursor0 \
    libxcb-glx0-dev \
    libxcb-keysyms1-dev \
    libxcb-image0-dev \
    libxcb-shm0-dev \
    libxcb-icccm4-dev \
    libxcb-sync-dev \
    libxcb-xfixes0-dev \
    libxcb-shape0-dev \
    libxcb-randr0-dev \
    libxcb-render-util0-dev \
    libxcb-xinerama0-dev \
    libxcb-xkb-dev \
    libxkbcommon-dev \
    libxkbcommon-x11-dev \
    libegl1-mesa-dev \
    libfontconfig1-dev \
    libinput-dev \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --break-system-packages aqtinstall \
    && aqt install-qt linux desktop ${QT_VERSION} linux_gcc_64 \
        --outputdir ${QT_PATH} \
        -m qtmultimedia qtshadertools

ENV PATH=${QT_PATH}/${QT_VERSION}/gcc_64/bin:${PATH}
ENV CMAKE_PREFIX_PATH=${QT_PATH}/${QT_VERSION}/gcc_64
ENV LD_LIBRARY_PATH=${QT_PATH}/${QT_VERSION}/gcc_64/lib

# ============================================================================
# Install Linux tools required to build tsMuxer and create ZIP for distribution
# ============================================================================
RUN apt-get update && apt-get install -y \
    cmake \
    ninja-build \
    zip \
    file \
    patchelf \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Install linuxdeploy and the Qt plugin for AppImage creation
# ============================================================================
RUN curl -sLo /usr/local/bin/linuxdeploy-x86_64.AppImage \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage" && \
    curl -sLo /usr/local/bin/linuxdeploy-plugin-qt-x86_64.AppImage \
    "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage" && \
    chmod +x /usr/local/bin/linuxdeploy-x86_64.AppImage && \
    chmod +x /usr/local/bin/linuxdeploy-plugin-qt-x86_64.AppImage

# Fix for running AppImage in Docker containers (disable magic bytes check)
RUN dd if=/dev/zero of=/usr/local/bin/linuxdeploy-plugin-qt-x86_64.AppImage conv=notrunc bs=1 count=3 seek=8 && \
    dd if=/dev/zero of=/usr/local/bin/linuxdeploy-x86_64.AppImage conv=notrunc bs=1 count=3 seek=8

# Create Qt6 plugin directories for AppImage
RUN mkdir -p /usr/lib/x86_64-linux-gnu/qt6/plugins/mediaservice && \
    mkdir -p /usr/lib/x86_64-linux-gnu/qt6/plugins/audio

# ============================================================================
# Setup osxcross for macOS cross-compilation
# ============================================================================
ENV OSXCROSS_ROOT=/usr/lib/osxcross
ENV MACOSX_DEPLOYMENT_TARGET=15.0
ENV UNATTENDED=1

# Install osxcross build dependencies
RUN apt-get update && apt-get install -y \
    llvm \
    clang \
    libxml2-dev \
    uuid-dev \
    libssl-dev \
    libbz2-dev \
    zlib1g-dev \
    cpio \
    liblzma-dev \
    && rm -rf /var/lib/apt/lists/*

# Clone and build osxcross
RUN git clone https://github.com/tpoechtrager/osxcross.git ${OSXCROSS_ROOT}-src

# Note: You need to provide the macOS SDK. Download from Apple or use xcode-select.
# Place the SDK tarball (e.g., MacOSX14.5.sdk.tar.xz) in the tarballs directory.
# For CI/CD, you may need to build and cache the SDK separately.
# 
# Example to package SDK on a Mac:
#   cd /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs
#   tar -cJf MacOSX14.5.sdk.tar.xz MacOSX14.5.sdk
#
# When building, pass MACOS_SDK_VERSION to match your SDK version:
#   docker build --build-arg MACOS_SDK_URL="..." --build-arg MACOS_SDK_VERSION="14.5" .

# Build osxcross (SDK must be provided at build time via build arg or volume mount)
ARG MACOS_SDK_URL=""
ARG MACOS_SDK_VERSION="14.5"
RUN if [ -n "${MACOS_SDK_URL}" ]; then \
        curl -fSLo ${OSXCROSS_ROOT}-src/tarballs/MacOSX${MACOS_SDK_VERSION}.sdk.tar.xz "${MACOS_SDK_URL}" && \
        cd ${OSXCROSS_ROOT}-src/tarballs && \
        mkdir -p tmp && cd tmp && \
        tar -xf ../MacOSX${MACOS_SDK_VERSION}.sdk.tar.xz && \
        if [ -d "MacOSX.sdk" ] && [ ! -d "MacOSX${MACOS_SDK_VERSION}.sdk" ]; then \
            mv MacOSX.sdk MacOSX${MACOS_SDK_VERSION}.sdk; \
        fi && \
        tar -cJf ../MacOSX${MACOS_SDK_VERSION}.sdk.tar.xz MacOSX${MACOS_SDK_VERSION}.sdk && \
        cd .. && rm -rf tmp; \
    fi

RUN cd ${OSXCROSS_ROOT}-src && \
    if [ -f tarballs/MacOSX*.sdk.tar.xz ]; then \
        UNATTENDED=1 ./build.sh && \
        mv target ${OSXCROSS_ROOT} && \
        rm -rf ${OSXCROSS_ROOT}-src; \
    else \
        echo "Warning: No macOS SDK found. OSX cross-compilation will not be available." && \
        mkdir -p ${OSXCROSS_ROOT}/bin && \
        rm -rf ${OSXCROSS_ROOT}-src; \
    fi

ENV PATH=${OSXCROSS_ROOT}/bin:${OSXCROSS_ROOT}/tools:$PATH

# Install macOS dependencies via osxcross-macports (if osxcross was built)
RUN if [ -f ${OSXCROSS_ROOT}/bin/osxcross-macports ]; then \
        ${OSXCROSS_ROOT}/bin/osxcross-macports install freetype && \
        ${OSXCROSS_ROOT}/bin/osxcross-macports install zlib; \
    fi

# Install Qt for macOS cross-compilation (x86_64 and arm64 for universal binaries)
ENV QT_MAC_PATH=/opt/qt-mac
RUN if [ -f ${OSXCROSS_ROOT}/bin/o64-clang ]; then \
        aqt install-qt mac desktop ${QT_VERSION} clang_64 \
            --outputdir ${QT_MAC_PATH} \
            -m qtmultimedia qtshadertools; \
    fi

ENV QT_MAC_X64=${QT_MAC_PATH}/${QT_VERSION}/macos

# Setup XAR for osxcross (required for code signing)
RUN git clone https://github.com/tpoechtrager/xar.git /tmp/xar && \
    cd /tmp/xar/xar && \
    ./autogen.sh --prefix=${OSXCROSS_ROOT} && \
    make && make install && \
    rm -rf /tmp/xar

# Create static library symlinks for osxcross (if macports packages were installed)
RUN if [ -d ${OSXCROSS_ROOT}/macports/pkgs/opt/local/lib ]; then \
        cd ${OSXCROSS_ROOT}/macports/pkgs/opt/local/lib && \
        for lib in libfreetype.a libz.a libbz2.a libpng.a libpng16.a; do \
            [ -f "$lib" ] && ln -sf "$lib" "${lib%.a}-static.a" || true; \
        done; \
    fi

# ============================================================================
# Setup MXE for Windows cross-compilation
# ============================================================================
ENV MXE_ROOT=/usr/lib/mxe
ENV MXE_TARGETS="x86_64-w64-mingw32.static i686-w64-mingw32.static"

# Install MXE build dependencies
RUN apt-get update && apt-get install -y \
    autopoint \
    gettext \
    intltool \
    libgdk-pixbuf-2.0-dev \
    libtool-bin \
    lzip \
    p7zip-full \
    python-is-python3 \
    python3-mako \
    python3-pip \
    ruby \
    scons \
    unzip \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --break-system-packages mako

# Clone MXE repository
RUN git clone https://github.com/mxe/mxe.git ${MXE_ROOT}

# Build MXE toolchain and base libraries first
# This takes a long time on first build
WORKDIR ${MXE_ROOT}
RUN make MXE_TARGETS="${MXE_TARGETS}" \
    MXE_PLUGIN_DIRS="plugins/gcc14" \
    cc cmake freetype zlib

# Build MXE Qt6 separately - dump log on failure for debugging
RUN LD_LIBRARY_PATH= make MXE_TARGETS="${MXE_TARGETS}" \
    MXE_PLUGIN_DIRS="plugins/gcc14" \
    qt6-qtbase qt6-qttools qt6-qtmultimedia \
    || (echo "=== BUILD FAILED ===" && \
        for f in ${MXE_ROOT}/log/qt6-qtbase*; do \
            echo "=== $f ===" && tail -200 "$f" 2>/dev/null; \
        done && false)

# Add MXE to PATH
ENV PATH=${MXE_ROOT}/usr/bin:$PATH

WORKDIR /

# ============================================================================
# Final cleanup and verification
# ============================================================================
RUN apt-get update && apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Verify installations
RUN echo "=== Build Environment ===" && \
    echo "GCC version:" && g++ --version | head -1 && \
    echo "CMake version:" && cmake --version | head -1 && \
    echo "Qt6 version (Linux):" && (${QT_PATH}/${QT_VERSION}/gcc_64/bin/qmake --version 2>/dev/null | head -2 || echo "Not installed") && \
    echo "Qt6 version (macOS):" && (ls ${QT_MAC_X64}/bin/qmake* 2>/dev/null && echo "Qt ${QT_VERSION}" || echo "Not installed") && \
    echo "MXE Qt6 version:" && (ls ${MXE_ROOT}/usr/x86_64-w64-mingw32.static/qt6/bin/qmake* 2>/dev/null && echo "Qt6 installed" || echo "Qt6 not found") && \
    echo "MXE targets:" && ls ${MXE_ROOT}/usr/bin/*-g++ 2>/dev/null | xargs -I{} basename {} | sed 's/-g++//' || echo "MXE not built" && \
    echo "osxcross:" && (${OSXCROSS_ROOT}/bin/o64-clang --version 2>/dev/null | head -1 || echo "osxcross not built")
