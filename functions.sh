#!/bin/bash
# (c) 2014-2016 Freifunk Hochstift <kontakt@hochstift.freifunk.net>
#
# Helper functions for 'fancy' output

function progress {
	echo -en "\033[1;34m➔  "
	echo -en $*
	echo -en "\033[0m\n"
}

function debug {
	[ "_$VERBOSE" == "_1" ] || return

	echo -en "\033[1;37m  # "
	echo -en $*
	echo -en "\033[0m\n"
}

function info {
	echo -en "\033[1;36m"
	echo -en $*
	echo -en "\033[0m\n"
}

function success {
	echo -en "\033[1;32m  ✔ "
	echo -en $*
	echo -en "\033[0m\n"
}

function abort {
	echo -en "\033[1;31m  ✘ "
	echo -en $*
	echo -en "\033[0m\n"
	popd > /dev/null
	exit 99
}

