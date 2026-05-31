# Loki - Authorized Internal Penetration Testing Service
# Based on Kali Linux for authorized security testing of Asgard defenses
# Target surfaces: API injection, model prompt injection, data exfiltration
# All traffic marked as test via X-Loki-Test header

FROM kalilinux/kali:latest

LABEL maintainer="Asgard Security Team"
LABEL description="Loki - Internal authorized penetration testing service for Asgard"

ENV DEBIAN_FRONTEND=noninteractive

# Install core penetration testing tools for Asgard-specific targets
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Networking & reconnaissance
    curl \
    wget \
    net-tools \
    netcat-openbsd \
    dnsutils \
    nmap \
    # API testing & fuzzing
    sqlmap \
    sqlparse \
    jq \
    httpie \
    # Python for custom exploit development
    python3 \
    python3-pip \
    python3-dev \
    git \
    # LLM/Prompt injection testing
    # (custom tools mounted via ConfigMap)
    # Cryptography & encoding
    openssl \
    xxd \
    # Process & system tools
    procps \
    vim \
    nano \
    less \
    # Shell
    bash \
    zsh \
    && rm -rf /var/lib/apt/lists/*

# Install Python security testing libraries
RUN pip3 install --no-cache-dir \
    requests \
    paramiko \
    pycryptodome \
    cryptography \
    beautifulsoup4 \
    lxml \
    websocket-client \
    pyjwt

WORKDIR /opt/loki

# Copy test scripts and payloads (injected via ConfigMap at runtime)
# /opt/loki/scripts/ will contain custom exploit/test code
# /opt/loki/payloads/ will contain test payloads

# Default to bash shell
ENTRYPOINT ["/bin/bash"]
CMD ["-l"]
