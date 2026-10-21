# First "Apple Development" identity in your keychain; override with `make IDENTITY="..."`.
IDENTITY ?= $(shell security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)
BIN := .build/release
APP := build/Scotta.app
DAEMON := build/com.scotta.daemon
SIGN = codesign --force --options runtime --sign "$(IDENTITY)"

.PHONY: all build test app icon install uninstall clean

all: app

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(APP)
	@test -n "$(IDENTITY)" || { echo "No Apple Development signing identity found; set IDENTITY=..."; exit 1; }
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Helpers $(APP)/Contents/Resources
	cp Support/Info.plist $(APP)/Contents/
	cp Support/AppIcon.icns $(APP)/Contents/Resources/
	cp $(BIN)/ScottaApp $(APP)/Contents/MacOS/Scotta
	cp $(BIN)/scotta $(APP)/Contents/Helpers/scotta
	cp $(BIN)/scottad $(DAEMON)
	$(SIGN) --identifier com.scotta.cli $(APP)/Contents/Helpers/scotta
	$(SIGN) $(APP)
	$(SIGN) --identifier com.scotta.daemon $(DAEMON)

# Regenerates Support/AppIcon.icns and docs/icon.png from Support/make-icon.swift.
icon:
	rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset docs
	swift Support/make-icon.swift build/icon.png
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s build/icon.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		sips -z $$((s*2)) $$((s*2)) build/icon.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o Support/AppIcon.icns
	sips -z 256 256 build/icon.png --out docs/icon.png >/dev/null

# Builds as you, then copies into place with sudo.
install: app
	-sudo launchctl bootout system/com.scotta.daemon 2>/dev/null
	sudo install -d /Library/PrivilegedHelperTools /Library/Logs/Scotta /usr/local/bin
	sudo install -m 755 $(DAEMON) /Library/PrivilegedHelperTools/
	sudo install -m 644 Support/com.scotta.daemon.plist /Library/LaunchDaemons/
	sudo rm -rf /Applications/Scotta.app
	sudo cp -R $(APP) /Applications/
	sudo ln -sf /Applications/Scotta.app/Contents/Helpers/scotta /usr/local/bin/scotta
	sudo launchctl bootstrap system /Library/LaunchDaemons/com.scotta.daemon.plist
	open /Applications/Scotta.app

# Restores firmware defaults first, then removes everything.
uninstall:
	-/usr/local/bin/scotta reset
	-osascript -e 'quit app "Scotta"'
	-sudo launchctl bootout system/com.scotta.daemon
	sudo rm -rf /Applications/Scotta.app /usr/local/bin/scotta /Library/PrivilegedHelperTools/com.scotta.daemon \
		/Library/LaunchDaemons/com.scotta.daemon.plist "/Library/Application Support/Scotta" /Library/Logs/Scotta

clean:
	rm -rf .build build
