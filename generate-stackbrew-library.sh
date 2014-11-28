#!/bin/bash
set -e

declare -A aliases
aliases=(
	[$(cat latest)]='latest'
)
declare -A noVersion
noVersion=(
	[oldstable]=1
	[stable]=1
	[testing]=1
	[unstable]=1
)

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( */ )
versions=( "${versions[@]%/}" )
for version in "${versions[@]}"; do
	arches=( $version/*/ )
	arches=( "${arches[@]%/}" )
	arches=( "${arches[@]#$version/}" )
	eval arches_$version=\( ${arches[@]} \)
done

url='git://github.com/tianon/docker-brew-debian'

echo '# maintainer: Tianon Gravi <admwiggin@gmail.com> (@tianon)'

commitRange='master..dist'
commitCount="$(git rev-list "$commitRange" --count 2>/dev/null || true)"
if [ "$commitCount" ] && [ "$commitCount" -gt 0 ]; then
	echo
	echo '# commits:' "($commitRange)"
	git log --oneline "$commitRange" | sed 's/^/#  - /'
fi

for version in "${versions[@]}"; do
	eval arches=\( \${arches_${version}[@]} \)
	for arch in "${arches[@]}"; do
		dir="$version/$arch"
		commit="$(git log -1 --format='format:%H' "$dir")"
		versionAliases=()
		if [ -z "${noVersion[$version]}" ]; then
			fullVersion="$(tar -xvf "$dir/rootfs.tar.xz" etc/debian_version --to-stdout 2>/dev/null)"
			if [ -z "$fullVersion" ] || [[ "$fullVersion" == */sid ]]; then
				fullVersion="$(eval "$(tar -xvf "$dir/rootfs.tar.xz" etc/os-release --to-stdout 2>/dev/null)" && echo "$VERSION" | cut -d' ' -f1)"
				if [ -z "$fullVersion" ]; then
					# lucid...
					fullVersion="$(eval "$(tar -xvf "$dir/rootfs.tar.xz" etc/lsb-release --to-stdout 2>/dev/null)" && echo "$DISTRIB_DESCRIPTION" | cut -d' ' -f2)" # DISTRIB_DESCRIPTION="Ubuntu 10.04.4 LTS"
				fi
			else
				while [ "${fullVersion%.*}" != "$fullVersion" ]; do
					versionAliases+=( $fullVersion )
					fullVersion="${fullVersion%.*}"
				done
			fi
			if [ "$fullVersion" != "$version" ]; then
				versionAliases+=( $fullVersion )
			fi
		fi
		versionAliases+=( $version $(cat "$dir/suite" 2>/dev/null || true) ${aliases[$version]} )
	
		echo
		for va in "${versionAliases[@]}"; do
			echo "$va: ${url}@${commit} $version-$arch"
			[ "$arch" == "amd64" ] && echo "$va: ${url}@${commit} $version"
		done
	done
done

dockerfiles='git://github.com/tianon/dockerfiles'
commit="$(git ls-remote "$dockerfiles" HEAD | cut -d$'\t' -f1)"
cat <<-EOF

rc-buggy: $dockerfiles@$commit debian/rc-buggy
experimental: $dockerfiles@$commit debian/experimental
EOF
