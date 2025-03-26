FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies, profiling tools, OpenMP and MPI
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
    libomp-dev \
    libopenmpi-dev \
    openmpi-bin \
    openmpi-common \
    bc \
    doxygen \
    graphviz \
    && rm -rf /var/lib/apt/lists/*

# Install additional Python tools
RUN pip3 install matplotlib numpy pandas

# Set working directory
WORKDIR /app

# Add environment variables for performance tools, OpenMP and MPI
ENV PATH="/app:/usr/lib/openmpi/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/openmpi/lib:${LD_LIBRARY_PATH:-}"
# Default to maximum available cores for OpenMP
ENV OMP_NUM_THREADS=0
# Add OpenMP configurations for better performance
ENV OMP_PROC_BIND=true
ENV OMP_PLACES=cores

# Create a wrapper script for perf (since it requires root in Docker)
RUN echo '#!/bin/bash\n\
if [ "$1" = "record" ] || [ "$1" = "stat" ]; then\n\
  echo "Running perf with simulated privileges in Docker..."\n\
  exec /usr/bin/perf "$@"\n\
else\n\
  exec /usr/bin/perf "$@"\n\
fi' > /usr/local/bin/perf-docker && \
    chmod +x /usr/local/bin/perf-docker

# Verify MPI installation
RUN which mpirun && mpirun --version

# Set default command
CMD ["/bin/bash"]