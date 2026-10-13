.PHONY: test test-unit test-lsp lsp-deps lint format clean help

NVIM ?= nvim
ANGULAR ?= 20

help:
	@echo "angular-refs.nvim commands:"
	@echo ""
	@echo "  make test                  - Run unit and integration tests"
	@echo "  make test-unit             - Run unit tests (no language servers needed)"
	@echo "  make lsp-deps [ANGULAR=20] - Install fixture Angular packages and language servers"
	@echo "  make test-lsp              - Run integration tests against real language servers"
	@echo "  make lint                  - Run luacheck"
	@echo "  make format                - Run stylua"
	@echo "  make clean                 - Remove installed fixture dependencies"
	@echo ""

test: test-unit test-lsp

test-unit:
	$(NVIM) --headless -u test/minimal_init.lua \
		-c "PlenaryBustedDirectory test/plenary {minimal_init = 'test/minimal_init.lua', sequential = true}"

lsp-deps:
	test/scripts/install-lsp-deps.sh $(ANGULAR)

test-lsp:
	$(NVIM) --headless -u test/lsp/minimal_init.lua \
		-c "PlenaryBustedDirectory test/lsp {minimal_init = 'test/lsp/minimal_init.lua', sequential = true, timeout = 600000}"

lint:
	@command -v luacheck >/dev/null 2>&1 && luacheck lua/ test/ --globals vim || echo "luacheck not installed"

format:
	@command -v stylua >/dev/null 2>&1 && stylua lua/ test/ || echo "stylua not installed"

clean:
	rm -rf test/fixtures/angular-test-app/node_modules test/.servers
