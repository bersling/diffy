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
	  'exec node "$(CURDIR)/web/server/index.ts" "$$@"' > $(PREFIX)/bin/diffy
	@chmod +x $(PREFIX)/bin/diffy
	@echo "installed diffy -> $(PREFIX)/bin/diffy"

.PHONY: build install uninstall clean web web-install
