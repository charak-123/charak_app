#!/usr/bin/env bash
# Re-download the Anek variable fonts (SIL OFL 1.1, by Ek Type) into
# packages/charak_core/fonts. The files are committed, so you only need this
# to upgrade them. Source: github.com/google/fonts (ofl/aneklatin, ofl/anekdevanagari).
set -euo pipefail
cd "$(dirname "$0")/../.."
dest=packages/charak_core/fonts
base=https://raw.githubusercontent.com/google/fonts/main/ofl
mkdir -p "$dest"
curl -fsSL "$base/aneklatin/AnekLatin%5Bwdth,wght%5D.ttf"           -o "$dest/AnekLatin-Variable.ttf"
curl -fsSL "$base/anekdevanagari/AnekDevanagari%5Bwdth,wght%5D.ttf" -o "$dest/AnekDevanagari-Variable.ttf"
curl -fsSL "$base/aneklatin/OFL.txt"                                -o "$dest/OFL.txt"
echo "Fonts updated in $dest"
