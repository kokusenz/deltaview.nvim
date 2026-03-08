SHELL := /bin/bash
.PHONY: setup setup-silent test test-file clean

# Treesitter parsers compiled for tests: one "name,repo-url" entry per line.
# To add a parser, append a new entry. The script handles scanner.c and
# scanner.cc automatically; no tree-sitter CLI required, only cc and c++.
# TODO install markdown and typescript
PARSERS = \
	lua,https://github.com/tree-sitter-grammars/tree-sitter-lua \
	python,https://github.com/tree-sitter/tree-sitter-python \
	javascript,https://github.com/tree-sitter/tree-sitter-javascript \
	rust,https://github.com/tree-sitter/tree-sitter-rust \
	go,https://github.com/tree-sitter/tree-sitter-go \
	bash,https://github.com/tree-sitter/tree-sitter-bash \
	c,https://github.com/tree-sitter/tree-sitter-c \
	cpp,https://github.com/tree-sitter/tree-sitter-cpp \

setup:
	@mkdir -p deps deps/parser
	@if [ ! -d "deps/mini.test" ]; then \
		echo "Installing mini.test for testing..."; \
		git clone --filter=blob:none https://github.com/nvim-mini/mini.test deps/mini.test; \
	else \
		echo "mini.test already installed"; \
	fi
	@if [ ! -d "deps/delta" ]; then \
		echo "Installing delta.lua for integration tests..."; \
		git clone --filter=blob:none https://github.com/kokusenz/delta.lua deps/delta; \
	else \
		echo "delta already installed"; \
	fi
	@if [ ! -d "deps/fzf" ]; then \
		echo "Installing fzf (not fzf.vim) for integration test..."; \
		git clone --filter=blob:none https://github.com/junegunn/fzf deps/fzf; \
	else \
		echo "fzf already installed"; \
	fi
	@if [ ! -d "deps/fzf_lua" ]; then \
		echo "Installing fzf_lua for integration tests..."; \
		git clone --filter=blob:none https://github.com/ibhagwan/fzf-lua deps/fzf_lua; \
	else \
		echo "fzf_lua already installed"; \
	fi
	@if [ ! -d "deps/telescope" ]; then \
		echo "Installing telescope for integration tests..."; \
		git clone --filter=blob:none https://github.com/nvim-telescope/telescope.nvim deps/telescope; \
	else \
		echo "telescope already installed"; \
	fi
	@for entry in $(PARSERS); do \
		name=$${entry%%,*}; \
		rest=$${entry#*,}; \
		url=$${rest%%,*}; \
		subdir=""; \
		[ "$$url" != "$$rest" ] && subdir=$${rest#*,}; \
		bash scripts/install_parser.sh "$$name" "$$url" "$$subdir"; \
	done

setup-silent:
	@mkdir -p deps deps/parser
	@[ -d "deps/mini.test" ] || git clone -q --filter=blob:none https://github.com/nvim-mini/mini.test deps/mini.test
	@[ -d "deps/delta" ] || git clone -q --filter=blob:none https://github.com/kokusenz/delta.lua deps/delta
	@[ -d "deps/fzf" ] || git clone -q --filter=blob:none https://github.com/junegunn/fzf deps/fzf
	@[ -d "deps/fzf_lua" ] || git clone -q --filter=blob:none https://github.com/ibhagwan/fzf-lua deps/fzf_lua
	@[ -d "deps/telescope" ] || git clone -q --filter=blob:none https://github.com/nvim-telescope/telescope.nvim deps/telescope
	@for entry in $(PARSERS); do \
		name=$${entry%%,*}; \
		url=$${entry#*,}; \
		bash scripts/install_parser.sh "$$name" "$$url" > /dev/null; \
	done

# Run all tests
test: setup-silent
	nvim --headless --noplugin -u scripts/minimal_init.lua -c "luafile scripts/test.lua"

# Run a specific test file
# Usage: make test-file FILE=tests/deltaview/test_parsing.lua
test-file: setup-silent
	@if [ -z "$(FILE)" ]; then \
		echo "Error: FILE is not set. Usage: make test-file FILE=tests/deltaview/test_parsing.lua"; \
		exit 1; \
	fi
	nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')" -c "quit"

# Clean generated files and deps (next make test will reinstall everything)
clean:
	find . -name "*.swp" -delete
	find . -name "*~" -delete
	rm -rf deps

help:
	@echo "Available targets:"
	@echo "  make setup          - Install mini.test and delta.lua and compile treesitter parsers"
	@echo "  make test           - Run all tests"
	@echo "  make test-file FILE=<path> - Run a specific test file"
	@echo "  make clean          - Remove deps/ (next run will reinstall everything)"
	@echo ""
	@echo "Examples:"
	@echo "  make test"
	@echo "  make test-file FILE=tests/deltaview/test_view.lua"
