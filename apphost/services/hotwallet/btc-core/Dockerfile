FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90 as builder

WORKDIR /root

ENV BITCOIN_REPO=https://github.com/bitcoin/bitcoin.git
ENV BITCOIN_TAG=v31.0

RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    python3 \
    libevent-dev \
    libboost-dev \
    libsqlite3-dev \
    libzmq3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone $BITCOIN_REPO bitcoin

RUN cd bitcoin && \
    git fetch --all --tags --prune && \
    git checkout tags/$BITCOIN_TAG && \
    cmake -B build \
        -DBUILD_TESTS=OFF \
        -DBUILD_BENCH=OFF \
        -DWITH_GUI=OFF \
        -DWITH_ZMQ=OFF \
        -DENABLE_IPC=OFF \
        -DBUILD_BITCOIN_WALLET=ON && \
    cmake --build build -j$(nproc)

RUN strip /root/bitcoin/build/bin/bitcoind && \
    strip /root/bitcoin/build/bin/bitcoin-cli


FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90

RUN apt-get update && apt-get install -y --no-install-recommends \
    libevent-2.1-7 \
    libevent-pthreads-2.1-7 \
    libevent-extra-2.1-7 \
    libboost-system1.83.0 \
    libboost-filesystem1.83.0 \
    libboost-thread1.83.0 \
    libsqlite3-0 \
    jq \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /root/bitcoin/build/bin/bitcoind /usr/local/bin/
COPY --from=builder /root/bitcoin/build/bin/bitcoin-cli /usr/local/bin/

EXPOSE 18444 18443

# ubuntu:24.04 bringt UID 1000 (User "ubuntu") schon mit -> erst löschen, dann app anlegen
RUN userdel -r ubuntu && useradd -u 1000 -m app

# >>> HIER kommt der mkdir hin: NACH useradd, VOR "USER 1000" <<<
# Legt das Datadir an und übergibt es UID 1000, damit das leere Named-Volume
# beim ersten Start die Ownership 1000:1000 erbt (sonst kann der non-root-Prozess nicht schreiben)
RUN mkdir -p /home/app/.bitcoin && chown -R 1000:1000 /home/app

COPY src/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER 1000

CMD ["/usr/local/bin/entrypoint.sh"]