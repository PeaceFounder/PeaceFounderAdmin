# Containerfile for PeaceFounder service
FROM docker.io/julia:1.11

# Application in /opt/peacefounder
WORKDIR /opt/peacefounder

# Copy and install Julia dependencies first (better caching)
COPY Project.toml Manifest.toml ./
RUN julia --project=. -e "using Pkg; Pkg.instantiate()"

# Copy application code
COPY . ./

# Auto-detect architecture and set CPU target, then precompile
RUN julia --project=. -e ' \
    arch = Sys.ARCH; \
    cpu_target = if arch == :x86_64; \
        "generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)"; \
    elseif arch == :aarch64; \
        "generic;apple-m1"; \
    else; \
        "generic"; \
    end; \
    println("Detected Julia architecture: $arch"); \
    println("Using JULIA_CPU_TARGET: $cpu_target"); \
    using Pkg; \
    withenv("JULIA_CPU_TARGET" => cpu_target) do; \
        Pkg.precompile(); \
    end; \
    println("Precompilation completed with optimized target!"); \
'

# Use /home/peacefounder for data
ENV USER_DATA=/home/peacefounder
ENV PEACEFOUNDER_ADMIN_HOST="0.0.0.0"

# Create home directory structure
RUN mkdir -p /home/peacefounder

# Admin panel (localhost only) and entry point
EXPOSE 3221 4584

ENTRYPOINT ["julia", "--project=.", "main.jl"]
CMD [] # Containerfile for PeaceFounder service