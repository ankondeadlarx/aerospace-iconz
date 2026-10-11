APP        := AeroSpaceIconz
BUNDLE     := build/$(APP).app
INSTALL_TO := $(HOME)/Applications/$(APP).app

.PHONY: test build install run uninstall clean

test:
	swift test

build:
	swift build -c release
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp .build/release/$(APP) $(BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(BUNDLE)/Contents/
	codesign --force --sign - $(BUNDLE)

# Replaces the installed copy and relaunches it.
install: build
	-pkill -x $(APP)
	mkdir -p $(HOME)/Applications
	rm -rf $(INSTALL_TO)
	cp -R $(BUNDLE) $(INSTALL_TO)
	open $(INSTALL_TO)

run: build
	-pkill -x $(APP)
	open $(BUNDLE)

uninstall:
	-pkill -x $(APP)
	rm -rf $(INSTALL_TO)

clean:
	rm -rf .build build
