# Multiarch Debian Docker Image

Debian images are published to
[`ghcr.io/vicamo/debian`](https://github.com/vicamo/docker-brew-debian/pkgs/container/debian).

## Available tags

Using Debian Sid (the `unstable` suite) as an example, the following tags are
available. Prefix each tag with `ghcr.io/vicamo/debian:`.

| Tags                                      | Contents                                                |
| ----------------------------------------- | ------------------------------------------------------- |
| `sid`, `unstable`                         | Regular image; Docker selects the host's architecture.  |
| `sid-slim`, `unstable-slim`               | Smaller rootfs; Docker selects the host's architecture. |
| `sid-<arch>`, `unstable-<arch>`           | Regular image for a specific Debian architecture.       |
| `sid-<arch>-slim`, `unstable-<arch>-slim` | Slim image for a specific Debian architecture.          |

Replace `<arch>` with an architecture marked ✅ in the Sid row of the
[architecture support table](#architecture-support), for example `amd64`,
`arm64`, or `ppc64el`. Thus, `sid-amd64`, `sid-arm64-slim`, and
`unstable-ppc64el` are architecture-specific tags. Architecture suffixes use
Debian names; Docker's `--platform` uses OCI names, such as `linux/ppc64le` for
`ppc64el`.

These tags are updated as images are rebuilt. To pin an exact image, use its
digest (`ghcr.io/vicamo/debian@sha256:...`), available from
`docker buildx imagetools inspect ghcr.io/vicamo/debian:sid`.

## Usage

Pull Sid and start an interactive shell on the host's architecture:

```sh
docker pull ghcr.io/vicamo/debian:sid
docker run --rm -it ghcr.io/vicamo/debian:sid bash
```

Use the slim variant or its suite alias:

```sh
docker run --rm ghcr.io/vicamo/debian:sid-slim cat /etc/os-release
docker pull ghcr.io/vicamo/debian:unstable-slim
```

Select ARM64 from the multiarch image, or use an architecture-specific tag:

```sh
docker run --rm --platform linux/arm64 ghcr.io/vicamo/debian:sid-slim uname -m
docker pull --platform linux/arm64 ghcr.io/vicamo/debian:sid-arm64-slim
```

Running an image for a foreign architecture requires compatible emulation on the
host, such as QEMU with binfmt support.

Use Sid as the base for your own Dockerfile:

```dockerfile
FROM ghcr.io/vicamo/debian:sid-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

CMD ["bash"]
```

## Architecture support

<!-- arch-table:start -->

| suite    | alpha | amd64 | arm | arm64 | armel | armhf | hppa | i386 | loong64 | m68k | mips | mips64el | mipsel | powerpc | ppc64 | ppc64el | riscv64 | s390x | sh4 | sparc | sparc64 |
| -------- | ----- | ----- | --- | ----- | ----- | ----- | ---- | ---- | ------- | ---- | ---- | -------- | ------ | ------- | ----- | ------- | ------- | ----- | --- | ----- | ------- |
| sid      | ✅    | ✅    | —   | ✅    | —     | ✅    | ✅   | ✅   | ✅      | ✅   | —    | —        | —      | ✅      | ✅    | ✅      | ✅      | ✅    | ✅  | —     | ✅      |
| forky    | —     | ✅    | —   | ✅    | —     | ✅    | —    | ✅   | ✅      | —    | —    | —        | —      | —       | —     | ✅      | ✅      | ✅    | —   | —     | —       |
| trixie   | —     | ✅    | —   | ✅    | ✅    | ✅    | —    | ✅   | —       | —    | —    | —        | —      | —       | —     | ✅      | ✅      | ✅    | —   | —     | —       |
| bookworm | —     | ✅    | —   | ✅    | ✅    | ✅    | —    | ✅   | —       | —    | —    | ✅       | ✅     | —       | —     | ✅      | —       | ✅    | —   | —     | —       |
| bullseye | —     | ✅    | —   | ✅    | ✅    | ✅    | —    | ✅   | —       | —    | —    | ✅       | ✅     | —       | —     | ✅      | —       | ✅    | —   | —     | —       |
| buster   | —     | ✅    | —   | ✅    | ✅    | ✅    | —    | ✅   | —       | —    | ✅   | ✅       | ✅     | —       | —     | ✅      | —       | ✅    | —   | —     | —       |
| stretch  | —     | ✅    | —   | ✅    | ✅    | ✅    | —    | ✅   | —       | —    | ✅   | ✅       | ✅     | —       | —     | ✅      | —       | ✅    | —   | —     | —       |
| jessie   | —     | ✅    | —   | ✅    | ✅    | ✅    | —    | ✅   | —       | —    | ✅   | —        | ✅     | ✅      | —     | ✅      | —       | ✅    | —   | —     | —       |
| wheezy   | —     | ✅    | —   | —     | ✅    | ✅    | —    | ✅   | —       | —    | ✅   | —        | ✅     | ✅      | —     | —       | —       | ✅    | —   | ✅    | —       |
| squeeze  | —     | ✅    | —   | —     | ✅    | —     | —    | ✅   | —       | —    | ✅   | —        | ✅     | ✅      | —     | —       | —       | —     | —   | ✅    | —       |
| lenny    | ✅    | ✅    | ❌  | —     | ✅    | —     | ✅   | ✅   | —       | —    | ✅   | —        | ✅     | ✅      | —     | —       | —       | —     | —   | ✅    | —       |
| etch     | ✅    | ✅    | ❌  | —     | —     | —     | ✅   | ✅   | —       | ❌   | ✅   | —        | ✅     | ✅      | —     | —       | —       | —     | —   | ✅    | —       |
| sarge    | ✅    | —     | ❌  | —     | —     | —     | ✅   | ✅   | —       | ✅   | ✅   | —        | ✅     | ✅      | —     | —       | —       | —     | —   | ✅    | —       |
| woody    | ✅    | —     | ❌  | —     | —     | —     | ✅   | ✅   | —       | ✅   | ❌   | —        | ❌     | ❌      | —     | —       | —       | —     | —   | ✅    | —       |
| potato   | ✅    | —     | ❌  | —     | —     | —     | —    | ✅   | —       | ✅   | —    | —        | —      | ❌      | —     | —       | —       | —     | —   | ✅    | —       |

Legend: ✅ built | ❌ missing | — unsupported

<!-- arch-table:end -->
