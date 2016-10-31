all:

LC_ALL:=C
LANG:=C

GLUONDIR:=${CURDIR}/src

include $(GLUONDIR)/include/gluon.mk
include $(GLUONDIR)/targets/targets.mk

list-targets:
	@echo '$(GLUON_TARGETS)'

default-release:
	@echo '$(DEFAULT_GLUON_RELEASE)'
