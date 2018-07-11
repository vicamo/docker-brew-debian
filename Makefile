SHELL := /bin/bash

ifneq ($(strip $(V)),)
  hide :=
else
  hide := @
endif

DEBUERREOTYPE_ARTIFACTS_URL := https://raw.githubusercontent.com/debuerreotype/docker-debian-artifacts
DEB_SNAPSHOT_BASE_URL := http://snapshot.debian.org/archive
DEB_SNAPSHOT_EPOCH := $(shell wget --quiet -O - $(DEBUERREOTYPE_ARTIFACTS_URL)/dist-amd64/sid/rootfs.debuerreotype-epoch)
DEB_SNAPSHOT_TIMESTAMP := $(shell env TZ=UTC LC_ALL=C date --date "@$(DEB_SNAPSHOT_EPOCH)" '+%Y%m%dT%H%M%SZ')
DEB_SNAPSHOT_URL := $(DEB_SNAPSHOT_BASE_URL)/debian/$(DEB_SNAPSHOT_TIMESTAMP)
DEB_SNAPSHOT_SEC_URL := $(DEB_SNAPSHOT_BASE_URL)/debian-security/$(DEB_SNAPSHOT_TIMESTAMP)

# $(1): suite name, e.g. jessie
define get-debian-codename
$(shell (wget --quiet --spider $(DEB_SNAPSHOT_URL)/dists/$(1)/Release && wget --quiet -O - $(DEB_SNAPSHOT_URL)/dists/$(1)/Release 2>/dev/null) | grep ^Codename: | cut -d ' ' -f2)
endef

DEBUERREOTYPE_SERIAL := $(shell env TZ=UTC LC_ALL=C date --date "@$(DEB_SNAPSHOT_EPOCH)" '+%Y%m%d')
DEBUERREOTYPE_ARCH_NAME_armel := arm32v5
DEBUERREOTYPE_ARCH_NAME_armhf := arm32v7
DEBUERREOTYPE_ARCH_NAME_arm64 := arm64v8
DEBUERREOTYPE_ARCH_NAME_ppc64el := ppc64le

# $(1): debian architecture name
define debuerreotype-arch-name
$(if $(DEBUERREOTYPE_ARCH_NAME_$(1)),$(DEBUERREOTYPE_ARCH_NAME_$(1)),$(1))
endef

DEBIAN_ALIASED_NAMES := unstable testing stable oldstable
DEBIAN_ALIASED_NAMES += oldoldstable
$(foreach alias,$(DEBIAN_ALIASED_NAMES), \
  $(eval ALIAS_$(alias) := $(call get-debian-codename,$(alias))) \
  $(if $(ALIAS_$(alias)),$(info Debian $(alias) aliased to $(ALIAS_$(alias)))))
LATEST := $(ALIAS_stable)
$(info Latest aliased to $(LATEST))

DOCKER ?= docker
DOCKER_REPO := $(shell cat repo)
DOCKER_USER ?= $(shell $(DOCKER) info | awk '/^Username:/ { print $$2 }')
MKIMAGE ?= mkimage.sh
MKIMAGE := $(shell readlink -f $(MKIMAGE))

DEB_SYSTEM_ARCH := $(shell dpkg --print-architecture)
QEMU_NATIVE_ARCHS := amd64-i386 arm-armel armel-arm arm-armhf armhf-arm armel-armhf armhf-armel i386-amd64 powerpc-ppc64 ppc64-powerpc sparc-sparc64 sparc64-sparc s390-s390x s390x-s390
$(foreach arch,alpha arm armeb i386 m68k mips mipsel mips64el ppc64 sh4 sh4eb sparc sparc64 s390x,$(eval QEMU_ARCH_$(arch) := $(arch)))
QEMU_ARCH_amd64 := x86_64
QEMU_ARCH_armel := arm
QEMU_ARCH_armhf := arm
QEMU_ARCH_arm64 := aarch64
QEMU_ARCH_lpia := i386
QEMU_ARCH_powerpc := ppc
QEMU_ARCH_powerpcspe := ppc
QEMU_ARCH_ppc64el := ppc64le
QEMU_SUITE_wheezy := stretch
QEMU_SUITE_jessie := stretch

# $(1): suite
define get-qemu-suite
$(if $(QEMU_SUITE_$(1)),$(QEMU_SUITE_$(1)),$(1))
endef

# $(1): system dpkg arch
# $(2): target dpkg arch
define get-qemu-arch
$(if $(filter $(1)-$(2),$(1)-$(1) $(QEMU_NATIVE_ARCHS)),,$(QEMU_ARCH_$(2)))
endef

# $(1): relative directory path, e.g. "jessie/amd64"
# $(2): file name, e.g. suite
# $(3): default value
define get-part
$(shell if [ -f $(1)/$(2) ]; then cat $(1)/$(2); elif [ -f $(2) ]; then cat $(2); else echo "$(3)"; fi)
endef

# $(1): relative directory path, e.g. "jessie/amd64"
define target-name-from-path
$(subst /,-,$(1))
endef

# $(1): relative directory path, e.g. "jessie/amd64"
define suite-name-from-path
$(word 1,$(subst /, ,$(1)))
endef

# $(1): jessie or stable
define alias-name-from-suite
$(if $(ALIAS_$(1)),$(ALIAS_$(1)),$(1))
endef

# $(1): suite
# $(2): arch
define suite-arch-target-name
all-$(call alias-name-from-suite,$(1))-$(2)
endef

# $(1): relative directory path, e.g. "jessie/amd64"
define arch-name-from-path
$(word 2,$(subst /, ,$(1)))
endef

# $(1): relative directory path, e.g. "jessie/amd64/curl"
define func-name-from-path
$(word 3,$(subst /, ,$(1)))
endef

# $(1): relative directory path, e.g. "jessie/amd64"
define base-image-from-path
$(shell cat $(1)/Dockerfile | grep ^FROM | awk '{print $$2}')
endef

# $(1): base image name, e.g. "foo/bar:tag"
define enumerate-build-dep-for-docker-build-inner
$(if $(filter $(DOCKER_USER)/$(DOCKER_REPO):%,$(1)),$(patsubst $(DOCKER_USER)/$(DOCKER_REPO):%,%,$(1)))
endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
define enumerate-build-dep-for-docker-build
$(call enumerate-build-dep-for-docker-build-inner,$(call base-image-from-path,$(1)))
endef

# $(1): suite
# $(2): arch
# $(3): func
define enumerate-additional-tags-for
$(if $(filter amd64,$(2)),$(1)$(if $(3),-$(3))) $(if $(filter $(LATEST),$(1)),latest-$(2)$(if $(3),-$(3)) $(if $(filter amd64,$(2)),latest$(if $(3),-$(3))))
endef

# $(1): relative directory path, e.g. "jessie/amd64"
define is-scratch
$(filter scratch,$(call base-image-from-path,$(1)))
endef

# $(1): relative directory path, e.g. "jessie/amd64"
define maybe-qemu-arch
$(if $(call is-scratch,$(1)),$(call get-qemu-arch,$(DEB_SYSTEM_ARCH),$(call arch-name-from-path,$(1))))
endef

define do-debuerreotype-rootfs-tarball
@echo "$@ <= building";
$(hide) [ ! -d "$(@D)" ] || rm -rf "$(@D)"; \
mkdir -p "$(@D)"; \
args=( --arch="$(PRIVATE_ARCH)" ); \
if [ -n "$(call get-qemu-arch,$(DEB_SYSTEM_ARCH),$(PRIVATE_ARCH))" ]; then \
  args+=( --qemu ); \
fi; \
args+=( "$(@D)" ); \
args+=( "$(PRIVATE_SUITE)" ); \
args+=( "@$(DEB_SNAPSHOT_EPOCH)" ); \
$(PRIVATE_ENVS) nice ionice -c 3 "$(MKIMAGE)" "$${args[@]}" 2>&1 | tee "$(@D)/build.log"; \
touch "$@"

endef

# $(1): relative directory path, e.g. "jessie/amd64"
# $(2): target name, e.g. jessie-amd64
# $(3): suite name, e.g. jessie
# $(4): arch name, e.g. amd64
define define-build-debuerreotype-rootfs-tarball-target
$(1)/debuerreotype/stamp: PRIVATE_TARGET := $(2)
$(1)/debuerreotype/stamp: PRIVATE_SUITE := $(3)
$(1)/debuerreotype/stamp: PRIVATE_ARCH := $(4)
$(1)/debuerreotype/stamp: PRIVATE_DEBUERREOTYPE_ARCH := $(call debuerreotype-arch-name,$(4))
$(1)/debuerreotype/stamp: PRIVATE_ENVS := $(call get-part,$(1),envs)
$(1)/debuerreotype/stamp:
	$$(call do-debuerreotype-rootfs-tarball)

endef

define do-rootfs-tarball
@echo "$@ <= building";
$(hide) if [ -z "$<" ]; then \
  wget --quiet --continue -O "$@" "$(DEBUERREOTYPE_ARTIFACTS_URL)/dist-$(PRIVATE_DEBUERREOTYPE_ARCH)/$(PRIVATE_SUITE)$(if $(PRIVATE_FUNC),/$(PRIVATE_FUNC))/rootfs.tar.xz"; \
else \
  cp "$(PRIVATE_SUITE)/$(PRIVATE_ARCH)/debuerreotype/$(DEBUERREOTYPE_SERIAL)/$(PRIVATE_ARCH)/$(PRIVATE_SUITE)$(if $(PRIVATE_FUNC),/$(PRIVATE_FUNC))/rootfs.tar.xz" "$@"; \
fi

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): suite name, e.g. jessie
# $(4): arch name, e.g. amd64
# $(5): func name, e.g. scm
define define-build-rootfs-tarball-target
$(2): $(1)/rootfs.tar.xz
$(1)/rootfs.tar.xz: PRIVATE_TARGET := $(2)
$(1)/rootfs.tar.xz: PRIVATE_PATH := $(1)
$(1)/rootfs.tar.xz: PRIVATE_SUITE := $(3)
$(1)/rootfs.tar.xz: PRIVATE_ARCH := $(4)
$(1)/rootfs.tar.xz: PRIVATE_FUNC := $(5)
$(1)/rootfs.tar.xz: PRIVATE_INCLUDE := $(call get-part,$(1),include)
$(1)/rootfs.tar.xz: PRIVATE_MIRROR := $(call get-part,$(1),mirror)
$(1)/rootfs.tar.xz: PRIVATE_DEBUERREOTYPE_ARCH := $(call debuerreotype-arch-name,$(4))
$(1)/rootfs.tar.xz: PRIVATE_ENVS := $(call get-part,$(1),envs)
$(1)/rootfs.tar.xz: PRIVATE_DEBOOTSTRAP_ARGS := $(call get-part,$(1),debootstrap-args)
$(1)/rootfs.tar.xz: $(if $(shell wget --quiet --spider "$(DEBUERREOTYPE_ARTIFACTS_URL)/dist-$(call debuerreotype-arch-name,$(4))/$(3)$(if $(5),/$(5))/rootfs.tar.xz" && echo yes),,$(3)/$(4)/debuerreotype/stamp)
$(1)/rootfs.tar.xz:
	$$(call do-rootfs-tarball)

docker-build-$(2): $(1)/rootfs.tar.xz

endef

define do-docker-build
@echo "$@ <= docker building $(PRIVATE_PATH)";
$(hide) target_tag=$(DOCKER_USER)/$(DOCKER_REPO):$(PRIVATE_TARGET); \
if [ -n "$(FORCE)" -o -z "$$($(DOCKER) inspect $${target_tag} 2>/dev/null | grep Created)" ]; then \
  if [ -n "$(PRIVATE_QEMU_ARCH)" ]; then \
    staging_tag=$${target_tag}-staging; \
    $(DOCKER) build --tag $${staging_tag} $(PRIVATE_PATH); \
    cp $(PRIVATE_QEMU_SUITE)/$(DEB_SYSTEM_ARCH)/qemu/qemu-$(PRIVATE_QEMU_ARCH)-static $(PRIVATE_PATH); \
    { echo "FROM $${staging_tag}"; echo "ADD qemu-$(PRIVATE_QEMU_ARCH)-static /usr/bin/qemu-$(PRIVATE_QEMU_ARCH)-static"; } | \
      tee $(PRIVATE_PATH)/Dockerfile.real; \
    $(DOCKER) build --tag $${target_tag} --file $(PRIVATE_PATH)/Dockerfile.real $(PRIVATE_PATH); \
    $(DOCKER) rmi $${staging_tag}; \
    rm "$(PRIVATE_PATH)/Dockerfile.real" "$(PRIVATE_PATH)/qemu-$(PRIVATE_QEMU_ARCH)-static"; \
  else \
    $(DOCKER) build -t $${target_tag} $(PRIVATE_PATH); \
  fi; \
  $(DOCKER) run --rm $${target_tag} dpkg-query -f '$${Package}\t$${Version}\n' -W > "$(PRIVATE_PATH)/build.manifest"; \
fi

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): suite name, e.g. jessie
# $(4): arch name, e.g. amd64
# $(5): func name, e.g. scm
define define-docker-build-target
.PHONY: docker-build-$(2)
$(2): docker-build-$(2)
docker-build-$(2): PRIVATE_TARGET := $(2)
docker-build-$(2): PRIVATE_PATH := $(1)
docker-build-$(2): PRIVATE_SUITE := $(3)
docker-build-$(2): PRIVATE_ARCH := $(4)
docker-build-$(2): PRIVATE_FUNC := $(5)
docker-build-$(2): PRIVATE_QEMU_SUITE := $(call get-qemu-suite,$(3))
docker-build-$(2): PRIVATE_QEMU_ARCH := $(call maybe-qemu-arch,$(1))
docker-build-$(2): $(if $(call maybe-qemu-arch,$(1)),qemu-binary-$(call get-qemu-suite,$(3)))
docker-build-$(2): $(call enumerate-build-dep-for-docker-build,$(1))
	$$(call do-docker-build)

endef

define do-qemu-binary
$(hide) if [ -z "$$(ls -1 $(PRIVATE_PATH)/qemu/qemu-*-static 2>/dev/null)" ]; then \
  mkdir -p "$(PRIVATE_PATH)/qemu"; \
  $(DOCKER) run --rm --volume "$(abspath $(PRIVATE_PATH)/qemu)":/export $(DOCKER_USER)/$(DOCKER_REPO):$(PRIVATE_TARGET) \
    /bin/sh -xc '(cd /tmp; apt-get update --quiet && apt-get download qemu-user-static && dpkg-deb -x *.deb .) && cp /tmp/usr/bin/qemu-*-static /export'; \
  $$(ls -1 $(PRIVATE_PATH)/qemu/qemu-*-static | head -n 1) -version; \
fi

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): suite name, e.g. jessie
define define-qemu-binary-target
.PHONY: qemu-binary-$(3)
qemu-binary-$(3): PRIVATE_PATH := $(1)
qemu-binary-$(3): PRIVATE_TARGET := $(2)
qemu-binary-$(3): docker-build-$(2)
	$$(call do-qemu-binary)

endef

define do-docker-tag
@echo "$@ <= docker tagging $(PRIVATE_PATH)";
$(hide) for tag in $(PRIVATE_TAGS); do \
  $(DOCKER) tag $(DOCKER_USER)/$(DOCKER_REPO):$(PRIVATE_TARGET) $(DOCKER_USER)/$(DOCKER_REPO):$${tag}; \
done

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): suite name, e.g. jessie
# $(4): arch name, e.g. amd64
# $(5): func name, e.g. scm
define define-docker-tag-target
.PHONY: docker-tag-$(2)
$(2): docker-tag-$(2)
docker-tag-$(2): PRIVATE_TARGET := $(2)
docker-tag-$(2): PRIVATE_PATH := $(1)
docker-tag-$(2): PRIVATE_TAGS := $(call enumerate-additional-tags-for,$(3),$(4),$(5))
docker-tag-$(2): docker-build-$(2)
	$$(call do-docker-tag)

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
define define-target-from-path
$(eval target := $(call target-name-from-path,$(1)))
$(eval suite := $(call suite-name-from-path,$(1)))
$(eval arch := $(call arch-name-from-path,$(1)))
$(eval func := $(call func-name-from-path,$(1)))
$(eval suite_arch_target := $(call suite-arch-target-name,$(suite),$(arch)))
$(eval ALL_SUITE_ARCH_TARGETS := $(sort $(ALL_SUITE_ARCH_TARGETS) $(suite_arch_target)))

.PHONY: $(target) $(suite) $(arch) $(func)
all: $(target)
$(suite): $(target)
$(arch): $(target)
$(if $(func),$(func): $(target))
$(suite_arch_target): $(target)
$(target):
	@echo "$$@ done"

$(if $(func),,$(call define-build-debuerreotype-rootfs-tarball-target,$(1),$(target),$(suite),$(arch)))
$(if $(call is-scratch,$(1)), \
  $(call define-build-rootfs-tarball-target,$(1),$(target),$(suite),$(arch),$(func)))
$(call define-docker-build-target,$(1),$(target),$(suite),$(arch),$(func))
$(if $(filter $(DEB_SYSTEM_ARCH)-,$(arch)-$(func)), \
  $(call define-qemu-binary-target,$(1),$(target),$(suite)))
$(if $(strip $(call enumerate-additional-tags-for,$(suite),$(arch),$(func))), \
  $(call define-docker-tag-target,$(1),$(target),$(suite),$(arch),$(func)))

endef

all: .travis.yml
	@echo "Build $(DOCKER_USER)/$(DOCKER_REPO) done"

.PHONY: .travis.yml
.travis.yml:
	$(hide) TMP_TRAVIS=$$(mktemp); \
	travisEnv=; \
	$(foreach t,$(patsubst all-%,%,$(ALL_SUITE_ARCH_TARGETS)),travisEnv+='\n  - VARIANT=$(t)';) \
	awk -v 'RS=\n\n' '($$1 == "env:") { $$0 = substr($$0, 0, index($$0, "matrix:") + length("matrix:")) "'"$$travisEnv"'" } { printf "%s%s", $$0, RS }' "$@" > "$${TMP_TRAVIS}"; \
	(diff -q "$@" "$${TMP_TRAVIS}" >/dev/null && rm -f "$${TMP_TRAVIS}") || mv "$${TMP_TRAVIS}" "$@"

$(foreach f,$(shell find . -type f -name Dockerfile | cut -d/ -f2-), \
  $(eval path := $(patsubst %/Dockerfile,%,$(f))) \
  $(if $(if $(NO_SKIP),,$(wildcard $(path)/skip)), \
    $(info Skipping $(path): $(shell cat $(path)/skip)), \
    $(eval $(call define-target-from-path,$(path))) \
  ) \
)

.PHONY: debian ubuntu
debian: squeeze wheezy jessie stretch buster sid
ubuntu: precise trusty utopic vivid wily xenial yakkety zesty
