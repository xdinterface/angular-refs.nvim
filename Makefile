.PHONY: test test-unit test-integration test-file lint format install-fixtures clean help

NVIM ?= nvim
PLENARY_OPTS ?= {minimal_init = 'test/minimal_init.lua'}

help:
	@echo "angular-refs.nvim test commands:"
	@echo ""
	@echo "  make test              - Run all tests"
	@echo "  make test-unit         - Run unit tests only"
	@echo "  make test-integration  - Run integration tests only"
	@echo "  make test-file FILE=x  - Run specific test file"
	@echo "  make install-fixtures  - Install Angular test app dependencies"
	@echo "  make build-fixtures    - Build Angular test app"
	@echo "  make lint              - Run linter on Lua files"
	@echo "  make format            - Format Lua files"
	@echo "  make clean             - Clean generated files"
	@echo ""

test:
	@echo "Running all tests..."
	$(NVIM) --headless -c "PlenaryBustedDirectory test/plenary/ $(PLENARY_OPTS)"

test-unit:
	@echo "Running unit tests..."
	$(NVIM) --headless -c "PlenaryBustedDirectory test/plenary/ $(PLENARY_OPTS)" \
		--pattern "*_spec.lua" \
		--exclude "*integration*"

test-integration:
	@echo "Running integration tests..."
	$(NVIM) --headless -c "PlenaryBustedDirectory test/plenary/ $(PLENARY_OPTS)" \
		--pattern "*integration*"

test-file:
ifndef FILE
	$(error FILE is required. Usage: make test-file FILE=test/plenary/config_spec.lua)
endif
	@echo "Running $(FILE)..."
	$(NVIM) --headless -c "PlenaryBustedFile $(FILE) $(PLENARY_OPTS)"

install-fixtures:
	@echo "Installing Angular test app dependencies..."
	cd test/fixtures/angular-test-app && npm install

build-fixtures:
	@echo "Building Angular test app..."
	cd test/fixtures/angular-test-app && npm run build

lint:
	@echo "Linting Lua files..."
	@command -v luacheck >/dev/null 2>&1 && luacheck lua/ test/ --globals vim || echo "luacheck not installed"

format:
	@echo "Formatting Lua files..."
	@command -v stylua >/dev/null 2>&1 && stylua lua/ test/ || echo "stylua not installed"

clean:
	@echo "Cleaning generated files..."
	rm -rf test/fixtures/angular-test-app/node_modules
	rm -rf test/fixtures/angular-test-app/dist
	rm -rf test/fixtures/angular-test-app/.angular
