# Yabadabadoo-pak: an optional Pak Rat content pak that adds the Yabadabadoo
# Sega Saturn core to Leaf's SATURN system on the MLP1.
#
# Everything builds from a clean clone of this repository with Docker, git
# and python3: the pinned upstream sources are fetched into workdir/, the
# armhf core, RetroArch and runtime are built inside a digest-pinned Debian
# bookworm image, and the results land in build/.
#
#   make package       build build/package/Yabadabadoo.pak
#   make dist-pakrat   the Pak Rat archive, build/dist/Yabadabadoo.mlp1.pak.zip
#   make dist-source   the corresponding source, build/dist/yabadabadoo-pak-source.tar.gz
#   make check         validate the manifest, the wrapper and the vendored patches
#                      against SOURCE.json (no Docker needed)
#   make check-package validate the built package strictly
#   make check-patches fetch retroarch-builds and fail if a vendored Leaf patch drifted

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD := $(REPO_ROOT)/build
WORKDIR := $(REPO_ROOT)/workdir
PACKAGE := $(BUILD)/package/Yabadabadoo.pak
DIST := $(BUILD)/dist
ARTIFACT := $(DIST)/Yabadabadoo.mlp1.pak.zip
SOURCE_ARCHIVE := $(DIST)/yabadabadoo-pak-source.tar.gz

LOCK := $(REPO_ROOT)/upstream.lock.json
lock_get = $(shell python3 -I -c 'import functools,json,sys;print(functools.reduce(lambda v,k:v[k],sys.argv[2:],json.load(open(sys.argv[1]))))' "$(LOCK)" $(1))
IMAGE_REF = $(firstword $(subst :, ,$(call lock_get,image ref)))@$(call lock_get,image digest)
SOURCE_EPOCH = $(call lock_get,build source_date_epoch)

# The contract this pak is validated against, from the public leaf-contracts
# repository at a pinned commit. A local clone is fine for development.
CONTRACT_REPO ?= https://github.com/Utility-Muffin-Research-Kitchen/leaf-contracts.git
# The pin must carry the `frontend` field on retroarch cores (LEAF-RA-1); it
# moves together with .github/workflows/ci.yml and release.yml.
CONTRACT_REF ?= 4998d0f5a4f365004db7ba607b6370ee75ce0ace
CONTRACT_DIR ?= $(BUILD)/contract/$(CONTRACT_REF)

# A clone of retroarch-builds that contains the commit in
# patches/retroarch/leaf/SOURCE.json. Left empty, check-patches fetches that
# commit into a temporary directory.
RETROARCH_BUILDS_DIR ?=

.PHONY: all fetch package dist-pakrat dist-source validate test-wrapper check-patches vendored-patches check check-package clean distclean help

all: dist-pakrat

help:
	@sed -n '1,/^$$/p' $(firstword $(MAKEFILE_LIST)) | sed 's/^# \{0,1\}//'

fetch:
	scripts/fetch-sources.sh "$(WORKDIR)"

package: fetch
	mkdir -p "$(BUILD)"
	docker run --rm \
		-e HOST_UID="$$(id -u)" -e HOST_GID="$$(id -g)" \
		-v "$(REPO_ROOT)":/repo:ro -v "$(WORKDIR)/src":/src:ro -v "$(BUILD)":/out \
		"$(IMAGE_REF)" bash /repo/scripts/build-in-container.sh

dist-pakrat: package
	mkdir -p "$(DIST)"
	python3 -I scripts/make-archive.py zip --epoch "$(SOURCE_EPOCH)" \
		--out "$(ARTIFACT)" --root "$(BUILD)/package" Yabadabadoo.pak
	cd "$(DIST)" && shasum -a 256 "$(notdir $(ARTIFACT))" 2>/dev/null || sha256sum "$(notdir $(ARTIFACT))"

# GPL corresponding source: this repository (build scripts and patches) and
# the patched Yabadabadoo and RetroArch trees exactly as they were built.
dist-source: fetch
	mkdir -p "$(DIST)"
	python3 -I scripts/make-archive.py tar --epoch "$(SOURCE_EPOCH)" \
		--out "$(SOURCE_ARCHIVE)" \
		--member yabadabadoo-pak-source/yabadabadoo-pak="$(REPO_ROOT)" \
		--member yabadabadoo-pak-source/yabadabadoo="$(WORKDIR)/src/yabadabadoo" \
		--member yabadabadoo-pak-source/retroarch="$(WORKDIR)/src/retroarch"
	cd "$(DIST)" && shasum -a 256 "$(notdir $(SOURCE_ARCHIVE))" 2>/dev/null || sha256sum "$(notdir $(SOURCE_ARCHIVE))"

$(CONTRACT_DIR):
	git init -q "$@"
	git -C "$@" fetch -q --depth 1 "$(CONTRACT_REPO)" "$(CONTRACT_REF)"
	git -C "$@" -c advice.detachedHead=false checkout -q FETCH_HEAD

validate: $(CONTRACT_DIR)
	python3 -I scripts/validate-pak.py --contract "$(CONTRACT_DIR)" --pak pak

test-wrapper:
	sh tests/test-retroarch-sh.sh

# Leaf's MLP1 RetroArch patches are vendored; this fails if any differs from
# the original in retroarch-builds at the recorded commit.
check-patches:
	python3 -I scripts/check-patches.py verify $(if $(RETROARCH_BUILDS_DIR),--upstream "$(RETROARCH_BUILDS_DIR)")

# The offline half of check-patches: the vendored files against SOURCE.json.
vendored-patches:
	python3 -I scripts/check-patches.py list >/dev/null
	@echo "ok   vendored patches match SOURCE.json"

check: validate test-wrapper vendored-patches

check-package: $(CONTRACT_DIR)
	python3 -I scripts/validate-pak.py --contract "$(CONTRACT_DIR)" --pak "$(PACKAGE)" --packaged

clean:
	rm -rf "$(BUILD)"

distclean: clean
	rm -rf "$(WORKDIR)"
