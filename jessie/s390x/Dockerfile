FROM scratch
ADD rootfs.tar.xz /


RUN [ -z "$(grep debian-security /etc/apt/sources.list)" ] \
	|| sed -i '/^deb .*debian-security.*$/d' /etc/apt/sources.list

CMD ["/bin/bash"]
