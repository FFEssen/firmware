#!/bin/bash
# (c) 2014-2016 Freifunk Hochstift <kontakt@hochstift.freifunk.net>
#
# This script builds the firmware by the environment variables given, the
# first two being mandatory:
#
# BASE        = Gluon Version (tag or commit, i.e. v2014.4)
# BRANCH      = Firmware Branch (stable/testing/experimental)
# VERSION     = the version tag (can only be empty if BRANCH=experimental)
#
# optional:
# AUTOUPDATER = force Autoupdater Branch (stable/testing/experimental/off)
# BROKEN      = 0 (default) or 1, build the untested hardware model firmwares, too
# BUILD_TS    = build timestamp (format: %Y-%m-%d %H:%M:%S)
# CLEAN       = DIRCLEAN perform "make dirclean" before build (BRANCH==stable/testing) or CLEAN perform "make clean" (BRANCH==experimental) or NONE
# FAKETIME_LIB = path to libfaketime.so.1 if it is not in the standard location
# KEY_DIR     = specify directory for gluon-opkg-key
# MAKEJOBS    = number of compiler processes running in parallel (default: number of CPUs/Cores)
# NO_FAKETIME = 0 (default) or 1, disables the use of Faketime
# PRIORITY    = determines the number of day a rollout phase should last at most
# SITE_ID     = specific site repository commit-id (leave blank to use HEAD)
# SITE_REPO_FETCH_METHOD = http, everything except "git" will use the HTTP method for fetchting site repo
# TARGETS     = a space separated list of target platforms (if unset, all platforms will be build)
# VERBOSE     = 0 (default) or 1, call the make commands with 'V=s' to see actual errors better
#


### includes
. functions.sh

### static variables
MY_DIR=$(dirname $0)
MY_DIR=$(readlink -f "${MY_DIR}")
DEFAULT_KEY_DIR="${MY_DIR}/opkg-keys"
CODE_DIR="${MY_DIR}/src"
GLUON_BUILD_DIR="${CODE_DIR}/build"
SITE_DIR="${CODE_DIR}/site"
PATCH_DIR="${SITE_DIR}/patches"
OUTPUT_DIR="${MY_DIR}/output"
IMAGE_DIR="${CODE_DIR}/output/images"
MODULE_DIR="${CODE_DIR}/output/modules"
VERSIONS_INFO_DIR="${MY_DIR}/versions"

BUILD_INFO_FILENAME="build-info.txt"
SITE_REPO_URL="github.com/ffessen/site-ffe"
LANG=C

pushd ${MY_DIR} > /dev/null

### ERROR handling
[ -n "${BASE}" ] || abort "Please specify BASE environment variable (Gluon, i.e. 'v2014.3' or commit-id)."
[ -n "${BRANCH}" ] || abort "Please specify BRANCH environment variable."
[ "${BRANCH}" == "experimental" -o "${BASE}" != "HEAD" ] || abort "HEAD is not an allowed BASE-identifier for non-experimental builds. Either use a tagged commit or the commit-SHA itself."
[ -n "${VERSION}" -o "${BRANCH}" == "experimental" ] || abort "Please specify VERSION environment variable (not necessary for experimental branch)."
[ "${BRANCH}" == "experimental" -o ! -r "${VERSIONS_INFO_DIR}/${VERSION}" ] || abort "There exists a version file for '${VERSION}' ... you are trying to do something really stupid, aren't you?"

### set reasonable defaults for unset environment variables
[ -n "${AUTOUPDATER}" ] || AUTOUPDATER=${BRANCH}
if [ -n "${BROKEN}" ]; then
	if [ "${BROKEN}" -eq "1" ]; then
		export BROKEN
	else
		unset BROKEN
	fi
fi
[ -n "${BUILD_TS}" ] || BUILD_TS=$(date +"%Y-%m-%d %H:%M:%S")

if [ -z "${CLEAN}" ]; then
	if [ "${BRANCH}" == "experimental" ]; then
		CLEAN="clean"
	else
		CLEAN="dirclean"
	fi
fi

if [ -n "${KEY_DIR}" ]; then
	KEY_DIR=$(readlink -f "${KEY_DIR}")
else
	KEY_DIR="${DEFAULT_KEY_DIR}"
fi
[ -e "${KEY_DIR}" ] || mkdir -p ${KEY_DIR}
[ "$?" -eq "0" ] || abort "Unable to create output directory: ${KEY_DIR}"

[ -n "${MAKEJOBS}" ] || MAKEJOBS=$(grep -c "^processor" /proc/cpuinfo)
[ -n "${NO_FAKETIME}" ] || NO_FAKETIME=0
[ -n "${PRIORITY}" ] || PRIORITY=0
[ -n "${SITE_REPO_FETCH_METHOD}" ] || SITE_REPO_FETCH_METHOD="http"
[ -n "${VERBOSE}" ] || VERBOSE=0

if [ "${SITE_REPO_FETCH_METHOD}" != "git" ]; then
	SITE_REPO_URL="https://${SITE_REPO_URL}"
else
	SITE_REPO_URL="git@${SITE_REPO_URL}"
fi

MAKE_PARAM=""
[ "${VERBOSE}" -eq "1" ] && MAKE_PARAM="${MAKE_PARAM} V=s"

### INIT /src IF NECESSARY
if [ ! -d "${CODE_DIR}" ]; then
	info "Code directory does not exist yet - fetching Gluon ..."
	git clone https://github.com/freifunk-gluon/gluon.git "${CODE_DIR}"
	[ "$?" -eq "0" ] || abort "Failed to fetch Gluon repository."
fi

### INIT /src/site IF NECESSARY
if [ ! -d "${SITE_DIR}" ]; then
	info "Site repository does not exist, fetching it ..."
	git clone "${SITE_REPO_URL}" "${SITE_DIR}"
	[ "$?" -eq "0" ] || abort "Failed to fetch SITE repository."
fi

pushd ${CODE_DIR} > /dev/null

### CHECKOUT GLUON
progress "Checking out GLUON '${BASE}' ..."
# check if gluon got modified and bail out if necessary
[ "$(git status --porcelain)" ] && abort "Local changes to peers directory. Cowardly refusing to update gluon repository." >&2
git fetch
git checkout -q ${BASE}
[ "$?" -eq "0" ] || abort "Failed to checkout '${BASE}' gluon base version, mimimi." >&2
git show-ref --verify --quiet refs/remotes/origin/${BASE}
if [ "$?" -eq "0" ]; then
	git pull
	[ "$?" -eq "0" ] || abort "Failed to get newest '${BASE}' in gluon repository, mimimi."
fi
GLUON_COMMIT=$(git rev-list --max-count=1 HEAD)


### CHECKOUT SITE REPO
progress "Checking out SITE REPO ..."
pushd ${SITE_DIR} > /dev/null
if [ $(git remote | wc -l) -ge "1" ]; then
	git fetch
	# TODO: check if site got modified locally and bail out if necessary
	if [ -z "${SITE_ID}" ]; then
		# no specific site given - get the most current one
		git checkout -q ${BRANCH}
		git branch -r | grep ${BRANCH} > /dev/null
		if [ "$?" -eq "0" ]; then
			git rebase
			[ "$?" -eq "0" ] || abort "Failed to get newest '${BRANCH}' in site repository, mimimi."
		fi
	else
		# fetch site repo updates
		git fetch || true
		# commit given - use this one
		git checkout -q ${SITE_ID}
		[ "$?" -eq "0" ] || abort "Failed to checkout requested site commit '${SITE_ID}', mimimi."
	fi
fi
SITE_COMMIT=$(git rev-list --max-count=1 HEAD)
popd > /dev/null #${SITE_DIR}

### APPLY PATCHES TO GLUON
progress "Applying Patches ..."
git checkout -B patching "${BASE}"
if [ -d "${PATCH_DIR}" -a "$(echo ${PATCH_DIR}/*.patch)" ]; then
	git am --whitespace=nowarn ${PATCH_DIR}/*.patch || (
		git am --abort
		git checkout patched
		git branch -D patching
		false
	)
	[ "$?" -eq "0" ] || abort "Failed to apply patches, mimimi."
fi
git branch -M patched


### DIRCLEAN
if [ -d "${GLUON_BUILD_DIR}/" -a "${CLEAN}" == "dirclean" ]; then
	progress "Cleaning your build environment (make dirclean) ..."
	make dirclean
fi

### PREPARE
progress "Preparing the build environment (make update) ..."
make update
[ "$?" -eq "0" ] || abort "Failed to update the build environment, mimimi."
popd > /dev/null #${CODE_DIR}

### set reasonable defaults for ${TARGETS} and ${BRANCH} if unset
if [ -z "${TARGETS}" ]; then
        TARGETS=$(make list-targets | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        info "building all targets: '${TARGETS}'"
fi
if [ "${BRANCH}" == "experimental" -a -z "${VERSION}" ] ; then
        VERSION=$(make default-release)
        info "EXPERIMENTAL FIRMWARE: using version tag '${VERSION}'"
fi

# we are now ready to produce the firmware images, so let's "save" our state
build_info_path="${OUTPUT_DIR}/${BRANCH}/${BUILD_INFO_FILENAME}"
progress "Saving build information to: ${build_info_path}"
[ -n "${build_info_path}" -a -f "${build_info_path}" ] && rm -f ${build_info_path}
mkdir -p $(dirname ${build_info_path})
[ "$?" -eq "0" ] || abort "Unable to create output directory: $(dirname ${build_info_path})"
touch $(dirname ${build_info_path})
[ "$?" -eq "0" ] || abort "Cannot create build information file: ${build_info_path}"
echo "VERSION=${VERSION}" >> ${build_info_path}
echo "GLUON=${GLUON_COMMIT} # ${BASE}" >> ${build_info_path}
echo "BRANCH=${BRANCH}" >> ${build_info_path}
echo "SITE=${SITE_COMMIT} # ${VERSION}" >> ${build_info_path}
echo "TARGETS=${TARGETS}" >> ${build_info_path}
echo "TS=${BUILD_TS}" >> ${build_info_path}

### SETUP FAKETIME (consistent build)
if [ "${NO_FAKETIME}" -eq "0" ]; then
	[ -z "${FAKETIME_LIB}" ] && FAKETIME_LIB="/usr/lib/${MACHTYPE}-${OSTYPE}/faketime/libfaketime.so.1"
	export LD_PRELOAD="${FAKETIME_LIB}"
	export FAKETIME="${BUILD_TS}"
fi

### restore gluon-opkg-key, if already exists
if [ -e "${KEY_DIR}/gluon-opkg-key" -a -e "${KEY_DIR}/gluon-opkg-key.pub" ]; then
	info "gluon-opkg-key already exists, restoring it."
	mkdir -p ${GLUON_BUILD_DIR}/
	[ "$?" -eq "0" ] || abort "Unable to create directory: ${GLUON_BUILD_DIR}/"
	cp -f ${KEY_DIR}/gluon-opkg-key* ${GLUON_BUILD_DIR}/
	[ "$?" -eq "0" ] || abort "Unable to copy gluon-opkg-key."
fi

### BUILD FIRMWARE
progress "Building the firmware - please stand by!"
pushd ${CODE_DIR} > /dev/null

for target in ${TARGETS} ; do
	# configure build environment for our current target
	export GLUON_TARGET="${target}"
	export GLUON_RELEASE="${VERSION}"
	[ "${AUTOUPDATER}" != "off" ] && export GLUON_BRANCH="${AUTOUPDATER}"

	# prepare build environment for our current target
	progress "${target}: Preparing build environment."
	if [ "${CLEAN}" == "clean" ]; then
		make clean
		[ "$?" -eq "0" ] || abort "${target}: Unable to clean environment."
	fi

	make -j ${MAKEJOBS} prepare-target ${MAKE_PARAM}
	[ "$?" -eq "0" ] || abort "${target}: Unable to build environment."

	# need to have a toolchain for the particular target 
	progress "${target}: Building toolchain."
	make -j ${MAKEJOBS} toolchain/install ${MAKE_PARAM}
	[ "$?" -eq "0" ] || abort "${target}: Unable to build toolchain."

	# now we can start building the images for the target platform
	progress "${target}: Building FFE-flavoured Gluon firmware. You'd better go and fetch some c0ffee!"
	make -j ${MAKEJOBS} prepare ${MAKE_PARAM}
	[ "$?" -eq "0" ] || abort "${target}: Unable to build firmware."

	# finally compile the firmware binaries
	progress "${target}: Compiling binary firmware images."
	make -j ${MAKEJOBS} images ${MAKE_PARAM}
	[ "$?" -eq "0" ] || abort "${target}: Unable to assemble images."

	# compile the modules
	progress "${target}: Compiling modules."
	make -j ${MAKEJOBS} modules ${MAKE_PARAM}
	[ "$?" -eq "0" ] || abort "${target}: Unable to build modules."
done

popd > /dev/null #${CODE_DIR}

# compress all binaries into 7z archive
if [ -d "${IMAGE_DIR}" ]; then
	progress "Assembling images.7z ..."
	pushd ${IMAGE_DIR} > /dev/null
	[ -e "${OUTPUT_DIR}/${BRANCH}/images.7z" ] && rm "${OUTPUT_DIR}/${BRANCH}/images.7z"
	7z a -mmt=on -xr!*.manifest "${OUTPUT_DIR}/${BRANCH}/images.7z" ./sysupgrade/* ./factory/*
	[ "$?" -eq "0" ] || abort "Failed to assemble images (did you install p7zip-full?)."
	popd > /dev/null #${IMAGE_DIR}
fi

# compress modules into 7z archive
if [ -d "${MODULE_DIR}" ]; then
	progress "Assembling modules.7z ..."
	pushd ${MODULE_DIR} > /dev/null
	[ -e "${OUTPUT_DIR}/${BRANCH}/modules.7z" ] && rm "${OUTPUT_DIR}/${BRANCH}/modules.7z"
	7z a -mmt=on "${OUTPUT_DIR}/${BRANCH}/modules.7z" ./* > /dev/null
	[ "$?" -eq "0" ] || abort "Failed to assemble modules."
	popd > /dev/null #${MODULE_DIR}
fi

# generate and copy manifests
progress "Generating and copying manifest ..."
pushd ${CODE_DIR} > /dev/null
GLUON_PRIORITY=${PRIORITY} GLUON_BRANCH=${BRANCH} make manifest
[ "$?" -eq "0" ] || abort "Failed to generate the manifest, try running 'make manifest' in '$CODE_DIR' directory manually."
cp "${CODE_DIR}/output/images/sysupgrade/${BRANCH}.manifest" "${OUTPUT_DIR}/${BRANCH}/"
popd > /dev/null #${CODE_DIR}

# Saving a copy of the build info file as reference
progress "Building a greater and brighter firmware finished successfully. Saving build information at: ${VERSIONS_INFO_DIR}/${VERSION}"
cp -p "${build_info_path}" "${VERSIONS_INFO_DIR}/${VERSION}"

# Saving a copy of gluon-opkg-key
[ -e "${KEY_DIR}/gluon-opkg-key" -a -e "${KEY_DIR}/gluon-opkg-key.pub" ] || cp ${GLUON_BUILD_DIR}/gluon-opkg-key* ${KEY_DIR}/
[ "$?" -eq "0" ] || abort "Failed to save gluon-opkg-key, try to execute 'cp ${GLUON_BUILD_DIR}/gluon-opkg-key* ${KEY_DIR}/' manually"

# The end. Finally.
success "We're done, go and enjoy your new firmware (${VERSION}) in ${OUTPUT_DIR}/${BRANCH}!"
popd > /dev/null #${MY_DIR}

