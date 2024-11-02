FROM alpine:3.20.3
# docker run -it --privileged --rm \
#   -e SUSHY_EMULATOR_CONFIG=/etc/sushy/sushy-emulator.conf \
#   -v /var/run/libvirt:/var/run/libvirt \
#   -v "${PWD}/scripts/sushy.key:/etc/sushy/sushy.key" \
#   -v "${PWD}/scripts/sushy.cert:/etc/sushy/sushy.cert" \
#   -v "${PWD}/scripts/sushy-tools.conf:/etc/sushy/sushy-emulator.conf" \
#   -v "${PWD}/scripts/htpasswd:/etc/sushy/htpasswd" \
#   --name vbmc virtualbmc

ARG S6_OVERLAY_VERSION=3.2.0.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN apk add --no-cache xz && \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz && \
    rm -f /tmp/s6-overlay-noarch.tar.xz /tmp/s6-overlay-x86_64.tar.xz && \
    apk del xz

# virtualbmc for the ipmi interface
# sushy-tools for the redfish interface
RUN apk add --no-cache python3 py3-pip py3-libvirt py3-netifaces && \
    python3 -m venv --system-site-packages /opt/virtualbmc && \
    /opt/virtualbmc/bin/pip3 install virtualbmc && \
    python3 -m venv --system-site-packages /opt/sushy-tools && \
    /opt/sushy-tools/bin/pip3 install sushy-tools && \
    apk del py3-pip && \
    rm -rf /var/cache/apk/* /tmp/*

# Define virtualbmc as a long running s6 service
COPY <<EOF /etc/s6-overlay/s6-rc.d/vbmc/type
longrun
EOF

# Start vbmc in the foreground
COPY --chmod=700 <<EOF /etc/s6-overlay/s6-rc.d/vbmc/run
#!/command/with-contenv sh
    vbmcd --foreground
EOF

# This script is called when the service is stopped
# It will halt the entire container
COPY --chmod=700 <<EOF /etc/s6-overlay/s6-rc.d/vbmc/finish
#!/command/execlineb -S0
    foreground { redirfd -w 1 /run/s6-linux-init-container-results/exitcode echo 0 }
    /run/s6/basedir/bin/halt
EOF

# Register virtualbmc as a service for s6 to manage
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/vbmc
# Put the virtualbmc and sushy-tools binaries into the PATH
ENV PATH=/opt/virtualbmc/bin:/opt/sushy-tools/bin:$PATH

# The redfish emulator runs as a foreground process
# s6 manages it directly
CMD ["/command/with-contenv", "sh", "-c", "sushy-emulator"]

ENTRYPOINT ["/init"]
