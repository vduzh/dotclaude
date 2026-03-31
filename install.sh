#!/bin/bash
#
# Install skills from dotclaude into a project's .claude/skills/ directory.
#
# Usage:
#   ./install.sh <project-path> <skill-name> [skill-name...]
#   ./install.sh <project-path> --list
#   ./install.sh <project-path> --all
#
# Examples:
#   ./install.sh ~/projects/my-api rest-api-design dto-conventions pagination-filtering
#   ./install.sh ~/projects/my-api --list
#   ./install.sh ~/projects/my-api --all
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="$SCRIPT_DIR/skills"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <project-path> <skill-name> [skill-name...]"
    echo "       $0 <project-path> --list"
    echo "       $0 <project-path> --all"
    echo ""
    echo "Options:"
    echo "  --list    Show available skills"
    echo "  --all     Install all skills"
    echo ""
    echo "Examples:"
    echo "  $0 ~/projects/my-api rest-api-design dto-conventions"
    echo "  $0 . --list"
    exit 1
}

list_skills() {
    echo -e "${CYAN}Available skills:${NC}"
    echo ""
    for category_dir in "$CATALOG_DIR"/*/; do
        category=$(basename "$category_dir")
        echo -e "  ${YELLOW}$category/${NC}"
        for skill_dir in "$category_dir"*/; do
            [ -d "$skill_dir" ] || continue
            skill=$(basename "$skill_dir")
            # Extract description from frontmatter
            desc=$(sed -n 's/^description: *//p' "$skill_dir/SKILL.md" 2>/dev/null | head -1)
            echo -e "    ${GREEN}$skill${NC} — $desc"
        done
        echo ""
    done
}

find_skill() {
    local skill_name="$1"
    for category_dir in "$CATALOG_DIR"/*/; do
        if [ -d "$category_dir$skill_name" ]; then
            echo "$category_dir$skill_name"
            return 0
        fi
    done
    return 1
}

# --- Main ---

if [ $# -lt 2 ]; then
    usage
fi

PROJECT_PATH="$1"
shift

if [ "$1" = "--list" ]; then
    list_skills
    exit 0
fi

# Resolve project path
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
SKILLS_DIR="$PROJECT_PATH/.claude/skills"

# Collect skill names
if [ "$1" = "--all" ]; then
    SKILLS=()
    for category_dir in "$CATALOG_DIR"/*/; do
        for skill_dir in "$category_dir"*/; do
            [ -d "$skill_dir" ] || continue
            SKILLS+=("$(basename "$skill_dir")")
        done
    done
else
    SKILLS=("$@")
fi

# Install skills
mkdir -p "$SKILLS_DIR"
installed=0
failed=0

for skill in "${SKILLS[@]}"; do
    skill_path=$(find_skill "$skill" 2>/dev/null) || true
    if [ -z "$skill_path" ]; then
        echo -e "${RED}✗ Skill not found: $skill${NC}"
        ((failed++))
        continue
    fi

    # Copy the entire skill directory
    cp -r "$skill_path" "$SKILLS_DIR/"
    echo -e "${GREEN}✓ Installed: $skill${NC}"
    ((installed++))
done

echo ""
echo -e "${CYAN}Done: $installed installed, $failed failed${NC}"
echo -e "Skills directory: ${YELLOW}$SKILLS_DIR${NC}"
