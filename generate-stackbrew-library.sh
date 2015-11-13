#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

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
	[sid]=1
)

versions=( */ )
versions=( "${versions[@]%/}" )
for version in "${versions[@]}"; do
	arches=( $version/*/ )
	arches=( "${arches[@]%/}" )
	arches=( "${arches[@]#$version/}" )
	eval arches_$version=\( ${arches[@]} \)
done

url='git://github.com/tianon/docker-brew-debian'

cat <<-'EOH'
# maintainer: Tianon Gravi <tianon@debian.org> (@tianon)
# maintainer: Paul Tagliamonte <paultag@debian.org> (@paultag)
EOH

commitRange='master..dist'
commitCount="$(git rev-list "$commitRange" --count 2>/dev/null || true)"
if [ "$commitCount" ] && [ "$commitCount" -gt 0 ]; then
	echo
	echo '# commits:' "($commitRange)"
	git log --format=format:'- %h %s%n%w(0,2,2)%b' "$commitRange" | sed 's/^/#  /'
fi

for version in "${versions[@]}"; do
	eval arches=\( \${arches_${version}[@]} \)
	for arch in "${arches[@]}"; do
		dir="$version/$arch"
		commit="$(git log -1 --format='format:%H' -- "$dir")"
		versionAliases=()
		if [ -z "${noVersion[$version]}" ]; then
			tarball="$dir/rootfs.tar.xz"
			fullVersion="$(tar -xvf "$tarball" etc/debian_version --to-stdout 2>/dev/null)"
			if [ -z "$fullVersion" ] || [[ "$fullVersion" == */sid ]]; then
				fullVersion="$(eval "$(tar -xvf "$tarball" etc/os-release --to-stdout 2>/dev/null)" && echo "$VERSION" | cut -d' ' -f1)"
				if [ -z "$fullVersion" ]; then
					# lucid...
					fullVersion="$(eval "$(tar -xvf "$tarball" etc/lsb-release --to-stdout 2>/dev/null)" && echo "$DISTRIB_DESCRIPTION" | cut -d' ' -f2)" # DISTRIB_DESCRIPTION="Ubuntu 10.04.4 LTS"
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
			echo "$va: ${url}@${commit} $dir"
			[ "$arch" == "amd64" ] && echo "$va: ${url}@${commit} $dir"
		done

		if [ -s "$dir/backports/Dockerfile" ]; then
			echo
			echo "$version-backports-$arch: ${url}@${commit} $dir/backports"
			[ "$arch" == "amd64" ] && echo "$version-backports: ${url}@${commit} $dir/backports"
		fi
	done
done

dockerfilesGit='git://github.com/tianon/dockerfiles'
dockerfiles='https://github.com/tianon/dockerfiles/commits/master/debian'
rcBuggyCommit="$(curl -fsSL "$dockerfiles/rc-buggy/Dockerfile.atom" | tac|tac | awk -F '[[:space:]]*[<>/]+' '$2 == "id" && $3 ~ /Commit/ { print $4; exit }')"
experimentalCommit="$(curl -fsSL "$dockerfiles/experimental/Dockerfile.atom" | tac|tac | awk -F '[[:space:]]*[<>/]+' '$2 == "id" && $3 ~ /Commit/ { print $4; exit }')"
cat <<-EOF

rc-buggy: $dockerfilesGit@$rcBuggyCommit debian/rc-buggy
experimental: $dockerfilesGit@$experimentalCommit debian/experimental
EOF
