FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -yqq
RUN apt-get install -qqy --no-install-recommends sudo wget gnupg2 ca-certificates.
# add user builder
RUN useradd -ms /bin/bash builder
# add user builder to sudoers
RUN echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
# switch to user builder
USER builder
ENV PATH=/opt/cmake/bin:$PATH:/home/builder/.local/bin
WORKDIR /home/builder

RUN wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
RUN sudo bash -c "echo 'deb https://apt.llvm.org/jammy/ llvm-toolchain-jammy main' >> /etc/apt/sources.list"
RUN sudo apt-get update -yqq
RUN sudo apt-get install -qqy --no-install-recommends \
    autoconf-archive autopoint build-essential automake bzip2 clang-16 python3  \
    clang-tidy-16 curl e2fslibs-dev file gettext git gnupg2 less libasound2-dev \
    libatomic1 libattr1-dev libbsd-dev libbsd0 libc++-16-dev libc++abi-16-dev   \
    libedit-dev libgtk-3-dev liblzma-dev libncurses-dev libncursesw6 libssl-dev \
    libtinfo6 libtool libunwind-16-dev libx11-dev libxcursor-dev libxi-dev nano \
    libxinerama-dev libxml2 libxrandr-dev libltdl-dev lld-16 nsis pkg-config    \
    python3-dev python3-distutils python3-pip swig unzip unzip yasm wget zip    \
    rsync

RUN pip3 install pygments pyyaml

# enfore lld-16 as linker
RUN sudo ln -s /usr/bin/lld-16 /usr/local/bin/ld

RUN wget -nv https://github.com/ninja-build/ninja/releases/download/v1.11.1/ninja-linux.zip
RUN sudo unzip ninja-linux.zip -d /usr/local/bin/ && rm ninja-linux.zip

# Manually install a newer version of CMake; this is needed since building
# LLVM requires CMake 3.13.4, while Ubuntu 18.04 ships with 3.10.2. If
# updating to a newer distribution, this can be dropped.
RUN wget -nv https://github.com/Kitware/CMake/releases/download/v3.25.0-rc4/cmake-3.25.0-rc4-linux-$(uname -m).tar.gz
RUN tar -zxf cmake-*.tar.gz && rm cmake-*.tar.gz
RUN sudo mv cmake-* /opt/cmake && sudo chown -R root:root /opt/cmake


RUN sudo git config --global user.name "LLVM MinGW" && \
    sudo git config --global user.email root@localhost && \
    sudo git config --global init.defaultBranch main && \
    sudo git config --global advice.detachedHead false

RUN sudo mkdir -p /build && sudo chown -R builder:builder /build && \
    mkdir -p /build/llvm

WORKDIR /build/llvm
ARG GIT_REPO=https://github.com/nidefawl/llvm-project.git
ARG GIT_BRANCH=llvm-dev
RUN git clone --depth=1 --branch=$GIT_BRANCH --single-branch $GIT_REPO llvm-project

COPY build-linux-x86_64.sh .

RUN ./build-linux-x86_64.sh

ENV LD_LIBRARY_PATH=/build/llvm/llvm-linux-x86_64/lib/x86_64-unknown-linux-gnu
ENV PATH=/build/llvm/llvm-linux-x86_64/bin:$PATH

# steal the local runtimes and provide them for packaging, what is the worst that could happen?
# in theory this should work
RUN cp /lib/x86_64-linux-gnu/libc++abi.so.1 /build/llvm/llvm-linux-x86_64/lib && \
    cp /lib/x86_64-linux-gnu/libc++.so.1 /build/llvm/llvm-linux-x86_64/lib && \
    cp /lib/x86_64-linux-gnu/libunwind.so.1 /build/llvm/llvm-linux-x86_64/lib

RUN tar -cjSf toolchain.bz2 --transform "s%^llvm-linux-x86_64%llvm-clang-ubuntu-22.04-x86_64%" llvm-linux-x86_64

RUN cp /lib/x86_64-linux-gnu/libncurses.so.6 /build/llvm/llvm-linux-x86_64/lib && \
    cp /lib/x86_64-linux-gnu/libform.so.6 /build/llvm/llvm-linux-x86_64/lib && \
    cp /lib/x86_64-linux-gnu/libtinfo.so.6 /build/llvm/llvm-linux-x86_64/lib && \
    cp /lib/x86_64-linux-gnu/libpanel.so.6 /build/llvm/llvm-linux-x86_64/lib