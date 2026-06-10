PREFIX ?= $(HOME)/.local

build:
	swiftc -O -swift-version 5 -o diffy Sources/*.swift

install: build
	mkdir -p $(PREFIX)/bin
	ln -sf $(CURDIR)/diffy $(PREFIX)/bin/diffy

uninstall:
	rm -f $(PREFIX)/bin/diffy

clean:
	rm -f diffy
	rm -rf dist

# Universal (arm64 + x86_64), ad-hoc signed, zipped for sharing.
dist:
	swiftc -O -swift-version 5 -target arm64-apple-macos11.0 -o /tmp/diffy-arm64 Sources/*.swift
	swiftc -O -swift-version 5 -target x86_64-apple-macos11.0 -o /tmp/diffy-x86_64 Sources/*.swift
	mkdir -p dist/diffy
	lipo -create /tmp/diffy-arm64 /tmp/diffy-x86_64 -output dist/diffy/diffy
	codesign -s - --force dist/diffy/diffy
	cd dist && rm -f diffy.zip && zip -r diffy.zip diffy -x '.*'

# macOS installer package (.pkg) with a proper ReadMe + uninstaller.
pkg:
	swiftc -O -swift-version 5 -target arm64-apple-macos11.0 -o /tmp/diffy-arm64 Sources/*.swift
	swiftc -O -swift-version 5 -target x86_64-apple-macos11.0 -o /tmp/diffy-x86_64 Sources/*.swift
	rm -rf dist/pkgroot dist/pkgbuild
	mkdir -p dist/pkgroot/usr/local/bin dist/pkgroot/usr/local/share/diffy dist/pkgbuild
	lipo -create /tmp/diffy-arm64 /tmp/diffy-x86_64 -output dist/pkgroot/usr/local/bin/diffy
	codesign -s - --force dist/pkgroot/usr/local/bin/diffy
	install -m 755 installer/uninstall.sh dist/pkgroot/usr/local/share/diffy/uninstall.sh
	pkgbuild --root dist/pkgroot \
	         --identifier com.taskbase.diffy \
	         --version 1.0 \
	         --install-location / \
	         dist/pkgbuild/diffy-component.pkg
	productbuild --distribution installer/distribution.xml \
	             --resources installer \
	             --package-path dist/pkgbuild \
	             dist/diffy-1.0.pkg
	rm -rf dist/pkgroot dist/pkgbuild

.PHONY: build install uninstall clean dist pkg
