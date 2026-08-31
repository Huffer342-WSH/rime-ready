FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
COPY platforms/ubuntu-22.04/build-packages.txt /tmp/build-packages.txt
RUN apt-get update \
 && grep -Ev '^\s*(#|$)' /tmp/build-packages.txt | xargs apt-get install -y --no-install-recommends \
 && apt-get install -y --no-install-recommends \
      ibus-rime librime-bin librime-plugin-lua librime-plugin-octagram \
      lintian sudo \
 && rm -f /tmp/build-packages.txt

RUN useradd --uid 1000 --create-home --shell /bin/bash tester \
 && printf 'tester ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/tester \
 && chmod 0440 /etc/sudoers.d/tester

WORKDIR /work
USER tester
ENV HOME=/home/tester
