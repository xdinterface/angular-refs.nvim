.PHONY: test test-unit test-integration test-file lint format help

NVIM ?= nvim
PLENARY_OPTS ?= {minimal_init = 'test/minimal_init.lua'}

help:
	@echo "make test | test-file FILE=... | test-integration LIVE_ROOTS='...' | lint | format"

test:
	$(NVIM) --headless -i NONE -u test/minimal_init.lua -c "PlenaryBustedDirectory test/plenary/ $(PLENARY_OPTS)"

test-unit: test

test-integration:
ifndef LIVE_ROOTS
	$(error LIVE_ROOTS is required; see test/live/README.md)
endif
	node test/live/matrix.mjs $(LIVE_ROOTS)

test-file:
ifndef FILE
	$(error FILE is required; e.g. test/plenary/lsp_spec.lua)
endif
	$(NVIM) --headless -i NONE -u test/minimal_init.lua -c "PlenaryBustedFile $(FILE) $(PLENARY_OPTS)"

lint:
	luacheck lua/ test/plenary/ --globals vim
	stylua --check lua/ test/plenary/ test/live/run.lua

format:
	stylua lua/ test/plenary/ test/live/run.lua
