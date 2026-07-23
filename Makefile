PREFIX ?= $(HOME)/.local

build: web

install: web-install

uninstall:
	rm -f $(PREFIX)/bin/diffy-web

clean:
	cd web && rm -rf dist node_modules

# ---------------------------------------------------------------------------
# Web edition (browser-based port in web/)
# ---------------------------------------------------------------------------

web:
	cd web && npm ci && npm run build

web-install: web
	@mkdir -p $(PREFIX)/bin
	@printf '%s\n' '#!/bin/sh' \
	  'DIR="$(CURDIR)/web"' \
	  'if [ ! -f "$$DIR/dist/index.html" ]; then (cd "$$DIR" && npm run build > /dev/null 2>&1); fi' \
	  'exec node "$$DIR/server/index.ts" "$$@"' > $(PREFIX)/bin/diffy
	@chmod +x $(PREFIX)/bin/diffy
	@echo "installed diffy -> $(PREFIX)/bin/diffy"

.PHONY: build install uninstall clean web web-install
