#!/bin/bash
set -euo pipefail

SKILLS_DIR="${HOME}/.claude/skills"

for skill in docker-generator terraform-generator monitoring-generator; do
  echo "Installing ${skill}..."
  mkdir -p "${SKILLS_DIR}/${skill}/references"
  cp -r "${skill}/"* "${SKILLS_DIR}/${skill}/"
done

echo ""
echo "All 3 skills installed. Restart Claude Code to activate."
echo "  /docker-generator"
echo "  /terraform-generator"
echo "  /monitoring-generator"
