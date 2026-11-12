.DEFAULT_GOAL := ios-build

# Optional overrides: DEVICE (name or identifier), PROFILE, TEAM, BUNDLE_ID.
BUILD_DIR ?= $(CURDIR)/build/ios
APP := $(BUILD_DIR)/products/Debug-iphoneos/Racing.app

.PHONY: iphone ios-build ios-devices
iphone: ios-build
	@python3 Tools/deploy-ios.py iphone "$(APP)"

ios-build:
	@xcodebuild -project Racing.xcodeproj -scheme Racing -configuration Debug \
		-sdk iphoneos -derivedDataPath "$(BUILD_DIR)/DerivedData" \
		SYMROOT="$(BUILD_DIR)/products" OBJROOT="$(BUILD_DIR)/intermediates" \
		CODE_SIGNING_ALLOWED=NO build

ios-devices:
	@xcrun devicectl list devices --timeout 15
