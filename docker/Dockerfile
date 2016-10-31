FROM ubuntu:14.04
MAINTAINER vincent@freifunk-essen.de

RUN apt-get update && apt-get install -y \
    build-essential \
    git python wget gawk subversion p7zip-full unzip \
    faketime libfaketime libgmp-dev libmpfr-dev libmpc-dev \
    zlib1g-dev ncurses-dev libssl-dev bsdmainutils

RUN useradd -m build
ENV HOME /home/build
RUN sudo -Hu build git config --global user.name "docker-based build" ; sudo -Hu build git config --global user.email "build@freifunk-essen.de"

RUN mkdir /code
WORKDIR /code

RUN chown -R build: /code
RUN echo -en "#!/bin/sh\necho Start this container with "-v /path/to/firmware-repo:/code" to map your repo into it.\n" > /code/build.sh ; chmod +x /code/build.sh

VOLUME /code
USER build

CMD ["/bin/bash", "docker-build.sh"]

