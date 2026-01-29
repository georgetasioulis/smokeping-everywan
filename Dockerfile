FROM linuxserver/smokeping:latest

RUN apk add --no-cache \
    python3 \
    py3-pip \
    curl \
    imagemagick \
    ttf-dejavu \
    bind-tools \
    tcptraceroute \
    dos2unix \
    perl-dbi \
    perl-dbd-sqlite \
    perl-cgi

RUN mkdir -p /opt/traceroute_history /opt/smokeping/lib

COPY traceroute_history/ /opt/traceroute_history/
COPY traceping_daemon.pl /opt/smokeping/traceping_daemon.pl
COPY traceping_server_simple.pl /opt/smokeping/traceping_server_simple.pl
COPY traceping.cgi /usr/share/webapps/smokeping/traceping.cgi
COPY traceping.cgi.pl /usr/share/webapps/smokeping/traceping.cgi.pl
COPY frontend/ /usr/share/webapps/smokeping/
COPY frontend/basepage.html /etc/smokeping/basepage.html
COPY config/Targets /defaults/Targets
COPY config/Probes /defaults/Probes
COPY scripts/init.d/99-custom-config.sh /custom-cont-init.d/99-custom-config.sh
COPY scripts/init.d/99-start-traceping-daemon.sh /custom-cont-init.d/99-start-traceping-daemon.sh
COPY scripts/init.d/99-start-traceping-server.sh /custom-cont-init.d/99-start-traceping-server.sh

# Create symlinks for production-compatible paths
RUN ln -sf /usr/share/webapps/smokeping/js/scriptaculous /usr/share/webapps/smokeping/scriptaculous && \
    ln -sf /usr/share/webapps/smokeping/js/cropper /usr/share/webapps/smokeping/cropper && \
    ln -sf /usr/share/webapps/smokeping/js/smokeping.js /usr/share/webapps/smokeping/smokeping-zoom.js

RUN dos2unix /custom-cont-init.d/99-custom-config.sh \
    /custom-cont-init.d/99-start-traceping-daemon.sh \
    /custom-cont-init.d/99-start-traceping-server.sh \
    /opt/smokeping/traceping_daemon.pl \
    /opt/smokeping/traceping_server_simple.pl \
    /usr/share/webapps/smokeping/traceping.cgi \
    /usr/share/webapps/smokeping/traceping.cgi.pl \
    /etc/smokeping/basepage.html && \
    chmod 755 /custom-cont-init.d/99-custom-config.sh \
    /custom-cont-init.d/99-start-traceping-daemon.sh \
    /custom-cont-init.d/99-start-traceping-server.sh \
    /opt/smokeping/traceping_daemon.pl \
    /opt/smokeping/traceping_server_simple.pl \
    /usr/share/webapps/smokeping/traceping.cgi \
    /usr/share/webapps/smokeping/traceping.cgi.pl && \
    chmod +x /opt/traceroute_history/*.sh 2>/dev/null || true

ENV TRACEPING_INTERVAL=300 \
    TRACEPING_RETENTION_DAYS=365 \
    TRACEPING_PORT=9000 \
    SMOKEPING_BRAND_NAME="SmokePing" \
    SMOKEPING_BRAND_URL="" \
    SMOKEPING_LOGO_URL="images/smokeping.png"
