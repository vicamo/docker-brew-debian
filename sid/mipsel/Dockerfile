FROM scratch
ADD rootfs.tar.xz /

# https://omniverse.ru/blog/2016/08/25/apt-get-mips/
RUN echo 'Acquire::ForceIPv4 "True";' > /etc/apt/apt.conf.d/80forceIPv4

CMD ["/bin/bash"]
