#!/usr/bin/env bash

set -euo pipefail

if command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen already installed at $(command -v xcodegen)"
    exit 0
fi

export HOMEBREW_NO_AUTO_UPDATE=1

echo "Installing xcodegen for CI"
brew install xcodegen
