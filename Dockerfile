FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
		apt-transport-https \
		ca-certificates \
		curl \
		gnupg \
		iproute2 \
		iputils-ping \
        iperf3 \
        iperf \
        git \
        build-essential \
        nasm \
        python3 \
        python3.10-venv \
        libnuma-dev \
        meson \
        ninja-build \
        python3-pyelftools \
        python3-pip \
        sudo \
        clang \
        cmake \
        openssl \
        libssl-dev \
        pkg-config \
        gcc-multilib \
        llvm \
        lld \
        m4 \
        libpcap-dev \
        python3-ply \
        zlib1g \
        zlib1g-dev \
        libelf-dev \
        python3 \
        pip \
        && rm -rf /var/lib/apt/lists/*

WORKDIR /
RUN git clone https://github.com/xdp-project/xdp-tools.git
WORKDIR /xdp-tools
RUN git checkout v1.2.9
RUN ./configure
# RUN make -C lib/libbpf/src PREFIX=/usr -j install
# RUN make CFLAGS+=-fpic; PREFIX=/usr make  -j install
RUN make -C lib/libbpf/src CFLAGS+=-fpic PREFIX=/usr -j install
RUN PREFIX=/usr make -j install
RUN echo "/lib/" >> /etc/ld.so.conf.d/x86_64-linux-gnu.conf
RUN echo "/lib64/" >> /etc/ld.so.conf.d/x86_64-linux-gnu.conf
RUN ldconfig

WORKDIR /
# RUN git clone https://github.com/FDio/vpp.git
WORKDIR /vpp/
# If there's a local version of VPP with developer changes then comment the git clone line above
# and uncomment the following line
COPY ./ /vpp/
RUN make build-release

# Reference https://fdio-vpp.readthedocs.io/en/latest/gettingstarted/developers/building.html
#CMD ["/usr/bin/vpp", "-c", "/etc/vpp/startup.conf"]
