#!/bin/bash
set -e

# Script to create PR with changes (equivalent to lines 47-108 of agent-on-demand.yml)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get repository info - prefer GITHUB_REPOSITORY env var (from GitHub Actions), otherwise parse from git remote
if [ -n "$GITHUB_REPOSITORY" ]; then
    GITHUB_REPO="$GITHUB_REPOSITORY"
    echo -e "${GREEN}Repository (from GITHUB_REPOSITORY): $GITHUB_REPO${NC}"
else
    REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -z "$REPO_URL" ]; then
        echo -e "${RED}Error: No git remote 'origin' found and GITHUB_REPOSITORY not set${NC}"
        exit 1
    fi
    
    # Extract owner/repo from various URL formats
    if [[ "$REPO_URL" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
        REPO_OWNER="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]%.git}"
        GITHUB_REPO="$REPO_OWNER/$REPO_NAME"
    else
        echo -e "${RED}Error: Could not parse repository from remote URL: $REPO_URL${NC}"
        exit 1
    fi
    echo -e "${GREEN}Repository (from git remote): $GITHUB_REPO${NC}"
fi

# Get tokens from environment
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
PAT_TOKEN="${PAT_TOKEN:-}"
AUTH_TOKEN="${PAT_TOKEN:-$GITHUB_TOKEN}"

if [ -z "$AUTH_TOKEN" ]; then
    echo -e "${RED}Error: GITHUB_TOKEN or PAT_TOKEN must be set${NC}"
    exit 1
fi

# Get default branch - prefer GITHUB_BASE_REF or use gh CLI, otherwise parse from git
if [ -n "$GITHUB_BASE_REF" ]; then
    DEFAULT_BRANCH="$GITHUB_BASE_REF"
    echo -e "${GREEN}Default branch (from GITHUB_BASE_REF): $DEFAULT_BRANCH${NC}"
elif command -v gh &> /dev/null && [ -n "$GITHUB_REPO" ]; then
    DEFAULT_BRANCH=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "main")
    echo -e "${GREEN}Default branch (from gh CLI): $DEFAULT_BRANCH${NC}"
else
    DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
    echo -e "${GREEN}Default branch (from git): $DEFAULT_BRANCH${NC}"
fi

# Step 1: Configure Git (if not already configured)
echo -e "\n${YELLOW}=== Configuring Git ===${NC}"
GIT_USER_NAME=$(git config --global user.name 2>/dev/null || echo "")
GIT_USER_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -z "$GIT_USER_NAME" ]; then
    GIT_USER_NAME="${GITHUB_ACTOR:-$(whoami)}"
    git config --global user.name "$GIT_USER_NAME"
    echo "Set git user.name to: $GIT_USER_NAME"
else
    echo "Git user.name already configured: $GIT_USER_NAME"
fi

if [ -z "$GIT_USER_EMAIL" ]; then
    GIT_USER_EMAIL="${GITHUB_ACTOR:-$(whoami)}@users.noreply.github.com"
    git config --global user.email "$GIT_USER_EMAIL"
    echo "Set git user.email to: $GIT_USER_EMAIL"
else
    echo "Git user.email already configured: $GIT_USER_EMAIL"
fi

# Step 2: Commit changes in feature branch
echo -e "\n${YELLOW}=== Creating feature branch and committing changes ===${NC}"
BRANCH_NAME="cursor-agent/$(date +%Y%m%d-%H%M%S)"
echo "Branch name: $BRANCH_NAME"

# Check if there are any changes
if [ -z "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}No changes to commit${NC}"
else
    git checkout -B "$BRANCH_NAME"
    git add -A
    
    if git diff --staged --quiet; then
        echo -e "${YELLOW}No changes to commit${NC}"
    else
        git commit -m "feat: Hello World Java program for PR" || echo "No changes to commit"
    fi
fi

# Push branch
echo "Pushing branch to origin..."
git push origin "$BRANCH_NAME" || {
    echo -e "${RED}Error: Failed to push branch. Make sure you have push access.${NC}"
    exit 1
}

# Export BRANCH_NAME for GitHub Actions (if GITHUB_ENV is set)
if [ -n "$GITHUB_ENV" ]; then
    echo "BRANCH_NAME=$BRANCH_NAME" >> "$GITHUB_ENV"
fi

# Step 3: Create PR
echo -e "\n${YELLOW}=== Creating Pull Request ===${NC}"
API_BASE="https://api.github.com/repos/$GITHUB_REPO"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_BASE/pulls" \
    -d "{\"title\":\"feat: Hello World Java program for PR\",\"body\":\"Automated PR created by cursor-agent workflow\",\"head\":\"$BRANCH_NAME\",\"base\":\"$DEFAULT_BRANCH}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "201" ]; then
    PR_NUMBER=$(echo "$BODY" | jq -r '.number')
    PR_URL=$(echo "$BODY" | jq -r '.html_url')
    echo -e "${GREEN}Created PR #$PR_NUMBER at $PR_URL${NC}"
    
    # Export PR_NUMBER for GitHub Actions (if GITHUB_ENV is set)
    if [ -n "$GITHUB_ENV" ]; then
        echo "PR_NUMBER=$PR_NUMBER" >> "$GITHUB_ENV"
    fi
    
    # Step 4: Post PR comment
    echo -e "\n${YELLOW}=== Posting comment on PR ===${NC}"
    COMMENT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$API_BASE/issues/$PR_NUMBER/comments" \
        -d "{\"body\":\"Docs updated\"}")
    
    COMMENT_HTTP_CODE=$(echo "$COMMENT_RESPONSE" | tail -n1)
    if [ "$COMMENT_HTTP_CODE" = "201" ]; then
        echo -e "${GREEN}Posted comment on PR #$PR_NUMBER${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to post comment (HTTP $COMMENT_HTTP_CODE)${NC}"
    fi
else
    echo -e "${RED}Failed to create PR (HTTP $HTTP_CODE)${NC}"
    if [ "$HTTP_CODE" = "403" ]; then
        echo -e "${RED}Error: Enable 'Allow GitHub Actions to create and approve pull requests' in repository settings, or use PAT_TOKEN${NC}"
    fi
    echo "Create manually: https://github.com/$GITHUB_REPO/compare/$DEFAULT_BRANCH...$BRANCH_NAME"
    exit 1
fi

echo -e "\n${GREEN}✓ Script completed successfully${NC}"

