# Apple II Mockingboard Music Player - Makefile
# music/ 하위 각 앨범 폴더마다 별도 디스크 이미지를 생성합니다.

# Tools
PYTHON = python3
CA65 = ca65
LD65 = ld65
AC = $(TOOLS_DIR)/ac.jar

# Directories
SRC_DIR    = src
TOOLS_DIR  = tools
DATA_DIR   = data
MUSIC_DIR  = music
BUILD_DIR  = build

# Source files
ASM_SRCS = $(SRC_DIR)/startup.s $(SRC_DIR)/player.s $(SRC_DIR)/mockingboard.s
CFG_FILE = $(SRC_DIR)/apple2.cfg

# Output binary
TARGET = $(BUILD_DIR)/player.bin

# DOS 3.3 master disk (bootable base)
DOS33_MASTER = $(TOOLS_DIR)/Apple_DOS_v3.3.dsk

# Discover album subdirectories under music/
ALBUMS      = $(notdir $(wildcard $(MUSIC_DIR)/*))
DISK_IMAGES = $(patsubst %,$(BUILD_DIR)/%.dsk,$(ALBUMS))

# ------------------------------------------------------------------ #
# Default target: build player binary only
# ------------------------------------------------------------------ #
.PHONY: all
all: $(TARGET)

# ------------------------------------------------------------------ #
# Create directories
# ------------------------------------------------------------------ #
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(DATA_DIR):
	mkdir -p $(DATA_DIR)

# ------------------------------------------------------------------ #
# Assemble
# ------------------------------------------------------------------ #
$(BUILD_DIR)/startup.o: $(SRC_DIR)/startup.s | $(BUILD_DIR)
	$(CA65) -o $@ $<

$(BUILD_DIR)/player.o: $(SRC_DIR)/player.s | $(BUILD_DIR)
	$(CA65) -o $@ $<

$(BUILD_DIR)/mockingboard.o: $(SRC_DIR)/mockingboard.s | $(BUILD_DIR)
	$(CA65) -o $@ $<

# ------------------------------------------------------------------ #
# Link
# ------------------------------------------------------------------ #
$(TARGET): $(BUILD_DIR)/startup.o $(BUILD_DIR)/player.o $(BUILD_DIR)/mockingboard.o $(CFG_FILE)
	$(LD65) -C $(CFG_FILE) -o $@ \
		$(BUILD_DIR)/startup.o \
		$(BUILD_DIR)/player.o \
		$(BUILD_DIR)/mockingboard.o

# ------------------------------------------------------------------ #
# Convert all albums' VGZ files to A2M (without building disks)
# ------------------------------------------------------------------ #
.PHONY: convert
convert:
	@for dir in $(MUSIC_DIR)/*/; do \
		album=$$(basename "$$dir"); \
		mkdir -p "$(DATA_DIR)/$$album"; \
		for f in "$$dir"*.vgz; do \
			[ -f "$$f" ] || continue; \
			base=$$(basename "$$f" .vgz); \
			echo "Converting: $$f"; \
			$(PYTHON) $(TOOLS_DIR)/vgz2a2m.py "$$f" "$(DATA_DIR)/$$album/$$base.a2m"; \
		done; \
	done

# ------------------------------------------------------------------ #
# Per-album disk image  (e.g. build/firebird.dsk, build/msx-best.dsk)
# Runs convert + image + disk all-in-one via build_disk.py
# ------------------------------------------------------------------ #
$(BUILD_DIR)/%.dsk: $(TARGET) | $(BUILD_DIR)
	@if command -v java >/dev/null 2>&1 && [ -f "$(AC)" ]; then \
		$(PYTHON) $(TOOLS_DIR)/build_disk.py \
			"$(MUSIC_DIR)/$*" \
			"$(DATA_DIR)/$*" \
			"$@" \
			"$(TARGET)" \
			"$(AC)" \
			"$(DOS33_MASTER)" \
			"$(TOOLS_DIR)"; \
	else \
		echo "AppleCommander ($(AC)) not found. Skipping disk image."; \
	fi

# ------------------------------------------------------------------ #
# Convenient short aliases:  make disk-firebird  make disk-msx-best
# ------------------------------------------------------------------ #
disk-%: $(BUILD_DIR)/%.dsk
	@true

# ------------------------------------------------------------------ #
# Build all disk images (one per album)
# ------------------------------------------------------------------ #
.PHONY: all-disks disk
all-disks disk: $(TARGET) $(DISK_IMAGES)

# ------------------------------------------------------------------ #
# Play a specific VGZ file (quick test without full disk build)
# Usage: make play VGZ="music/firebird/01 Title.vgz"
# ------------------------------------------------------------------ #
.PHONY: play
play:
ifdef VGZ
	$(PYTHON) $(TOOLS_DIR)/vgz2a2m.py "$(VGZ)" $(DATA_DIR)/music.a2m
	$(MAKE) clean-obj $(TARGET)
else
	@echo "Usage: make play VGZ=\"music/<album>/<file>.vgz\""
endif

# ------------------------------------------------------------------ #
# Clean
# ------------------------------------------------------------------ #
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

.PHONY: clean-obj
clean-obj:
	rm -f $(BUILD_DIR)/*.o

.PHONY: distclean
distclean: clean
	rm -rf $(DATA_DIR)

# ------------------------------------------------------------------ #
# Info / Help
# ------------------------------------------------------------------ #
.PHONY: info
info:
	@echo "Albums    : $(ALBUMS)"
	@echo "Disk images: $(DISK_IMAGES)"
	@echo "Binary    : $(TARGET)"

.PHONY: help
help:
	@echo "Apple II Mockingboard Music Player"
	@echo ""
	@echo "Usage:"
	@echo "  make                  - Build player binary"
	@echo "  make convert          - Convert all VGZ files to A2M (per album)"
	@echo "  make all-disks        - Build a disk image for each album"
	@echo "  make disk-<album>     - Build disk for one album (e.g. make disk-firebird)"
	@echo "  make build/<album>.dsk- Same as above"
	@echo "  make play VGZ=<path>  - Quick-test one VGZ file"
	@echo "  make clean            - Remove build artifacts"
	@echo "  make distclean        - Remove all generated files"
	@echo "  make info             - Show discovered albums"
	@echo ""
	@echo "Albums found under $(MUSIC_DIR)/:"
	@for d in $(MUSIC_DIR)/*/; do echo "  - $$(basename $$d)"; done
