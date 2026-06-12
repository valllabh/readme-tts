APP_NAME = ReadMe
BUILD_DIR = .build
RELEASE_BIN = $(BUILD_DIR)/release/$(APP_NAME)
DEBUG_BIN = $(BUILD_DIR)/debug/$(APP_NAME)
BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

# MLX needs a compiled Metal shader library at runtime. SwiftPM from
# CommandLineTools cannot compile Metal shaders, so we colocate the prebuilt
# mlx.metallib that ships inside the Python mlx wheel (version must match the
# mlx core embedded in mlx-swift, currently 0.31.x).
METALLIB := $(shell python3 -c "import mlx.core, os; print(os.path.join(os.path.dirname(mlx.core.__file__), 'lib', 'mlx.metallib'))" 2>/dev/null)

# Stable signing identity keeps the Accessibility permission valid across
# rebuilds. Falls back to ad hoc when the cert is missing.
CODESIGN_ID := $(shell security find-identity -p codesigning -v 2>/dev/null | grep -o '"ReadMe Dev Signing"' | head -1)
ifeq ($(CODESIGN_ID),)
CODESIGN_ID := -
endif

# Marketing version from the latest git tag (v0.2.0 -> 0.2.0); build number
# is the commit count, monotonic so Sparkle can compare CFBundleVersion.
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
ifeq ($(VERSION),)
VERSION := 0.1.0
endif
BUILD_NUM := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

DIST_DIR = dist
REPO_URL = https://github.com/valllabh/readme
SPARKLE_VERSION = 2.9.3
SPARKLE_TOOLS = $(BUILD_DIR)/sparkle-tools/bin

.PHONY: build release run bundle install clean test metallib-check dist appcast publish sparkle-keys

metallib-check:
	@if [ ! -f "$(METALLIB)" ]; then \
		echo "error: mlx.metallib not found. Run: pip3 install mlx"; \
		exit 1; \
	fi

build: metallib-check
	swift build
	cp "$(METALLIB)" $(BUILD_DIR)/debug/mlx.metallib

release: metallib-check
	swift build -c release
	cp "$(METALLIB)" $(BUILD_DIR)/release/mlx.metallib

run: build
	$(DEBUG_BIN)

bundle: release
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources $(BUNDLE)/Contents/Frameworks
	cp Bundle/Info.plist $(BUNDLE)/Contents/
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUM)" $(BUNDLE)/Contents/Info.plist
	cp Assets/ReadMe.icns $(BUNDLE)/Contents/Resources/
	cp $(RELEASE_BIN) $(BUNDLE)/Contents/MacOS/
	cp "$(METALLIB)" $(BUNDLE)/Contents/MacOS/mlx.metallib
	ditto $(BUILD_DIR)/release/Sparkle.framework $(BUNDLE)/Contents/Frameworks/Sparkle.framework
	install_name_tool -add_rpath @executable_path/../Frameworks $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	codesign --force --deep --sign $(CODESIGN_ID) $(BUNDLE)
	@echo "Bundle at $(BUNDLE), version $(VERSION) build $(BUILD_NUM)"

icon:
	swift scripts/makeicon.swift
	iconutil -c icns Assets/ReadMe.iconset -o Assets/ReadMe.icns

# Installs to the user Applications folder. The system /Applications needs
# admin rights, which this account does not have. Spotlight indexes both.
INSTALL_DIR = $(HOME)/Applications

install: bundle
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R $(BUNDLE) $(INSTALL_DIR)/
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(INSTALL_DIR)/$(APP_NAME).app
	ln -sf $(INSTALL_DIR)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME) /opt/homebrew/bin/readme
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app, CLI at /opt/homebrew/bin/readme"
	@echo "Run once, grant Accessibility permission, then the Services menu entry appears after next login or pbs refresh."

test:
	swift run ReadMeSelfTest

# --- Release management: GitHub Releases plus Sparkle auto updates ---
# Flow: git tag v0.2.0, then make publish. The EdDSA private key lives in
# the login keychain (created once via make sparkle-keys), never in the repo.

$(SPARKLE_TOOLS)/generate_appcast:
	mkdir -p $(BUILD_DIR)/sparkle-tools
	curl -sL -o $(BUILD_DIR)/sparkle-tools/sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz
	tar xf $(BUILD_DIR)/sparkle-tools/sparkle.tar.xz -C $(BUILD_DIR)/sparkle-tools

sparkle-keys: $(SPARKLE_TOOLS)/generate_appcast
	$(SPARKLE_TOOLS)/generate_keys

dist: bundle
	mkdir -p $(DIST_DIR)
	rm -f $(DIST_DIR)/$(APP_NAME)-$(VERSION).zip
	ditto -c -k --keepParent $(BUNDLE) $(DIST_DIR)/$(APP_NAME)-$(VERSION).zip
	@echo "Zip at $(DIST_DIR)/$(APP_NAME)-$(VERSION).zip"

appcast: dist $(SPARKLE_TOOLS)/generate_appcast
	$(SPARKLE_TOOLS)/generate_appcast --download-url-prefix $(REPO_URL)/releases/download/v$(VERSION)/ -o appcast.xml $(DIST_DIR)

publish: appcast
	gh release create v$(VERSION) $(DIST_DIR)/$(APP_NAME)-$(VERSION).zip --title "$(APP_NAME) $(VERSION)" --generate-notes
	git add appcast.xml
	git commit -m "Appcast for $(VERSION)"
	git push

clean:
	swift package clean
	rm -rf $(BUNDLE)
