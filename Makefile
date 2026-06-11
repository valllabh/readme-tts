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

.PHONY: build release run bundle install clean test metallib-check

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
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp Bundle/Info.plist $(BUNDLE)/Contents/
	cp Assets/ReadMe.icns $(BUNDLE)/Contents/Resources/
	cp $(RELEASE_BIN) $(BUNDLE)/Contents/MacOS/
	cp "$(METALLIB)" $(BUNDLE)/Contents/MacOS/mlx.metallib
	codesign --force --deep --sign $(CODESIGN_ID) $(BUNDLE)
	@echo "Bundle at $(BUNDLE)"

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
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Run once, grant Accessibility permission, then the Services menu entry appears after next login or pbs refresh."

test:
	swift run ReadMeSelfTest

clean:
	swift package clean
	rm -rf $(BUNDLE)
