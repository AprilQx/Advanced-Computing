FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies and profiling tools
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    g++ \
    gdb \
    valgrind \
    binutils \
    linux-tools-generic \
    python3 \
    python3-pip \
    git \
    vim \
    htop \
    google-perftools \
    libgoogle-perftools-dev \
    graphviz \
    kcachegrind \
    heaptrack \
    && rm -rf /var/lib/apt/lists/*

# Install additional Python tools
RUN pip3 install matplotlib numpy pandas

# Set working directory
WORKDIR /app

# Add environment variables for performance tools
ENV PATH="/app:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"

# Create a wrapper script for perf (since it requires root in Docker)
RUN echo '#!/bin/bash\n\
if [ "$1" = "record" ] || [ "$1" = "stat" ]; then\n\
  echo "Running perf with simulated privileges in Docker..."\n\
  exec /usr/bin/perf "$@"\n\
else\n\
  exec /usr/bin/perf "$@"\n\
fi' > /usr/local/bin/perf-docker && \
    chmod +x /usr/local/bin/perf-docker

# Set default command
CMD ["/bin/bash"]