# syntax=docker/dockerfile:1
# ═══════════════════════════════════════════════════════════════════════════════
# Windows in Docker with Nested Virtualization Support
# ═══════════════════════════════════════════════════════════════════════════════
# This Dockerfile builds a container that runs Windows as a QEMU/KVM VM
# with full nested virtualization support, enabling:
# - Android Emulator (WHPX/Hyper-V backend)
# - Hyper-V nested VMs
# - Docker Desktop with Hyper-V backend
# - WSL2 with virtualization features
# ═══════════════════════════════════════════════════════════════════════════════

ARG VERSION_ARG="latest"
FROM scratch AS build-amd64

COPY --from=qemux/qemu:7.29 / /

ARG TARGETARCH
ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

RUN set -eu && \
    apt-get update && \
    apt-get --no-install-recommends -y install \
        samba \
        wimtools \
        dos2unix \
        cabextract \
        libxml2-utils \
        libarchive-tools \
        # Additional tools for nested virtualization debugging
        pciutils \
        procps && \
    wget "https://github.com/gershnik/wsdd-native/releases/download/v1.22/wsddn_1.22_${TARGETARCH}.deb" -O /tmp/wsddn.deb -q && \
    dpkg -i /tmp/wsddn.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --chmod=755 ./src /run/
COPY --chmod=755 ./assets /run/assets

ADD --chmod=664 https://github.com/qemus/virtiso-whql/releases/download/v1.9.49-0/virtio-win-1.9.49.tar.xz /var/drivers.txz

FROM dockurr/windows-arm:${VERSION_ARG} AS build-arm64
FROM build-${TARGETARCH}

ARG VERSION_ARG="0.00"
RUN echo "$VERSION_ARG" > /run/version

# ═══════════════════════════════════════════════════════════════════════════════
# Environment defaults for nested virtualization
# ═══════════════════════════════════════════════════════════════════════════════
# VMX=Y enables VMX/SVM passthrough to the guest
# HV=Y enables Hyper-V enlightenments for better performance
# These can be overridden at runtime via docker-compose environment variables
# ═══════════════════════════════════════════════════════════════════════════════

VOLUME /storage
EXPOSE 3389 8006

ENV VERSION="11"
ENV RAM_SIZE="4G"
ENV CPU_CORES="2"
ENV DISK_SIZE="64G"
# Enable nested virtualization by default
ENV VMX="Y"
ENV HV="Y"

ENTRYPOINT ["/usr/bin/tini", "-s", "/run/entry.sh"]
