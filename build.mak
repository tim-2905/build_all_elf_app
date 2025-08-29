# --- Projekt ---
PROJECT_NAME := my_standalone_project
ELF_FILE     := $(PROJECT_NAME).elf

# --- Toolchain ---
PREFIX  := riscv32-unknown-elf-
CC      := $(PREFIX)gcc
OBJCOPY := $(PREFIX)objcopy
OBJDUMP := $(PREFIX)objdump
SIZE    := $(PREFIX)size

# --- Verzeichnisse (overridable; passen zum Output von generate.mak) ---
ROOT_DIR       ?= $(CURDIR)
BSP_DIR        ?= $(ROOT_DIR)/bsp
SRC_DIR        ?= $(ROOT_DIR)/src
BSP_INC        ?= $(BSP_DIR)/src
BSP_LIBDIR     ?= $(BSP_DIR)
BUILD_DIR      ?= $(ROOT_DIR)/build
LINKER_SCRIPT  ?= $(BSP_DIR)/lscript.ld
BOOT_S         ?= $(BSP_DIR)/boot.S
EXTRA_INCLUDES ?=

# --- Flags ---
ARCH     := -march=rv32im_zicsr_zifencei -mabi=ilp32 -mcmodel=medany
CFLAGS   := $(ARCH) -Wall -O0 -g3 -ffunction-sections -fdata-sections -MMD -MP -ffreestanding \
            -I$(SRC_DIR) -I$(BSP_INC) $(EXTRA_INCLUDES)
ASFLAGS  := $(ARCH) -g3 -x assembler-with-cpp -I$(SRC_DIR) -I$(BSP_INC)
LDFLAGS  := $(ARCH) -Wl,--gc-sections -Wl,-Map=$(PROJECT_NAME).map -Wl,-e,_boot -T$(LINKER_SCRIPT)
LIBDIRS  := -L$(BSP_LIBDIR)
LIBS     := -Wl,--start-group -lxil -lc -lm -lgcc -Wl,--end-group

# --- Quellen/Objekte ---
# Falls nichts übergeben wird, nimm alle .c im SRC_DIR
C_SOURCES ?= $(wildcard $(SRC_DIR)/*.c)

OBJ_C   := $(addprefix $(BUILD_DIR)/,$(notdir $(C_SOURCES:.c=.o)))
OBJ_S   := $(BUILD_DIR)/boot.o
OBJECTS := $(OBJ_C) $(OBJ_S)

.PHONY: all clean size debug
all: $(ELF_FILE) size

$(BUILD_DIR):
	@mkdir -p $@

# Debug-Hilfe
debug:
	@echo "ROOT_DIR=$(ROOT_DIR)"
	@echo "BSP_DIR=$(BSP_DIR)"
	@echo "SRC_DIR=$(SRC_DIR)"
	@echo "BSP_INC=$(BSP_INC)"
	@echo "EXTRA_INCLUDES=$(EXTRA_INCLUDES)"
	@echo "C_SOURCES=$(C_SOURCES)"

# Finde Quellen via VPATH (damit %.c auch mit absolut/relativ klappt)
VPATH := $(SRC_DIR)

$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/boot.o: $(BOOT_S) | $(BUILD_DIR)
	$(CC) $(ASFLAGS) -c $< -o $@

$(ELF_FILE): $(OBJECTS) $(LINKER_SCRIPT)
	$(CC) $(LDFLAGS) $(LIBDIRS) $(OBJECTS) $(LIBS) -o $@

size: $(ELF_FILE) ; $(SIZE) $<
clean:
	rm -rf $(BUILD_DIR) *.elf *.map *.hex *.bin *.dis
-include $(OBJ_C:.o=.d)
