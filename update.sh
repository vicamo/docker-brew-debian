#!/bin/bash
set -e

cd "$(readlink -f "$(dirname "$BASH_SOURCE")")"

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
	local arch="$1"
	shift
	local suite="$1"
	shift

	local isDefaultArch=
	[ "$arch" == "amd64" ] && isDefaultArch="yes"

	docker build -t "${repo}:${suite}-${arch}" "$dir"
	[ -n "$isDefaultArch" ] && docker tag "${repo}:${suite}-${arch}" "${repo}:${suite}"
	if [ "$suite" != "$version" ]; then
		docker tag "${repo}:${suite}-${arch}" "${repo}:${version}-${arch}"
		[ -n "$isDefaultArch" ] && docker tag "${repo}:${suite}-${arch}" "${repo}:${version}"
	fi
	if [ "$latest" == "$version" ]; then
		docker tag "${repo}:${latest}-${arch}" "${repo}:latest-${arch}"
		[ -n "$isDefaultArch" ] && docker tag "${repo}:${latest}-${arch}" "${repo}:latest"
	fi
	docker run -it --rm "${repo}:${suite}-${arch}" bash -xc '
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

args=( "$@" )
if [ ${#args[@]} -eq 0 ]; then
	args=( */ )
fi

versions=()
for arg in "${args[@]}"; do
	arg=${arg%/}
	arch=$(echo $arg | cut -d / -f 2)
	version=$(echo $arg | cut -d / -f 1)
	if [ "$arch" == "$version" ]; then
		arch=
	fi

	if [ -z "`echo ${versions[@]} | grep $version`" ]; then
		versions+=( $version )
	fi

	name=arches_$version
	if [ "$arch" ]; then
		eval arches=\( \${${name}[@]} \)
		if [ ${#arches[@]} -ne 0 ]; then
			if [ -z "`echo ${arches[@]} | grep $arch`" ]; then
				eval $name+=\( "$arch" \)
			fi
		else
			eval $name=\( "$arch" \)
		fi
	else
		arches=( $version/*/ )
		arches=( "${arches[@]%/}" )
		arches=( "${arches[@]#$version/}" )
		if [ ${#arches[@]} -lt 0 -o "${arches[0]}" != "*" ]; then
			eval $name=\( ${arches[@]} \)
		fi
	fi

	#echo "arch: $arch, version: $version"
	#echo "versions: ${versions[@]}"
	#eval echo "$name: \${${name}[@]}"
	#echo
done

scratches=()
cascaded=()
for version in "${versions[@]}"; do
	name=arches_$version
	eval arches=\( \${${name}[@]} \)
	for arch in "${arches[@]}"; do
		dir="$(readlink -f "$version/$arch")"

		skip="$(get_part "$dir" skip '')"
		[ -z "$skip" ] || (echo "Skipping $version/$arch, reason: $skip"; continue)

		from="$(cat $dir/Dockerfile | awk '/^FROM / { print $2 }')"
		if [[ x"$from" != xscratch ]]; then
			cascaded+=( $version/$arch )
		else
			scratches+=( $version/$arch )
		fi
	done
done

for task in "${scratches[@]}"; do
	version=$(echo $task | cut -d / -f 1)
	arch=$(echo $task | cut -d / -f 2)

	dir="$(readlink -f "$task")"
	variant="$(get_part "$dir" variant 'minbase')"
	components="$(get_part "$dir" components 'main')"
	include="$(get_part "$dir" include '')"
	suite="$(get_part "$dir" suite "$version")"
	mirror="$(get_part "$dir" mirror '')"
	script="$(get_part "$dir" script '')"
	
	args=( -d "$dir" debootstrap --arch="$arch" )
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
	
	mkimage="$(readlink -f "${MKIMAGE:-"mkimage.sh"}")"
	{
		echo "$(basename "$mkimage") ${args[*]/"$dir"/.}"
		echo
		echo 'https://github.com/docker/docker/blob/master/contrib/mkimage.sh'
	} > "$dir/build-command.txt"
	
	sudo nice ionice -c 3 "$mkimage" "${args[@]}" 2>&1 | tee "$dir/build.log"
	
	sudo chown -R "$(id -u):$(id -g)" "$dir"
	
	if [ "$repo" ]; then
		docker_build "$dir" "$version" "$arch" "$suite"
	fi
done

if [ "$repo" ]; then
	for task in "${cascaded[@]}"; do
		version=$(echo $task | cut -d / -f 1)
		arch=$(echo $task | cut -d / -f 2)

		dir="$(readlink -f "$task")"
		suite="$(get_part "$dir" suite "$version")"

		docker_build "$dir" "$version" "$arch" "$suite"
	done
fi
