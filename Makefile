# Apple II Mockingboard Music Player - Makefile
# Converts VGZ files to A2M format and builds the player

# Tools
PYTHON = python3
CA65 = ca65
LD65 = ld65
AC = $(TOOLS_DIR)/ac.jar

# Directories
SRC_DIR = src
TOOLS_DIR = tools
DATA_DIR = data
VGZ_DIR = vgz
BUILD_DIR = build

# Source files
ASM_SRCS = $(SRC_DIR)/startup.s $(SRC_DIR)/player.s $(SRC_DIR)/mockingboard.s
CFG_FILE = $(SRC_DIR)/apple2.cfg

# Output
TARGET = $(BUILD_DIR)/player.bin
DISK_IMAGE = $(BUILD_DIR)/music.dsk

# VGZ files to convert
VGZ_FILES = $(wildcard $(VGZ_DIR)/*.vgz)
A2M_FILES = $(patsubst $(VGZ_DIR)/%.vgz,$(DATA_DIR)/%.a2m,$(VGZ_FILES))

# Default target
.PHONY: all
all: $(DATA_DIR)/music.a2m $(TARGET)

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Create data directory
$(DATA_DIR):
	mkdir -p $(DATA_DIR)

# Convert VGZ to A2M
$(DATA_DIR)/%.a2m: $(VGZ_DIR)/%.vgz | $(DATA_DIR)
	$(PYTHON) $(TOOLS_DIR)/vgz2a2m.py "$<" "$@"

# Convert all VGZ files (handles spaces in filenames)
.PHONY: convert
convert:
	@for f in $(VGZ_DIR)/*.vgz; do \
		base=$$(basename "$$f" .vgz); \
		$(PYTHON) $(TOOLS_DIR)/vgz2a2m.py "$$f" "$(DATA_DIR)/$$base.a2m"; \
	done

# Create a default/placeholder music file if needed
$(DATA_DIR)/music.a2m: | $(DATA_DIR)
	@if [ ! -f "$@" ]; then \
		if [ -n "$(firstword $(VGZ_FILES))" ]; then \
			$(PYTHON) $(TOOLS_DIR)/vgz2a2m.py "$(firstword $(VGZ_FILES))" "$@"; \
		else \
			echo "Creating placeholder music file..."; \
			printf 'A2M\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xFE\x00' > "$@"; \
		fi \
	fi

# Assemble source files
$(BUILD_DIR)/startup.o: $(SRC_DIR)/startup.s | $(BUILD_DIR)
	$(CA65) -o $@ $<

$(BUILD_DIR)/player.o: $(SRC_DIR)/player.s $(DATA_DIR)/music.a2m | $(BUILD_DIR)
	$(CA65) -o $@ $<

$(BUILD_DIR)/mockingboard.o: $(SRC_DIR)/mockingboard.s | $(BUILD_DIR)
	$(CA65) -o $@ $<

# Link
$(TARGET): $(BUILD_DIR)/startup.o $(BUILD_DIR)/player.o $(BUILD_DIR)/mockingboard.o $(CFG_FILE)
	$(LD65) -C $(CFG_FILE) -o $@ \
		$(BUILD_DIR)/startup.o \
		$(BUILD_DIR)/player.o \
		$(BUILD_DIR)/mockingboard.o

# DOS 3.3 master disk (bootable base)
DOS33_MASTER = $(TOOLS_DIR)/Apple_DOS_v3.3.dsk

# Create disk image (requires AppleCommander)
.PHONY: disk
disk: $(TARGET)
	@if command -v java >/dev/null 2>&1 && [ -f "$(AC)" ]; then \
		cp $(DOS33_MASTER) $(DISK_IMAGE); \
		java -jar $(AC) -d $(DISK_IMAGE) HELLO 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) APPLESOFT 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) LOADER.OBJ0 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) FPBASIC 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) INTBASIC 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) MASTER 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) "MASTER CREATE" 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) COPY 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) COPY.OBJ0 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) COPYA 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) CHAIN 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) RENUMBER 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) FILEM 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) FID 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) CONVERT13 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) MUFFIN 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) START13 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) BOOT13 2>/dev/null || true; \
		java -jar $(AC) -d $(DISK_IMAGE) SLOT# 2>/dev/null || true; \
		tail -c +3 $(TARGET) | java -jar $(AC) -p $(DISK_IMAGE) PLAYER B 0x0803; \
		echo '10 PRINT CHR$$(4);"BRUN PLAYER"' | java -jar $(AC) -bas $(DISK_IMAGE) HELLO; \
		echo "Disk image created: $(DISK_IMAGE)"; \
		java -jar $(AC) -l $(DISK_IMAGE); \
	else \
		echo "AppleCommander not found. Skipping disk image creation."; \
		echo "Binary created at: $(TARGET)"; \
	fi

# Convert a specific VGZ file and rebuild
# Usage: make play VGZ=vgz/song.vgz
.PHONY: play
play:
ifdef VGZ
	$(PYTHON) $(TOOLS_DIR)/vgz2a2m.py "$(VGZ)" $(DATA_DIR)/music.a2m
	$(MAKE) clean-obj $(TARGET)
else
	@echo "Usage: make play VGZ=vgz/song.vgz"
endif

# Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

# Clean only object files (keep binary)
.PHONY: clean-obj
clean-obj:
	rm -f $(BUILD_DIR)/*.o

# Clean everything including converted files
.PHONY: distclean
distclean: clean
	rm -f $(DATA_DIR)/*.a2m

# Show info
.PHONY: info
info:
	@echo "VGZ files found: $(VGZ_FILES)"
	@echo "A2M files to create: $(A2M_FILES)"
	@echo "Target binary: $(TARGET)"

# Help
.PHONY: help
help:
	@echo "Apple II Mockingboard Music Player"
	@echo ""
	@echo "Usage:"
	@echo "  make              - Convert first VGZ and build player"
	@echo "  make convert      - Convert all VGZ files to A2M"
	@echo "  make play VGZ=... - Convert specific VGZ and rebuild"
	@echo "  make disk         - Create disk image (requires AppleCommander)"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make distclean    - Remove all generated files"
	@echo "  make info         - Show file information"
	@echo ""
	@echo "Example:"
	@echo "  make play VGZ=\"vgz/01 Title.vgz\""
