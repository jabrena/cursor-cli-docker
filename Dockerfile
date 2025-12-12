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

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install SDKMAN for Java version management
RUN curl -s "https://get.sdkman.io" | bash

# Set SDKMAN directory before using it
ENV SDKMAN_DIR="/root/.sdkman"

# Source SDKMAN and install SDKs
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

# Set the model parameter for cursor-agent (should be provided at runtime)
# Example: docker run -e MODEL=auto
ENV MODEL=""

# Set the git repository parameter (should be provided at runtime)
# Example: docker run -e GIT_REPOSITORY=https://github.com/user/repo.git
ENV GIT_REPOSITORY=""

# Set GitHub credentials for git operations (should be provided at runtime)
# Example: docker run -e GITHUB_TOKEN=your_token_here
ENV GITHUB_TOKEN=""
ENV GITHUB_ACTOR=""
ENV GITHUB_REPOSITORY=""

# Set PR creation flag (should be provided at runtime)
# Example: docker run -e PR=true to enable PR creation, -e PR=false to disable
ENV PR="false"

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
      cd /workspace && \
      if [ -n "$GITHUB_TOKEN" ]; then \
        echo "Configuring git credentials for authentication"; \
        git config --global user.name "${GITHUB_ACTOR:-cursor-agent}" && \
        git config --global user.email "${GITHUB_ACTOR:-cursor-agent}@users.noreply.github.com" && \
        git config --global credential.helper store && \
        echo "https://${GITHUB_ACTOR:-x-access-token}:${GITHUB_TOKEN}@github.com" > /root/.git-credentials && \
        if [ -n "$GITHUB_REPOSITORY" ]; then \
          git remote set-url origin "https://${GITHUB_ACTOR:-x-access-token}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" || true; \
        fi && \
        echo "Git credentials configured successfully"; \
      fi; \
    fi && \
    if [ -n "$PROMPT" ]; then \
      echo "=== User Prompt:==="; \
      echo ""; \
      echo "$PROMPT"; \
      echo ""; \
      echo "=== Cursor Agent Execution:==="; \
      echo ""; \
      if [ -n "$MODEL" ]; then \
        echo "Model: $MODEL"; \
        cursor-agent -p --force --output-format "$OUTPUT_FORMAT" --model "$MODEL" "$PROMPT"; \
      else \
        echo "Model: (not set)"; \
        cursor-agent -p --force --output-format "$OUTPUT_FORMAT" "$PROMPT"; \
      fi; \
      if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPOSITORY" ] && [ "$PR" = "true" ]; then \
        cd /workspace && \
        git fetch origin 2>/dev/null || true && \
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "") && \
        DEFAULT_BRANCH=$(git remote show origin | grep "HEAD branch" | cut -d" " -f5 || \
                         git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || \
                         (git ls-remote --symref origin HEAD | grep -oP 'refs/heads/\K[^\t]+' || echo "main")) && \
        if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ] && [ "$CURRENT_BRANCH" != "HEAD" ]; then \
          echo ""; \
          echo "=== Creating Pull Request:==="; \
          echo "Branch: $CURRENT_BRANCH"; \
          echo "Base: $DEFAULT_BRANCH"; \
          PR_TITLE="Automated PR: Changes from cursor-agent" && \
          PR_BODY="This PR was automatically created by cursor-agent." && \
          if gh pr create --title "$PR_TITLE" --body "$PR_BODY" --base "$DEFAULT_BRANCH" --head "$CURRENT_BRANCH" --repo "$GITHUB_REPOSITORY" 2>&1; then \
            PR_URL=$(gh pr view "$CURRENT_BRANCH" --repo "$GITHUB_REPOSITORY" --json url -q .url 2>/dev/null || echo "") && \
            if [ -n "$PR_URL" ]; then \
              echo "Pull Request created successfully!"; \
              echo "PR URL: $PR_URL"; \
            else \
              echo "Pull Request created successfully!"; \
              echo "PR URL: https://github.com/$GITHUB_REPOSITORY/pull/new/$CURRENT_BRANCH"; \
            fi; \
          else \
            PR_EXISTS=$(gh pr list --head "$CURRENT_BRANCH" --repo "$GITHUB_REPOSITORY" --json number -q '.[0].number' 2>/dev/null || echo "") && \
            if [ -n "$PR_EXISTS" ]; then \
              echo "Pull Request already exists for branch: $CURRENT_BRANCH"; \
              echo "PR URL: https://github.com/$GITHUB_REPOSITORY/pull/$PR_EXISTS"; \
            else \
              echo "Failed to create PR. You can create it manually at: https://github.com/$GITHUB_REPOSITORY/pull/new/$CURRENT_BRANCH"; \
            fi; \
          fi; \
        else \
          echo "No feature branch detected or already on default branch. Skipping PR creation."; \
        fi; \
      fi; \
    else \
      cursor-agent --help; \
    fi
