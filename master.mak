# master.mak – BSP (generate) + sync (MAIN_C -> app/{src,include}) + embeddedsw on-demand + build

.ONESHELL:
SHELL := /bin/bash

# ===== Pflicht-Eingaben =====
XSA_PATH        ?=
PROC_NAME       ?=
VIVADO_SETTINGS ?=
WORKSPACE       ?= $(HOME)/Desktop/test_generate

# Nur EIN Input: Pfad zu deiner main.c
MAIN_C          ?=

# ===== Abgeleitete Pfade =====
BSP_DIR      := $(WORKSPACE)/bsp
BSP_INC_DIR  := $(BSP_DIR)/src
LINKER_LD    := $(BSP_DIR)/lscript.ld

APP_SYNC_DIR := $(WORKSPACE)/app
APP_SYNC_INC := $(APP_SYNC_DIR)/include
APP_SYNC_SRC := $(APP_SYNC_DIR)/src

# ===== embeddedsw (partial clone + sparse checkout) =====
EMBEDDED_SW_URL ?= https://github.com/Xilinx/embeddedsw.git
EMBEDDED_SW_REF ?= xlnx_rel_v2024.2
EMBEDDED_SW_DIR ?= $(WORKSPACE)/_cache/embeddedsw

.PHONY: all debug generate sync embeddedsw_setup fetch_on_demand build gen_fetch_build clean

all: generate sync fetch_on_demand build

debug:
	@echo "XSA_PATH        = $(XSA_PATH)"
	@echo "PROC_NAME       = $(PROC_NAME)"
	@echo "VIVADO_SETTINGS = $(VIVADO_SETTINGS)"
	@echo "WORKSPACE       = $(WORKSPACE)"
	@echo "MAIN_C          = $(MAIN_C)"
	@echo "BSP_DIR         = $(BSP_DIR)"
	@echo "BSP_INC_DIR     = $(BSP_INC_DIR)"
	@echo "APP_SYNC_DIR    = $(APP_SYNC_DIR)"
	@echo "APP_SYNC_INC    = $(APP_SYNC_INC)"
	@echo "APP_SYNC_SRC    = $(APP_SYNC_SRC)"
	@echo "EMBEDDED_SW_DIR = $(EMBEDDED_SW_DIR)"
	@echo "EMBEDDED_SW_REF = $(EMBEDDED_SW_REF)"

# ---------- 1) BSP generieren ----------
generate:
	$(MAKE) -f generate.mak generate_bsp \
		XSA_PATH="$(XSA_PATH)" \
		PROC_NAME="$(PROC_NAME)" \
		VIVADO_SETTINGS="$(VIVADO_SETTINGS)" \
		WORKSPACE="$(WORKSPACE)"

# ---------- 2) MAIN_C analysieren & benötigte Dateien in app/ klonen ----------
sync: | $(APP_SYNC_INC) $(APP_SYNC_SRC)
	set -e

	# --- Helferfunktionen ---
	copy_first_match() { \
	  # $1=filename, $2=destdir, $3..=search dirs...
	  local f="$$1"; shift; local dest="$$1"; shift; \
	  local d; for d in "$$@"; do \
	    if [ -f "$$d/$$f" ]; then \
	      cp -f "$$d/$$f" "$$dest/"; \
	      echo "[SYNC] $$f  <-  $$d"; \
	      return 0; \
	    fi; \
	  done; \
	  return 1; \
	}
	find_bsp_inc_dir() { \
	  # Finde BSP-Header-Ordner (xparameters.h als Anker)
	  local guess; \
	  for guess in \
	    "$(BSP_INC_DIR)" \
	    "$(BSP_DIR)/include" \
	    "$(WORKSPACE)/bsp/src" \
	    "$(WORKSPACE)/stream_platform"/*/*/bsp/include \
	    "$(WORKSPACE)/stream_platform"/*/*/bsp/include/include \
	    "$(WORKSPACE)/src" \
	    "$(WORKSPACE)"; do \
	    [ -d "$$guess" ] || continue; \
	    if find "$$guess" -maxdepth 1 -type f -name xparameters.h | grep -q .; then \
	      echo "$$guess"; return 0; \
	    fi; \
	  done; \
	  echo "$(BSP_INC_DIR)"; \
	}

	# --- Eingaben prüfen ---
	[ -n "$(MAIN_C)" ] || { echo "ERROR: MAIN_C muss gesetzt sein (Pfad zu main.c)."; exit 1; }
	[ -f "$(MAIN_C)" ] || { echo "ERROR: Datei nicht gefunden: $(MAIN_C)"; exit 1; }
	MC_ABS="$(MAIN_C)"
	MC_DIR="$$(dirname "$$MC_ABS")"
	echo "[SYNC] main.c = $$MC_ABS"

	# main.c nach src/
	cp -f "$$MC_ABS" "$(APP_SYNC_SRC)/"

	# BSP-Include-Verzeichnis autodetektiert (falls nötig)
	DETECTED_BSP_INC="$$(find_bsp_inc_dir)"
	echo "[SYNC] BSP-Includes unter: $$DETECTED_BSP_INC"

	# Includes ("..." und <...>) aus main.c extrahieren (CRLF-fest)
	includes=$$(
	  tr -d '\r' < "$$MC_ABS" | \
	  grep -Eho '^[[:space:]]*#[:[:space:]]*include[[:space:]]*[<"][^">]+[">]' | \
	  sed -E 's/.*[<"]([^">]+)[">].*/\1/' | sort -u
	)
	[ -n "$$includes" ] && echo "[SYNC] Gefundene Includes: $$includes" || echo "[SYNC][WARN] Keine Includes in main.c gefunden."

	# 1) Header aus Projekt/BSP in app/include spiegeln, passende .c aus Projekt
	for inc in $$includes; do
	  base_noext="$${inc%.*}"
	  # Projekt-Header?
	  if copy_first_match "$$inc" "$(APP_SYNC_INC)" \
	       "$$MC_DIR" "$$MC_DIR/include" "$$MC_DIR/inc"; then
	    :
	  # BSP-Header?
	  elif copy_first_match "$$inc" "$(APP_SYNC_INC)" \
	       "$$DETECTED_BSP_INC"; then
	    :
	  else
	    echo "[SYNC] $$inc nicht lokal/BSP gefunden (wird später aus Repo geholt)."
	  fi
	  # passende .c (nur aus Projekt kopieren)
	  copy_first_match "$${base_noext}.c" "$(APP_SYNC_SRC)" \
	    "$$MC_DIR" "$$MC_DIR/src" "$$MC_DIR/.." "$$MC_DIR/../src" || true
	done

	# 2) Immer auch platform_config.h in include (Projekt -> BSP)
	copy_first_match "platform_config.h" "$(APP_SYNC_INC)" \
	  "$$MC_DIR" "$$MC_DIR/include" "$$DETECTED_BSP_INC" || true

	# 3) Immer auch platform.h in include (Projekt -> BSP)
	copy_first_match "platform.h" "$(APP_SYNC_INC)" \
	  "$$MC_DIR" "$$MC_DIR/include" "$$DETECTED_BSP_INC" || true

	# 4) Immer auch platform.c in src (Projekt -> BSP)
	copy_first_match "platform.c" "$(APP_SYNC_SRC)" \
	  "$$MC_DIR" "$$MC_DIR/src" "$$DETECTED_BSP_INC" || true

	echo "[SYNC] done -> $(APP_SYNC_DIR)"
	echo "        include/:"
	ls -1 "$(APP_SYNC_INC)" 2>/dev/null || true
	echo "        src/:"
	ls -1 "$(APP_SYNC_SRC)" 2>/dev/null || true

$(APP_SYNC_INC):
	mkdir -p "$(APP_SYNC_INC)"
$(APP_SYNC_SRC):
	mkdir -p "$(APP_SYNC_SRC)"

# ---------- 3) embeddedsw einrichten + fehlendes gezielt nachladen ----------
embeddedsw_setup: $(EMBEDDED_SW_DIR)/.git

$(EMBEDDED_SW_DIR)/.git:
	set -e
	echo "[SETUP] embeddedsw partial clone (ref: $(EMBEDDED_SW_REF))"
	command -v git >/dev/null 2>&1 || { echo "ERROR: git nicht gefunden"; exit 1; }
	mkdir -p "$(dir $(EMBEDDED_SW_DIR))"
	if [ ! -d "$(EMBEDDED_SW_DIR)/.git" ]; then
	  git clone --filter=blob:none --sparse --branch "$(EMBEDDED_SW_REF)" "$(EMBEDDED_SW_URL)" "$(EMBEDDED_SW_DIR)"
	  git -C "$(EMBEDDED_SW_DIR)" sparse-checkout set --no-cone
	else
	  git -C "$(EMBEDDED_SW_DIR)" fetch --all --tags --prune
	  git -C "$(EMBEDDED_SW_DIR)" checkout "$(EMBEDDED_SW_REF)"
	  git -C "$(EMBEDDED_SW_DIR)" pull --ff-only || true
	fi

fetch_on_demand: embeddedsw_setup
	set -e
	echo "[OD]  Ermittle fehlende Dateien aus app/ (nach sync)"
	# Alle Includes aus bereits kopierten Quellen (src+include)
	includes=$$(
	  { \
	    grep -Rho '^[[:space:]]*#[:[:space:]]*include[[:space:]]*[<"][^">]+[">]' "$(APP_SYNC_SRC)" 2>/dev/null || true; \
	    grep -Rho '^[[:space:]]*#[:[:space:]]*include[[:space:]]*[<"][^">]+[">]' "$(APP_SYNC_INC)" 2>/dev/null || true; \
	  } | sed -E 's/.*[<"]([^">]+)[">].*/\1/' | sort -u \
	)

	# Immer nachziehen, falls noch nicht vorhanden:
	want_always_h="platform_config.h platform.h"
	want_always_c="platform.c"

	needs_h=""
	for h in $$includes $$want_always_h; do
	  [ -f "$(APP_SYNC_INC)/$$h" ] && continue
	  needs_h="$$needs_h $$h"
	done

	needs_c=""
	for h in $$includes $$want_always_c; do
	  b="$${h%.*}.c"
	  [ -f "$(APP_SYNC_SRC)/$$b" ] && continue
	  needs_c="$$needs_c $$b"
	done

	if [ -z "$$needs_h$$needs_c" ]; then
	  echo "[OD]  Alles vorhanden – nichts aus Repo zu holen."
	  exit 0
	fi

	echo "[OD]  Fehlende Header: $$needs_h"
	echo "[OD]  Fehlende C-Files: $$needs_c"

	# Hilfsfunktion: Ordner im Repo finden, sparse-add, kopieren
	repo_fetch_and_copy() { \
	  local fname="$$1"; local dest="$$2"; local pattern="/$${fname}$$"; \
	  local match dir; \
	  match=$$(git -C "$(EMBEDDED_SW_DIR)" ls-tree -r --name-only HEAD | grep -E "$$pattern" | head -n1 || true); \
	  if [ -z "$$match" ]; then return 1; fi; \
	  dir=$$(dirname "$$match"); \
	  echo "[OD]  repo: $$fname -> $$dir"; \
	  git -C "$(EMBEDDED_SW_DIR)" sparse-checkout add "$$dir"; \
	  cp -f "$(EMBEDDED_SW_DIR)/$$match" "$$dest/"; \
	  return 0; \
	}

	for h in $$needs_h; do
	  repo_fetch_and_copy "$$h" "$(APP_SYNC_INC)" || echo "[OD]  WARN: $$h nicht im Repo gefunden"
	done
	for c in $$needs_c; do
	  repo_fetch_and_copy "$$c" "$(APP_SYNC_SRC)" || echo "[OD]  WARN: $$c nicht im Repo gefunden"
	done

	# Fallbacks: falls Repo-Dateien nicht auffindbar waren
	if [ ! -f "$(APP_SYNC_INC)/platform_config.h" ]; then
	  printf '%s\n' \
	    '#ifndef PLATFORM_CONFIG_H' \
	    '#define PLATFORM_CONFIG_H' \
	    '/* Platzhalter für Board-/Projekt-Defines */' \
	    '#endif' \
	    > "$(APP_SYNC_INC)/platform_config.h"
	  echo "[OD]  Fallback platform_config.h erzeugt."
	fi
	if [ ! -f "$(APP_SYNC_INC)/platform.h" ]; then
	  printf '%s\n' \
	    '#ifndef PLATFORM_H' \
	    '#define PLATFORM_H' \
	    '#ifdef __cplusplus' \
	    'extern "C" {' \
	    '#endif' \
	    '#include "platform_config.h"' \
	    'void init_platform(void);' \
	    'void cleanup_platform(void);' \
	    '#ifdef __cplusplus' \
	    '}' \
	    '#endif' \
	    '#endif' \
	    > "$(APP_SYNC_INC)/platform.h"
	  echo "[OD]  Fallback platform.h erzeugt."
	fi
	if [ ! -f "$(APP_SYNC_SRC)/platform.c" ]; then
	  printf '%s\n' \
	    '#include "platform.h"' \
	    'void init_platform(void) {}' \
	    'void cleanup_platform(void) {}' \
	    > "$(APP_SYNC_SRC)/platform.c"
	  echo "[OD]  Fallback platform.c erzeugt."
	fi

	echo "[OD]  Fertig."
	echo "        include/:"
	ls -1 "$(APP_SYNC_INC)" 2>/dev/null || true
	echo "        src/:"
	ls -1 "$(APP_SYNC_SRC)" 2>/dev/null || true

# ---------- 4) Build ----------
build:
	$(MAKE) -f build.mak all \
		ROOT_DIR="$(WORKSPACE)" \
		BSP_DIR="$(BSP_DIR)" \
		SRC_DIR="$(APP_SYNC_SRC)" \
		BSP_INC="$(BSP_INC_DIR)" \
		BSP_LIBDIR="$(BSP_DIR)" \
		LINKER_SCRIPT="$(LINKER_LD)" \
		EXTRA_INCLUDES='-I$(APP_SYNC_INC)'

# Komfort-Flow
gen_fetch_build: generate sync fetch_on_demand build

clean:
	-$(MAKE) -f build.mak clean
	-$(MAKE) -f generate.mak clean
	rm -rf "$(APP_SYNC_DIR)"
