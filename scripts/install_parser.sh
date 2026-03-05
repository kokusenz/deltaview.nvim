#!/usr/bin/env bash
# Compiles a tree-sitter grammar into a .so and places it in deps/parser/.
# Usage: bash scripts/install_parser.sh <parser-name> <grammar-repo-url> [subdir]
#
# <subdir> is optional: the subdirectory within the repo that contains src/.
# Needed for repos that host multiple grammars (e.g. tree-sitter-typescript,
# tree-sitter-markdown). Omit for repos with src/ at the root.
#
# Grammar repos contain pre-generated src/parser.c (and optionally
# src/scanner.c or src/scanner.cc), so no tree-sitter CLI is required.
# Only cc (C) and c++ (C++) are needed.
#
# Examples:
#   bash scripts/install_parser.sh lua https://github.com/tree-sitter-grammars/tree-sitter-lua
#   bash scripts/install_parser.sh typescript https://github.com/tree-sitter/tree-sitter-typescript typescript

set -e

PARSER_NAME="$1"
GRAMMAR_URL="$2"
SUBDIR="${3:-}"
OUT_DIR="deps/parser"
TMP_DIR="deps/ts-src-$PARSER_NAME"

if [ -z "$PARSER_NAME" ] || [ -z "$GRAMMAR_URL" ]; then
    echo "Usage: $0 <parser-name> <grammar-repo-url> [subdir]" >&2
    exit 1
fi

if [ -f "$OUT_DIR/$PARSER_NAME.so" ]; then
    echo "$PARSER_NAME parser already installed"
    exit 0
fi

echo "Compiling $PARSER_NAME treesitter parser..."

git clone --filter=blob:none --depth=1 "$GRAMMAR_URL" "$TMP_DIR"

if [ -n "$SUBDIR" ]; then
    SRC_DIR="$TMP_DIR/$SUBDIR/src"
else
    SRC_DIR="$TMP_DIR/src"
fi

if [ -f "$SRC_DIR/scanner.cc" ]; then
    c++ -shared -fPIC -o "$OUT_DIR/$PARSER_NAME.so" \
        "$SRC_DIR/parser.c" "$SRC_DIR/scanner.cc" \
        "-I$SRC_DIR"
elif [ -f "$SRC_DIR/scanner.c" ]; then
    cc -shared -fPIC -o "$OUT_DIR/$PARSER_NAME.so" \
        "$SRC_DIR/parser.c" "$SRC_DIR/scanner.c" \
        "-I$SRC_DIR"
else
    cc -shared -fPIC -o "$OUT_DIR/$PARSER_NAME.so" \
        "$SRC_DIR/parser.c" \
        "-I$SRC_DIR"
fi

rm -rf "$TMP_DIR"
echo "$PARSER_NAME parser installed."
