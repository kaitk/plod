FROM ubuntu:24.04
COPY install.sh /tmp/install.sh
RUN bash /tmp/install.sh && apt-get install -y --no-install-recommends procps && useradd -m deploy
USER deploy
