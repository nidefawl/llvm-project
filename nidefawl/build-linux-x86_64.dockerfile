FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -yqq
RUN apt-get install -qqy --no-install-recommends sudo wget gnupg2 ca-certificates
# add user builder
RUN useradd -ms /bin/bash builder
WORKDIR /home/builder

# add user builder to sudoers
RUN echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc
RUN bash -c "echo 'deb https://apt.llvm.org/jammy/ llvm-toolchain-jammy-18 main' >> /etc/apt/sources.list"
RUN apt-get update -yqq
RUN apt-get install -qqy --no-install-recommends \
    autoconf-archive autopoint build-essential automake bzip2 clang-18 python3  \
    clang-tidy-18 curl e2fslibs-dev file gettext git gnupg2 less libasound2-dev \
    libatomic1 libattr1-dev libbsd-dev libbsd0 libc++-18-dev libc++abi-18-dev   \
    libedit-dev libgtk-3-dev liblzma-dev libncurses-dev libncursesw6 libssl-dev \
    libtinfo6 libtool libunwind-18-dev libx11-dev libxcursor-dev libxi-dev nano \
    libxinerama-dev libxml2 libxrandr-dev libltdl-dev lld-18 nsis pkg-config    \
    python3-dev python3-distutils python3-pip swig unzip unzip yasm wget zip    \
    rsync libclang-rt-18-dev

    # enfore lld-18 as linker
RUN ln -s /usr/bin/lld-18 /usr/local/bin/ld

RUN wget -nv https://github.com/ninja-build/ninja/releases/download/v1.12.0/ninja-linux.zip
RUN unzip ninja-linux.zip -d /usr/local/bin/ && rm ninja-linux.zip

# Manually install a newer version of CMake; this is needed since building
# LLVM requires CMake 3.13.4, while Ubuntu 18.04 ships with 3.10.2. If
# updating to a newer distribution, this can be dropped.
RUN wget -nv https://github.com/Kitware/CMake/releases/download/v3.29.3/cmake-3.29.3-linux-$(uname -m).tar.gz
RUN tar -zxf cmake-*.tar.gz && rm cmake-*.tar.gz
RUN mv cmake-* /opt/cmake && chown -R root:root /opt/cmake

ENV PATH=/opt/cmake/bin:$PATH:/home/builder/.local/bin


RUN git config --global user.name "LLVM MinGW" && \
    git config --global user.email root@localhost && \
    git config --global init.defaultBranch main && \
    git config --global advice.detachedHead false

RUN mkdir -p /build && chown -R builder:builder /build

# switch to user builder
USER builder
RUN mkdir -p /build/llvm
WORKDIR /build/llvm
    
RUN pip3 install pygments pyyaml
        

ARG GIT_REPO=https://github.com/nidefawl/llvm-project.git
ARG GIT_BRANCH=llvm-dev
RUN git clone --depth=1 --branch=$GIT_BRANCH --single-branch $GIT_REPO llvm-project

COPY build-linux-x86_64.sh .

RUN ./build-linux-x86_64.sh

ENV LD_LIBRARY_PATH=/build/llvm/llvm-linux-x86_64/lib/x86_64-unknown-linux-gnu
ENV PATH=/build/llvm/llvm-linux-x86_64/bin:$PATH
