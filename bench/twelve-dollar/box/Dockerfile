FROM ubuntu:24.04
COPY install.sh /tmp/install.sh
RUN bash /tmp/install.sh && apt-get install -y --no-install-recommends jq openssl sqlite3 procps && useradd -m deploy
USER deploy
