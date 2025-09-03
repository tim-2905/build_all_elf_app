# BSP + linkerscript generation Makefile with BSP-file copy
WORKSPACE       ?= $(HOME)/Desktop/generate_bsp
VIVADO_SETTINGS ?= /tools/Xilinx/Vivado/2024.2/settings64.sh
PLATFORM_NAME   ?= stream_platform
DOMAIN_NAME     ?= mb_standalone

APP_NAME     ?= ppName
APP_TEMPLATE ?= Empty Application(C)
APP_LANG     ?= c
LSCRIPT_OUT  ?= $(WORKSPACE)/bsp/lscript.ld
UART_NAME    ?= axi_uartlite_0

BSP_DIR     = $(WORKSPACE)/bsp
BSP_SRC_DIR = $(BSP_DIR)/src

ifndef XSA_PATH
$(error XSA_PATH is not set. Usage: make generate_bsp XSA_PATH=/path/to/file.xsa PROC_NAME=processor_name VIVADO_SETTINGS=/path/to/settings64.sh)
endif
ifndef PROC_NAME
$(error PROC_NAME is not set. Usage: make generate_bsp XSA_PATH=/path/to/file.xsa PROC_NAME=processor_name VIVADO_SETTINGS=/path/to/settings64.sh)
endif
ifndef VIVADO_SETTINGS
$(error VIVADO_SETTINGS is not set. Usage: make generate_bsp XSA_PATH=/path/to/file.xsa PROC_NAME=processor_name VIVADO_SETTINGS=/path/to/settings64.sh)
endif

SELF := $(lastword $(MAKEFILE_LIST))
TCL_SCRIPT = $(WORKSPACE)/generate_bsp_and_lscript.tcl

.PHONY: generate_bsp copy_bsp_files clean clean-all help
generate_bsp: $(TCL_SCRIPT) create_bsp_dirs
	@echo "=== Generating BSP + Linkerscript for processor $(PROC_NAME) ==="
	@test -f $(VIVADO_SETTINGS) || (echo "ERROR: Vivado settings file not found: $(VIVADO_SETTINGS)" && exit 1)
	@rm -rf $(WORKSPACE)/$(PLATFORM_NAME) $(WORKSPACE)/$(APP_NAME) $(WORKSPACE)/.metadata
	@bash -c "source $(VIVADO_SETTINGS) && xsct $(TCL_SCRIPT)"
	@$(MAKE) -f $(SELF) copy_bsp_files

create_bsp_dirs:
	@mkdir -p $(BSP_DIR) $(BSP_SRC_DIR)

copy_bsp_files:
	@echo "=== Copying BSP files to $(BSP_DIR) ==="
	# 1) Try to find path 'export/.../bspinclude/include' 
	@HDR1="$(WORKSPACE)/$(PLATFORM_NAME)/export/$(PLATFORM_NAME)/sw/$(PLATFORM_NAME)/$(DOMAIN_NAME)/bspinclude/include"; \
	# 2) Fallback: search xparameters.h within the domain and take files
	HDR2=$$(find "$(WORKSPACE)/$(PLATFORM_NAME)" -path "*/$(DOMAIN_NAME)/*" -type f -name xparameters.h -printf '%h\n' | head -n1); \
	SRC=""; \
	if [ -d "$$HDR1" ]; then SRC="$$HDR1"; elif [ -n "$$HDR2" ] && [ -d "$$HDR2" ]; then SRC="$$HDR2"; fi; \
	if [ -n "$$SRC" ]; then \
	  echo "Copy header from $$SRC -> $(BSP_SRC_DIR)"; \
	  cp -r "$$SRC"/* "$(BSP_SRC_DIR)/"; \
	else \
	  echo "WARNING: No BSP header found."; \
	fi

	# copy linkerscript
	@LS1="$(WORKSPACE)/$(APP_NAME)/lscript.ld"; \
	LS2="$(WORKSPACE)/$(APP_NAME)/src/lscript.ld"; \
	LS=""; [ -f "$$LS1" ] && LS="$$LS1"; [ -z "$$LS" ] && [ -f "$$LS2" ] && LS="$$LS2"; \
	if [ -n "$$LS" ]; then cp "$$LS" "$(BSP_DIR)/"; else echo "WARNING: lscript.ld not found"; fi

	# copy boot.S
	@BOOT=$$(find "$(WORKSPACE)/$(PLATFORM_NAME)/$(PROC_NAME)/$(DOMAIN_NAME)/bsp/$(PROC_NAME)/libsrc"/standalone_v*"/src" -name boot.S -type f 2>/dev/null | head -n1); \
	if [ -n "$$BOOT" ]; then cp "$$BOOT" "$(BSP_DIR)/"; else echo "WARNING: boot.S not found"; fi

	# copy libxil.a
	@LIB="$(WORKSPACE)/$(PLATFORM_NAME)/export/$(PLATFORM_NAME)/sw/$(PLATFORM_NAME)/$(DOMAIN_NAME)/bsplib/lib/libxil.a"; \
	if [ -f "$$LIB" ]; then cp "$$LIB" "$(BSP_DIR)/"; else echo "WARNING: libxil.a not found"; fi

	@echo "=== Finished BSP copying ==="; \
	echo "BSP:      $(BSP_DIR)"; ls -la "$(BSP_DIR)" || true; \
	echo "BSP/src : $(BSP_SRC_DIR)"; ls -la "$(BSP_SRC_DIR)" || true

$(TCL_SCRIPT): | $(WORKSPACE)
	@{ \
	  echo '# Auto-generated TCL: BSP + linkerscript via XSCT'; \
	  echo 'setws $(WORKSPACE)'; \
	  echo 'set appName "$(APP_NAME)"'; \
	  echo 'catch { deleteprojects -name $$appName }'; \
	  echo 'catch { app remove -name $$appName }'; \
	  echo 'catch { platform remove $(PLATFORM_NAME) }'; \
	  echo 'platform create -name $(PLATFORM_NAME) -hw $(XSA_PATH) -proc $(PROC_NAME)'; \
	  echo 'platform active $(PLATFORM_NAME)'; \
	  echo 'catch { domain remove $(DOMAIN_NAME) }'; \
	  echo 'domain create -name $(DOMAIN_NAME) -proc $(PROC_NAME) -os standalone'; \
	  echo 'domain active $(DOMAIN_NAME)'; \
	  echo 'catch { bsp config stdin  $(UART_NAME) }'; \
	  echo 'catch { bsp config stdout $(UART_NAME) }'; \
	  echo 'bsp write'; \
	  echo 'bsp regenerate'; \
	  echo 'platform generate -domains $(DOMAIN_NAME)'; \
	  echo 'app create -name $$appName -platform $(PLATFORM_NAME) -domain $(DOMAIN_NAME) -proc $(PROC_NAME) -os standalone -lang $(APP_LANG) -template "$(APP_TEMPLATE)"'; \
	  echo 'app build -name $$appName'; \
	} > $(TCL_SCRIPT)

$(WORKSPACE):
	@mkdir -p $(WORKSPACE)

clean:
	@rm -f $(TCL_SCRIPT)
	@rm -rf $(WORKSPACE)/$(PLATFORM_NAME) $(WORKSPACE)/$(APP_NAME) $(WORKSPACE)/.metadata $(BSP_DIR)

clean-all:
	@rm -rf $(WORKSPACE)

help:
	@echo "Targets: generate_bsp | clean | clean-all"
.DEFAULT_GOAL := help
