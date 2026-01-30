#!/bin/bash

# Pre-commit Setup Script
# Run this in your project root to set up local commit validation

set -e

echo "Installing dependencies..."
npm install --save-dev husky @commitlint/cli @commitlint/config-conventional

echo "Initializing Husky..."
npx husky init

echo "Removing default pre-commit hook..."
echo '# No pre-commit checks - validation happens on commit-msg and pre-push' > .husky/pre-commit

echo "Creating commit-msg hook..."
echo './node_modules/.bin/commitlint --edit "$1"' > .husky/commit-msg

echo "Creating pre-push hook for branch validation..."
cat > .husky/pre-push << 'EOF'
#!/bin/sh

branch="$(git rev-parse --abbrev-ref HEAD)"

# Allow main, master, develop branches
if [ "$branch" = "main" ] || [ "$branch" = "master" ] || [ "$branch" = "develop" ]; then
  exit 0
fi

# Validate branch name: type/issue-id-description
if ! echo "$branch" | grep -qE '^(feat|fix|chore|docs|refactor|style|perf|test)/[0-9]+-.+'; then
  echo "ERROR: Branch name '$branch' doesn't match pattern: type/ID-description"
  echo "Examples: feat/123-add-login, fix/456-resolve-crash"
  echo "Allowed types: feat, fix, chore, docs, refactor, style, perf, test"
  exit 1
fi
EOF

echo "Creating commitlint config..."
cat > commitlint.config.mjs << 'EOF'
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', ['feat', 'fix', 'chore', 'docs', 'style', 'refactor', 'perf', 'test', 'build', 'ci', 'revert']],
  },
};
EOF

echo ""
echo "Setup complete! Your repo now enforces:"
echo "  - Conventional commit messages (on commit)"
echo "  - Branch naming convention (on push)"
