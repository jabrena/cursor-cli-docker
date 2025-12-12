# Use Ubuntu as the base image
FROM ubuntu:22.04

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libcurl4 \
    wget \
    git \
    sudo \
    tree \
    ca-certificates \
    gnupg \
    build-essential \
    unzip \
    zip \
    && rm -rf /var/lib/apt/lists/*

# Install SDKMAN for Java version management
RUN curl -s "https://get.sdkman.io" | bash

# Source SDKMAN and install SDKs as developer user
RUN bash -c "source ${SDKMAN_DIR}/bin/sdkman-init.sh && \
    sdk install java 25.0.1-graalce && \
    sdk install maven 3.9.10 && \
    sdk install gradle 9.2.1 && \
    sdk install jbang 0.135.0 && \
    sdk default java 25.0.1-graalce && \
    sdk default maven 3.9.10 && \
    sdk default gradle 9.2.1 && \
    sdk default jbang 0.135.0"

# Add SDKMAN to PATH and source it in bash profile
ENV SDKMAN_DIR="/root/.sdkman"
ENV JAVA_HOME="/root/.sdkman/candidates/java/current"
RUN echo "source $SDKMAN_DIR/bin/sdkman-init.sh" >> /root/.bashrc

# Install the Cursor CLI using the official installation script
RUN curl https://cursor.com/install -fsS | bash

# Add the installation directory and SDKMAN to the system's PATH
ENV PATH="/root/.local/bin:/root/.sdkman/candidates/java/current/bin:${PATH}"

# Set shell environment variable
ENV SHELL=/bin/bash

# Set CURSOR_AGENT environment variable to enable agent mode
ENV CURSOR_AGENT=1

# Set the Cursor API key as an environment variable (should be provided at runtime)
# Example: docker run -e CURSOR_API_KEY=your_key_here
ENV CURSOR_API_KEY=""

# Set the prompt parameter (should be provided at runtime)
# Example: docker run -e PROMPT="your prompt text here"
ENV PROMPT=""

# Set output format for headless mode (text, json, stream-json)
# Example: docker run -e OUTPUT_FORMAT=text
ENV OUTPUT_FORMAT="text"

# Set the git repository parameter (should be provided at runtime)
# Example: docker run -e GIT_REPOSITORY=https://github.com/user/repo.git
ENV GIT_REPOSITORY=""

# Create a working directory for cursor-agent to operate in
WORKDIR /workspace

# Ensure the working directory has proper permissions
RUN chmod 755 /workspace

# Verify the installations
RUN cursor-agent --version || true && \
    bash -c "source /root/.sdkman/bin/sdkman-init.sh && java -version" && \
    git --version

# Set the default command to clone repository if provided, then run cursor-agent
# If GIT_REPOSITORY is set, clone it to /workspace before running cursor-agent
# Use -p (--print) for non-interactive scripting and automation
# Use --force to allow file modifications in scripts
# Use --output-format for structured output (text, json, stream-json)
# Reference: https://cursor.com/docs/cli/headless
CMD if [ -n "$GIT_REPOSITORY" ]; then \
      echo "Cloning repository: $GIT_REPOSITORY into /workspace"; \
      find /workspace -mindepth 1 -delete 2>/dev/null || true; \
      git clone "$GIT_REPOSITORY" /workspace || (echo "Failed to clone repository" && exit 1); \
      echo "Repository cloned successfully"; \
    fi && \
    if [ -n "$PROMPT" ]; then \
      cursor-agent -p --force --output-format "$OUTPUT_FORMAT" "$PROMPT"; \
    else \
      cursor-agent --help; \
    fi
