#!/bin/bash
# (c) 2014-2016 Freifunk Hochstift <kontakt@hochstift.freifunk.net>

# check if we're in the container
running_in_docker() {
  awk -F/ '$2 == "docker"' /proc/self/cgroup | read
}

# when called within the container, just call build.sh after ensuring git config is set
if [ running_in_docker -a "$(id -un)" == "build" ]; then

	# ensure that we have a valid git config
	git config --global user.name "docker-based build"
	git config --global user.email build@freifunk-essen.de
	git config --global http.postBuffer 524288000

	# invoke the actual build
	./build.sh $@
	exit
fi

MYDIR="$(dirname $0)"
MYDIR="$(readlink -f ${MYDIR})"
pushd "${MYDIR}" > /dev/null

# run the container with fixed hostname and mapped /code directory
docker run -ti -h ffe-build -v "${MYDIR}:/code" \
    --env BASE="${BASE}" \
    --env BRANCH="${BRANCH}" \
    --env VERSION="${VERSION}" \
    --env AUTOUPDATER="${AUTOUPDATER}" \
    --env BROKEN="${BROKEN}" \
    --env BUILD_TS="${BUILD_TS}" \
    --env CLEAN="${CLEAN}" \
    --env FAKETIME_LIB="/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1" \
    --env KEY_DIR="${KEY_DIR}" \
    --env MAKEJOBS="${MAKEJOBS}" \
    --env NO_FAKETIME="${NO_FAKETIME}" \
    --env PRIORITY="${PRIORITY}" \
    --env SITE_ID="${SITE_ID}" \
    --env TARGETS="${TARGETS}" \
    --env VERBOSE="${VERBOSE}" \
    ffe/build

popd > /dev/null #${MYDIR}
