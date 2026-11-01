CFLAGS := -arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter
DYLIB_SOURCES := $(shell find src/dylib -name '*.[hm]')

all: build/diapatch build/DiaPatches.dylib build/patches.json

build/diapatch: src/diapatch/main.m | build
	clang $(CFLAGS) -framework Foundation -o $@ $<

build/DiaPatches.dylib: $(DYLIB_SOURCES) | build
	clang $(CFLAGS) -Isrc/dylib -dynamiclib -framework AppKit -framework QuartzCore -framework AVFoundation -o $@ $(filter %.m,$^)

# The patch list for diatweaks. With DIAPATCH_MANIFEST set, the dylib writes it and exits as it loads, so diapatch never runs.
build/patches.json: build/DiaPatches.dylib build/diapatch
	DIAPATCH_MANIFEST=$@ DYLD_INSERT_LIBRARIES=$< build/diapatch

build:
	mkdir -p $@

test: build/DiaPatches.dylib
	./test.sh

# make patch NAME=HideFooButton starts a new patch in src/dylib/Patches/HideFooButton.
patch:
	@scripts/new-patch "$(NAME)"

clean:
	rm -rf build

.PHONY: all clean test patch
