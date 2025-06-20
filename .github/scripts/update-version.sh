#!/bin/bash
set -euo pipefail

# Update version numbers across the project
# Usage: update-version.sh <version_type>
# version_type: patch, minor, major, none

VERSION_TYPE="${1:-patch}"

echo "🔄 Updating project version..."
echo "Version Type: $VERSION_TYPE"

# Configure Git
git config --local user.name "GitHub Action"
git config --local user.email "action@github.com"

# Get current branch name
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Current branch: $CURRENT_BRANCH"

# Function to get current version from server/version.py
get_current_version() {
    if [ -f "server/version.py" ]; then
        grep -o '__version__ = "[^"]*"' server/version.py | head -1 | cut -d'"' -f2 | tr -d '\n\r' | xargs
    else
        echo "❌ Error: server/version.py not found"
        exit 1
    fi
}

# Function to increment version
increment_version() {
    local current_version="$1"
    local increment_type="$2"
    
    # Parse version parts
    IFS='.' read -r MAJOR MINOR PATCH <<< "$current_version"
    
    case "$increment_type" in
        major)
            NEW_VERSION="$((MAJOR + 1)).0.0"
            ;;
        minor)
            NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
            ;;
        patch)
            NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
            ;;
        none)
            NEW_VERSION="$current_version"
            ;;
        *)
            echo "❌ Error: Invalid version type '$increment_type'"
            echo "Valid types: major, minor, patch, none"
            exit 1
            ;;
    esac
    
    echo "$NEW_VERSION"
}

# Function to update version in a file
update_version_in_file() {
    local file="$1"
    local old_version="$2"
    local new_version="$3"
    local pattern="$4"
    
    if [ -f "$file" ]; then
        echo "📝 Updating version in $file: $old_version -> $new_version"
        
        # Clean versions of any whitespace
        old_version=$(echo "$old_version" | tr -d '\n\r' | xargs)
        new_version=$(echo "$new_version" | tr -d '\n\r' | xargs)
        
        # Escape special characters for sed (dots become literal dots)
        local escaped_old_version=$(echo "$old_version" | sed 's/\./\\./g')
        local escaped_new_version=$(echo "$new_version" | sed 's/\./\\./g')
        
        # Create backup
        cp "$file" "${file}.bak"
        
        # Build the actual sed pattern with escaped versions
        local actual_pattern
        case "$pattern" in
            *"__version__"*)
                actual_pattern="s/__version__ = \"$escaped_old_version\"/__version__ = \"$new_version\"/"
                ;;
            *"version ="*)
                # For version = patterns, update only the first occurrence to avoid changing tool.briefcase.version
                actual_pattern="1,/^version = \"$escaped_old_version\"/s/^version = \"$escaped_old_version\"/version = \"$new_version\"/"
                ;;
            *)
                # Fallback: use the provided pattern but escape the versions
                actual_pattern=$(echo "$pattern" | sed "s|$old_version|$new_version|g")
                ;;
        esac
        
        # Update version using the constructed pattern
        if sed -i.tmp "$actual_pattern" "$file" 2>/dev/null; then
            rm -f "${file}.tmp"
            echo "✅ Updated $file"
        else
            # Restore backup if sed failed
            mv "${file}.bak" "$file"
            echo "❌ Failed to update $file"
            return 1
        fi
        
        # Remove backup
        rm -f "${file}.bak"
    else
        echo "⚠️ Warning: $file not found, skipping"
    fi
}

# Function to update CHANGELOG.md
update_changelog() {
    local new_version="$1"
    local version_type="$2"
    
    if [ -f "CHANGELOG.md" ]; then
        echo "📝 Updating CHANGELOG.md..."
        
        local today=$(date +%Y-%m-%d)
        local temp_file=$(mktemp)
        
        # Create new changelog entry
        cat > "$temp_file" << EOF
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [$new_version] - $today

### Changed
- Version increment: $version_type

EOF
        
        # Append existing content (skip the header)
        if grep -q "## \[Unreleased\]" CHANGELOG.md; then
            sed -n '/## \[Unreleased\]/,$p' CHANGELOG.md | tail -n +2 >> "$temp_file"
        else
            # If no existing unreleased section, append everything after the header
            tail -n +4 CHANGELOG.md >> "$temp_file"
        fi
        
        # Replace the original file
        mv "$temp_file" CHANGELOG.md
        
        echo "✅ Updated CHANGELOG.md"
    else
        echo "📝 Creating CHANGELOG.md..."
        cat > CHANGELOG.md << EOF
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [$new_version] - $(date +%Y-%m-%d)

### Changed
- Version increment: $version_type
- Initial release

EOF
        echo "✅ Created CHANGELOG.md"
    fi
}

# Improved push function with better retry logic
push_with_retry() {
    local max_retries=5
    local base_delay=2
    local max_delay=30
    
    for attempt in $(seq 1 $max_retries); do
        echo "🔄 Push attempt $attempt of $max_retries..."
        
        # First, try to sync with remote
        echo "📥 Fetching latest changes from remote..."
        if ! git fetch origin "$CURRENT_BRANCH"; then
            echo "⚠️ Failed to fetch from origin, continuing anyway..."
        fi
        
        # Check if we're behind the remote
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse "origin/$CURRENT_BRANCH" 2>/dev/null || echo "")
        
        if [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
            echo "📦 Local branch is behind remote, attempting rebase..."
            
            # Try to rebase our changes onto the latest remote
            if git rebase "origin/$CURRENT_BRANCH"; then
                echo "✅ Successfully rebased onto latest remote changes"
            else
                echo "❌ Rebase failed, likely due to conflicts"
                
                # Check if there are conflicts
                if git status --porcelain | grep -q "^UU\|^AA\|^DD"; then
                    echo "🔧 Attempting to auto-resolve version conflicts..."
                    
                    # Try to auto-resolve conflicts in our modified files
                    local conflict_resolved=true
                    for file in server/version.py pyproject.toml CHANGELOG.md; do
                        if [ -f "$file" ] && git status --porcelain | grep -q "^UU.*$file"; then
                            echo "🔧 Auto-resolving conflict in $file..."
                            # Use our version (the working tree version)
                            git add "$file"
                        fi
                    done
                    
                    # Continue rebase if all conflicts are resolved
                    if git rebase --continue; then
                        echo "✅ Auto-resolved conflicts and continued rebase"
                    else
                        echo "❌ Could not auto-resolve conflicts, aborting rebase"
                        git rebase --abort
                        conflict_resolved=false
                    fi
                    
                    if [ "$conflict_resolved" = false ]; then
                        if [ $attempt -eq $max_retries ]; then
                            echo "❌ Failed to resolve conflicts after $max_retries attempts"
                            return 1
                        fi
                        
                        # Wait with exponential backoff and try again
                        local delay=$((base_delay * 2**(attempt-1)))
                        if [ $delay -gt $max_delay ]; then
                            delay=$max_delay
                        fi
                        echo "⏳ Waiting ${delay}s before retry..."
                        sleep $delay
                        continue
                    fi
                else
                    echo "❌ Rebase failed for unknown reasons"
                    git rebase --abort
                    
                    if [ $attempt -eq $max_retries ]; then
                        return 1
                    fi
                    
                    # Wait with exponential backoff and try again
                    local delay=$((base_delay * 2**(attempt-1)))
                    if [ $delay -gt $max_delay ]; then
                        delay=$max_delay
                    fi
                    echo "⏳ Waiting ${delay}s before retry..."
                    sleep $delay
                    continue
                fi
            fi
        fi
        
        # Try to push
        if git push origin "$CURRENT_BRANCH"; then
            echo "✅ Successfully pushed to origin/$CURRENT_BRANCH"
            return 0
        else
            echo "⚠️ Push attempt $attempt failed"
            
            if [ $attempt -eq $max_retries ]; then
                echo "❌ Failed to push after $max_retries attempts"
                return 1
            fi
            
            # Wait with exponential backoff before retry
            local delay=$((base_delay * 2**(attempt-1)))
            if [ $delay -gt $max_delay ]; then
                delay=$max_delay
            fi
            echo "⏳ Waiting ${delay}s before retry..."
            sleep $delay
        fi
    done
    
    return 1
}

# Main version update workflow
echo "🔍 Getting current version..."
CURRENT_VERSION=$(get_current_version)
echo "Current version: $CURRENT_VERSION"

if [ "$VERSION_TYPE" = "none" ]; then
    echo "📋 No version change requested"
    echo "new_version=$CURRENT_VERSION" >> $GITHUB_OUTPUT
    echo "changed=false" >> $GITHUB_OUTPUT
    exit 0
fi

# Calculate new version
NEW_VERSION=$(increment_version "$CURRENT_VERSION" "$VERSION_TYPE")
echo "New version: $NEW_VERSION"

# Update version in various files
echo "📝 Updating version in project files..."

# Update server/version.py
update_version_in_file \
    "server/version.py" \
    "$CURRENT_VERSION" \
    "$NEW_VERSION" \
    "__version__"

# Update pyproject.toml (project version)
update_version_in_file \
    "pyproject.toml" \
    "$CURRENT_VERSION" \
    "$NEW_VERSION" \
    "version ="

# Update pyproject.toml (tool.briefcase version) - try both patterns
update_version_in_file \
    "pyproject.toml" \
    "$CURRENT_VERSION" \
    "$NEW_VERSION" \
    "version ="

# Update CHANGELOG.md
update_changelog "$NEW_VERSION" "$VERSION_TYPE"

# Commit changes
echo "📝 Committing version changes..."
git add server/version.py pyproject.toml CHANGELOG.md

if git diff --staged --quiet; then
    echo "⚠️ No changes to commit"
else
    git commit -m "chore: bump version to $NEW_VERSION [skip ci]

- Version increment: $VERSION_TYPE
- Updated version in server/version.py
- Updated version in pyproject.toml  
- Updated CHANGELOG.md"

    echo "✅ Committed version changes"
fi

# Push changes with improved retry logic
echo "📤 Pushing version changes..."
if push_with_retry; then
    echo "✅ Successfully pushed version changes"
else
    echo "❌ Failed to push version changes"
    exit 1
fi

# Create and push Git tag with retry logic
echo "🏷️ Creating Git tag..."
git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION

Version: $NEW_VERSION
Type: $VERSION_TYPE release
Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

Changes:
- Version increment: $VERSION_TYPE
- See CHANGELOG.md for details"

echo "📤 Pushing tag..."
PUSH_RETRIES=3
for i in $(seq 1 $PUSH_RETRIES); do
    if git push origin "v$NEW_VERSION"; then
        echo "✅ Successfully pushed tag: v$NEW_VERSION"
        break
    else
        echo "⚠️ Tag push attempt $i failed"
        if [ $i -lt $PUSH_RETRIES ]; then
            echo "🔄 Retrying tag push..."
            sleep $((2 * i))
        else
            echo "⚠️ Failed to push tag after $PUSH_RETRIES attempts (continuing anyway)"
            break
        fi
    fi
done

# Set GitHub Actions outputs
echo "new_version=$NEW_VERSION" >> $GITHUB_OUTPUT
echo "changed=true" >> $GITHUB_OUTPUT

# Generate version summary
cat > version_summary.txt << EOF
Version Update Summary
=====================

Previous Version: $CURRENT_VERSION
New Version: $NEW_VERSION
Increment Type: $VERSION_TYPE
Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

Files Updated:
- server/version.py
- pyproject.toml
- CHANGELOG.md

Git Actions:
- Committed changes
- Created tag: v$NEW_VERSION
- Pushed to remote repository

Next Steps:
- Build and package applications
- Create GitHub release
- Publish to PyPI (if configured)
EOF

echo ""
echo "✅ Version update complete!"
echo "📋 Summary:"
cat version_summary.txt