#!/bin/bash
set -e

cd "$(readlink -f "$(dirname "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

get_part() {
	local dir="$1"
	shift
	local part="$1"
	shift
	if [ -f "$dir/$part" ]; then
		cat "$dir/$part"
		return 0
	fi
	if [ -f "$part" ]; then
		cat "$part"
		return 0
	fi
	if [ $# -gt 0 ]; then
		echo "$1"
		return 0
	fi
	return 1
}

docker_build() {
	local dir="$1"
	shift
	local version="$1"
	shift
	local suite="$1"
	shift

	docker build -t "${repo}:${suite}" "$dir"
	if [ "$suite" != "$version" ]; then
		docker tag "${repo}:${suite}" "${repo}:${version}"
	fi
	if [ "$latest" == "$version" ]; then
		docker tag "${repo}:${latest}" "${repo}:latest"
	fi
	docker run -it --rm "${repo}:${suite}" bash -xc '
		cat /etc/apt/sources.list
		echo
		cat /etc/os-release 2>/dev/null
		echo
		cat /etc/lsb-release 2>/dev/null
		echo
		cat /etc/debian_version 2>/dev/null
		true
	'
}

repo="$(get_part . repo '')"
if [ "$repo" ]; then
	if [[ "$repo" != */* ]]; then
		user="$(docker info | awk '/^Username:/ { print $2 }')"
		if [ "$user" ]; then
			repo="$user/$repo"
		fi
	fi
fi

latest="$(get_part . latest '')"

scratches=()
cascaded=()
for version in "${versions[@]}"; do
	dir="$(readlink -f "$version")"
	from="$(cat $dir/Dockerfile | awk '/^FROM / { print $2 }')"
	if [[ x"$from" != xscratch ]]; then
		cascaded+=( $version )
	else
		scratches+=( $version )
	fi
done

for version in "${scratches[@]}"; do
	dir="$(readlink -f "$version")"
	variant="$(get_part "$dir" variant 'minbase')"
	components="$(get_part "$dir" components 'main')"
	include="$(get_part "$dir" include '')"
	suite="$(get_part "$dir" suite "$version")"
	mirror="$(get_part "$dir" mirror '')"
	script="$(get_part "$dir" script '')"
	
	args=( -d "$dir" debootstrap )
	[ -z "$variant" ] || args+=( --variant="$variant" )
	[ -z "$components" ] || args+=( --components="$components" )
	[ -z "$include" ] || args+=( --include="$include" )
	args+=( "$suite" )
	if [ "$mirror" ]; then
		args+=( "$mirror" )
		if [ "$script" ]; then
			args+=( "$script" )
		fi
	fi
	
	mkimage="$(readlink -f "mkimage.sh")"
	{
		echo "$(basename "$mkimage") ${args[*]/"$dir"/.}"
		echo
		echo 'https://github.com/dotcloud/docker/blob/master/contrib/mkimage.sh'
	} > "$dir/build-command.txt"
	
	sudo nice ionice -c 3 "$mkimage" "${args[@]}" 2>&1 | tee "$dir/build.log"
	
	sudo chown -R "$(id -u):$(id -g)" "$dir"
	
	if [ "$repo" ]; then
		docker_build "$dir" "$version" "$suite"
	fi
done

if [ "$repo" ]; then
	for version in "${cascaded[@]}"; do
		dir="$(readlink -f "$version")"
		suite="$(get_part "$dir" suite "$version")"

		docker_build "$dir" "$version" "$suite"
	done
fi
