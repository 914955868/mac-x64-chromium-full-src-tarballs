#!/bin/bash
# This script packages a complete, buildable Chromium source environment into a
# tarball: full source, third_party dependencies, the prebuilt Clang/LLVM
# toolchain, the Rust toolchain, Linux sysroot(s), hook dependencies, PGO
# profiles, plus depot_tools and the gclient config.
#
# Unlike the "distribution tarball" tooling this script does NOT strip anything
# needed to build Chromium offline.
#
# Usage:
#   package_chromium_full.sh <version> <arch>
#
# Example:
#   package_chromium_full.sh 140.0.7339.82 arm64
#   package_chromium_full.sh 126.0.6478.126 loong64
#
# Environment:
#   ZSTD_LEVEL     zstd compression level (default: 6)
#   SPLIT_PART_SZ  split part size (default: 1900M, below the 2GiB GitHub
#                  Release per-file limit)

base=$(cd "$(dirname $0)" && pwd)
source "${base}/logging.sh" || exit

set -euo pipefail
umask 022

SPLIT_PART_SZ="${SPLIT_PART_SZ:-1900M}"
ZSTD_LEVEL="${ZSTD_LEVEL:-6}"
PGO_GS_URL_BASE="chromium-optimization-profiles/pgo_profiles"

# LoongArch64 (loong64) is not supported by upstream Chromium: there is no
# official sysroot or Clang/LLVM toolchain for it. Both are provided by
# Loongnix, and only for Chromium 126.
LOONG64_CHROMIUM_MAJOR_VERSION="126"
LOONG64_SYSROOT_URL="http://ftp.loongnix.cn/browser/build/sysroot/debian_bullseye_loongarch64-sysroot.tar.bz2"
LOONG64_TOOLCHAIN_URL="http://ftp.loongnix.cn/browser/build/toolchain/Release+Asserts-126.tar.bz2"
LOONG64_PATCH_URL="https://github.com/loongson/chromium/raw/loongarch-patches/chromium126/0001-la64-cross-CH126-Add-loongarch-build-support-for-old-new-w.patch"
LOONG64_PATCH_FILE="0001-la64-cross-CH126-Add-loongarch-build-support-for-old-new-w.patch"

log_disk() {
	clog "Disk usage:"
	df -h . | sed 's/^/    /'
}

# This function clones one of Google's Chromium-related tool repositories.
#
# Usage:
#   get_google_repo REPO_BASENAME
#
get_google_repo() {
	local repo="${1}"
	if [[ -d "${repo}" ]]; then
		clog "${repo} repository already exists, pulling latest changes"
		pushd "${repo}" &> /dev/null || die "Failed to enter ${repo} directory"
		if [ "$(git symbolic-ref --short -q HEAD)" == "" ]; then
			clog "Currently in a detached HEAD state, switching to main branch"
			git switch main || die "Failed to switch to main branch in ${repo} repository"
		fi
		git pull || die "Failed to pull latest changes in ${repo} repository"
		popd &> /dev/null || die "Failed to exit ${repo} directory"
	else
		clog "Cloning ${repo} repository"
		git clone -q --depth=1 "https://chromium.googlesource.com/chromium/tools/${repo}.git" ||
			die "Failed to clone ${repo} repository"
	fi
}

# This function configures the gclient for Chromium development.
#
# Usage:
#   configure_gclient(version)
#
configure_gclient() {
	local version="${1}"
	if [ -z "${version}" ]; then
		die "${FUNCNAME}: No version specified"
	fi
	clog "Configuring gclient with version ${version}"
	gclient config --name src "https://chromium.googlesource.com/chromium/src.git@${version}" ||
		die "Failed to configure gclient with version ${version}"
	echo "target_os = [ 'linux' ]" >> .gclient
}

sync_sources() {
	clog "Syncing Chromium sources (no history, no hooks)"
	gclient sync -D --nohooks --no-history ||
		die "gclient sync failed"
}

# LoongArch64 is not supported by upstream Chromium, so the Loongson port
# patch has to be applied on top of the checked out sources. It is applied
# right after the sync so a broken patch fails before the expensive hooks.
#
# Usage:
#   apply_target_patches(arch)
#
apply_target_patches() {
	local arch="${1}"
	case "${arch}" in
		loong64)
			clog "Downloading LoongArch64 adaptation patch"
			curl --fail --location --retry 3 --retry-delay 5 --max-time 600 \
				--no-progress-meter -o "${LOONG64_PATCH_FILE}" "${LOONG64_PATCH_URL}" ||
				die "Failed to download ${LOONG64_PATCH_URL}"

			clog "Applying ${LOONG64_PATCH_FILE} to src"
			pushd src &> /dev/null || die "Failed to enter src directory"
			patch -Np1 -i "../${LOONG64_PATCH_FILE}" ||
				die "Failed to apply ${LOONG64_PATCH_FILE} (is \"patch\" installed?)"
			popd &> /dev/null || die "Failed to leave src directory"

			rm -f "${LOONG64_PATCH_FILE}"
			;;
	esac
}

run_hooks() {
	clog "Running gclient hooks (Clang/LLVM, sysroots, Node.js, ...)"
	gclient runhooks ||
		die "gclient runhooks failed"
}

download_pgo_profiles() {
	clog "Downloading Chromium PGO profiles"
	# Pre-downloading places the profile under src/chrome/build/pgo_profiles/,
	# where "gn gen" (chrome_pgo_phase=2) resolves it without network access.
	src/tools/update_pgo_profiles.py \
		--target=linux \
		update \
		--gs-url-base="${PGO_GS_URL_BASE}" ||
		die "Failed to update PGO profiles"
}

download_v8_pgo_profiles() {
	clog "Downloading V8 PGO profiles"
	# --check-v8-revision was added in later V8 versions (e.g. v8 13.x used by
	# Chromium 140) and is unknown to older ones (e.g. v8 12.6 used by Chromium
	# 126), so fall back to the plain invocation.
	if ! src/v8/tools/builtins-pgo/download_profiles.py \
		--force \
		--check-v8-revision \
		--depot-tools depot_tools \
		download
	then
		cwarn "--check-v8-revision unsupported on this V8 version, retrying without it"
		src/v8/tools/builtins-pgo/download_profiles.py \
			--force \
			--depot-tools depot_tools \
			download ||
			die "Failed to download V8 PGO profiles"
	fi
}

# This function downloads a tarball and extracts it into a directory.
#
# Usage:
#   download_and_extract URL DEST_DIR
#
download_and_extract() {
	local url="${1}"
	local dest="${2}"
	local tmp_dir

	tmp_dir=$(mktemp -d) || die "Failed to create a temporary download directory"
	local archive="${tmp_dir}/$(basename "${url}")"

	clog "Downloading ${url}"
	curl --fail --location --retry 3 --retry-delay 5 --max-time 7200 \
		--no-progress-meter -o "${archive}" "${url}" ||
		die "Failed to download ${url}"

	clog "Extracting $(basename "${archive}") into ${dest}"
	mkdir -p "${dest}" || die "Failed to create ${dest}"
	tar -xjf "${archive}" -C "${dest}" ||
		die "Failed to extract ${archive} into ${dest}"

	rm -rf "${tmp_dir}"
}

install_target_sysroot() {
	local arch="${1}"
	case "${arch}" in
		amd64)
			clog "amd64/i386 sysroots are installed by hooks, nothing to do"
			;;
		arm64)
			clog "Installing arm64 Linux sysroot"
			src/build/linux/sysroot_scripts/install-sysroot.py --arch=arm64 ||
				die "Failed to install arm64 sysroot"
			;;
		loong64)
			clog "Installing loong64 (LoongArch64) Linux sysroot from Loongnix"
			download_and_extract "${LOONG64_SYSROOT_URL}" "src/build/linux" ||
				die "Failed to install loong64 sysroot"
			;;
	esac
}

# The upstream prebuilt Clang/LLVM toolchain has no LoongArch support, so
# loong64 builds use the Loongnix toolchain instead. It is installed after
# runhooks so the clang hook cannot overwrite it.
install_target_toolchain() {
	local arch="${1}"
	case "${arch}" in
		loong64)
			clog "Installing loong64 (LoongArch64) Clang/LLVM toolchain from Loongnix"
			rm -rf "src/third_party/llvm-build/Release+Asserts"
			download_and_extract "${LOONG64_TOOLCHAIN_URL}" "src/third_party/llvm-build" ||
				die "Failed to install loong64 toolchain"
			;;
	esac
}

verify_toolchain() {
	local arch="${1}"
	local summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

	clog "Verifying toolchain and dependencies"

	local clang_bin="src/third_party/llvm-build/Release+Asserts/bin/clang"
	if [ -x "${clang_bin}" ]; then
		local clang_version
		clang_version=$("${clang_bin}" --version | head -n 1)
		clog "Clang: ${clang_version}"
		echo "- Clang: \`${clang_version}\`" >> "${summary}" 2> /dev/null || true
	else
		die "Clang toolchain not found at ${clang_bin}"
	fi

	local rustc_bin
	rustc_bin=$(find src/third_party/rust-toolchain -maxdepth 3 -type f -name rustc 2> /dev/null | head -n 1 || true)
	if [ -n "${rustc_bin}" ] && [ -x "${rustc_bin}" ]; then
		local rust_version
		rust_version=$("${rustc_bin}" --version | head -n 1)
		clog "Rust: ${rust_version}"
		echo "- Rust: \`${rust_version}\`" >> "${summary}" 2> /dev/null || true
	else
		die "Rust toolchain not found under src/third_party/rust-toolchain"
	fi

	local sysroot_pattern="*${arch}-sysroot"
	case "${arch}" in
		loong64) sysroot_pattern="*loongarch64-sysroot" ;;
	esac

	local sysroot
	sysroot=$(find src/build/linux -maxdepth 1 -type d -name "${sysroot_pattern}" | head -n 1 || true)
	if [ -n "${sysroot}" ]; then
		clog "Sysroot: $(basename "${sysroot}")"
		echo "- Sysroot: \`$(basename "${sysroot}")\`" >> "${summary}" 2> /dev/null || true
	else
		die "No ${arch} sysroot found under src/build/linux"
	fi
}

generate_manifest() {
	local version="${1}"
	local arch="${2}"
	local revision sysroots
	revision=$(git -C src rev-parse HEAD 2> /dev/null || echo "unknown")
	sysroots=$(find src/build/linux -maxdepth 1 -type d -name "*-sysroot" -printf "  - %f\n" 2> /dev/null | sort)

	clog "Generating chromium-build-manifest.txt"
	cat > chromium-build-manifest.txt <<EOF
Project: chromium-full-src-tarballs

Chromium version: ${version}
Chromium revision: ${revision}

Target architecture: ${arch}
Host architecture: $(uname -m)

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Included:
- Chromium source
- Chromium third_party dependencies
- Chromium build tools
- Chromium Clang/LLVM toolchain
- Chromium Rust toolchain
- Linux sysroot
- Chromium hook dependencies
- Chromium PGO profiles (linux)
- V8 PGO profiles
- depot_tools and gclient config

Packaged sysroots:
${sysroots}

Cross compilation:
- Prebuilt toolchains run on x86_64 Linux hosts
- Cross build target: target_os="linux", target_cpu="${arch}"
- Host apt dependencies are NOT included; run
  ./build/install-build-deps.sh on the build host before building

Excluded:
- src/out
- Git metadata
EOF

	if [ "${arch}" = "loong64" ]; then
		cat >> chromium-build-manifest.txt <<EOF

LoongArch64 (loong64):
- Chromium major version pinned to ${LOONG64_CHROMIUM_MAJOR_VERSION}
- Sysroot: ${LOONG64_SYSROOT_URL}
- Toolchain: ${LOONG64_TOOLCHAIN_URL}
- Patch: ${LOONG64_PATCH_URL}
EOF
	fi
}

# Git metadata must go per README; the package targets offline builds and
# revision info is preserved in the manifest.
cleanup_before_pack() {
	clog "Removing Git metadata"
	find . -name .git -prune -exec rm -rf {} +
	clog "Removing build output directories (if any)"
	rm -rf src/out src/out_*
}

# Stream tar|zstd|split so the (large) uncompressed archive never exists on
# disk; the full-file hash is computed afterwards by reading the parts back.
export_tarball() {
	local version="${1}"
	local arch="${2}"
	local pkg_name="chromium-full-src-${version}-linux-${arch}"

	mkdir -p out
	clog "Exporting ${pkg_name}.tar.zst (parts of ${SPLIT_PART_SZ}, zstd level ${ZSTD_LEVEL})"
	log_disk

	tar \
		--use-compress-program="zstd -T0 -${ZSTD_LEVEL}" \
		-C "${PWD}" \
		-cf - \
		"${pkg_name}" \
		| split -b "${SPLIT_PART_SZ}" -d -a 3 - "out/${pkg_name}.tar.zst.part-"

	clog "Generating hashes"
	local full_hash
	full_hash=$(cat "out/${pkg_name}".tar.zst.part-* | sha256sum | cut -d ' ' -f 1)
	echo "${full_hash}  ${pkg_name}.tar.zst" > out/SHA256SUMS
	(
		cd out &&
			sha256sum "${pkg_name}".tar.zst.part-* > SHA256SUMS.parts
	)

	log_disk
	clog "Hashes:"
	cat out/SHA256SUMS
	cat out/SHA256SUMS.parts

	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		{
			echo "## Tarball"
			echo "- \`${pkg_name}.tar.zst\` sha256: \`${full_hash}\`"
			echo "- Parts: $(find out -name "${pkg_name}.tar.zst.part-*" | wc -l) x ${SPLIT_PART_SZ}"
		} >> "${GITHUB_STEP_SUMMARY}"
	fi
}

usage() {
	echo "Usage: $0 <version> <arch>"
	echo "Example: $0 140.0.7339.82 arm64"
	exit 1
}

main() {
	local version="${1:-}"
	local arch="${2:-}"

	if [ -z "${version}" ] || [ -z "${arch}" ]; then
		usage
	fi
	shift 2
	if [ "$#" -gt 0 ]; then
		die "Unknown argument: $1"
	fi

	case "${arch}" in
		arm64 | amd64 | loong64) ;;
		*) die "Unsupported target architecture: ${arch} (expected arm64, amd64 or loong64)" ;;
	esac

	if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		die "Invalid Chromium version: ${version}"
	fi

	# LoongArch64 is only available as a Chromium 126 port; there is no sysroot
	# or toolchain for any other version.
	if [ "${arch}" = "loong64" ] && [ "${version%%.*}" != "${LOONG64_CHROMIUM_MAJOR_VERSION}" ]; then
		die "LoongArch64 (loong64) requires Chromium ${LOONG64_CHROMIUM_MAJOR_VERSION}.x, got ${version}"
	fi

	# Some Google Python scripts start with "#!/usr/bin/env python"
	if ! python --version 2>&1 | grep -q '^Python 3\.'; then
		cwarn "\"python\" is not Python 3, creating a python3 shim in PATH"
		local shim_dir
		shim_dir=$(mktemp -d)
		ln -s "$(command -v python3)" "${shim_dir}/python"
		export PATH="${shim_dir}:${PATH}"
	fi

	export GIT_CONFIG_GLOBAL="${base}/gitconfig"
	export TZ=PST8PDT

	local pkg_name="chromium-full-src-${version}-linux-${arch}"

	clog "Packaging Chromium ${version} (target: ${arch}) into ${pkg_name}"
	log_disk

	mkdir -p "${pkg_name}"
	pushd "${pkg_name}" &> /dev/null || die "Failed to enter ${pkg_name}"

	get_google_repo depot_tools
	export PATH="${PWD}/depot_tools:${PATH}"

	configure_gclient "${version}"
	sync_sources
	apply_target_patches "${arch}"
	run_hooks
	#	download_pgo_profiles
	download_v8_pgo_profiles
	# Note: the Rust toolchain is fetched by the unconditional DEPS hook
	# (src/tools/rust/update_rust.py) during runhooks; verify_toolchain below
	# fails the run if it is missing.
	install_target_sysroot "${arch}"
	install_target_toolchain "${arch}"
	verify_toolchain "${arch}"
	generate_manifest "${version}" "${arch}"
	cleanup_before_pack

	popd &> /dev/null || die "Failed to leave ${pkg_name}"

	export_tarball "${version}" "${arch}"

	clog "Done: ${pkg_name}.tar.zst (split parts in out/)"
}

if [ "$#" -lt 2 ]; then
	usage
fi

main "$@"
