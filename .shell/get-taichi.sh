#!/bin/bash
set -e

SCRIPT_COMMIT_SHA="e5543d473431b782227f8908005543bb4389b8de"

# strip "v" prefix if present
VERSION="${VERSION#v}"

# The channel to install from:
#   * stable
#   * test
#   * edge (deprecated)
#   * nightly (deprecated)
DEFAULT_CHANNEL_VALUE="stable"
if [ -z "$CHANNEL" ]; then
	CHANNEL=$DEFAULT_CHANNEL_VALUE
fi

DEFAULT_DOWNLOAD_URL="https://download.docker.com"
if [ -z "$DOWNLOAD_URL" ]; then
	DOWNLOAD_URL=$DEFAULT_DOWNLOAD_URL
fi

DEFAULT_REPO_FILE="docker-ce.repo"
if [ -z "$REPO_FILE" ]; then
	REPO_FILE="$DEFAULT_REPO_FILE"
fi

mirror=''
DRY_RUN=${DRY_RUN:-}
while [ $# -gt 0 ]; do
	case "$1" in
		--channel)
			CHANNEL="$2"
			shift
			;;
		--dry-run)
			DRY_RUN=1
			;;
		--mirror)
			mirror="$2"
			shift
			;;
		--version)
			VERSION="${2#v}"
			shift
			;;
		--*)
			echo "Illegal option $1"
			;;
	esac
	shift $(( $# > 0 ? 1 : 0 ))
done

case "$mirror" in
	Aliyun)
		DOWNLOAD_URL="https://mirrors.aliyun.com/docker-ce"
		;;
	AzureChinaCloud)
		DOWNLOAD_URL="https://mirror.azure.cn/docker-ce"
		;;
	"")
		;;
	*)
		>&2 echo "unknown mirror '$mirror': use either 'Aliyun', or 'AzureChinaCloud'."
		exit 1
		;;
esac

case "$CHANNEL" in
	stable|test)
		;;
	edge|nightly)
		>&2 echo "DEPRECATED: the $CHANNEL channel has been deprecated and is no longer supported by this script."
		exit 1
		;;
	*)
		>&2 echo "unknown CHANNEL '$CHANNEL': use either stable or test."
		exit 1
		;;
esac

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

# version_gte checks if the version specified in $VERSION is at least the given
# SemVer (Maj.Minor[.Patch]), or CalVer (YY.MM) version.It returns 0 (success)
# if $VERSION is either unset (=latest) or newer or equal than the specified
# version, or returns 1 (fail) otherwise.
#
# examples:
#
# VERSION=23.0
# version_gte 23.0  // 0 (success)
# version_gte 20.10 // 0 (success)
# version_gte 19.03 // 0 (success)
# version_gte 21.10 // 1 (fail)
version_gte() {
	if [ -z "$VERSION" ]; then
			return 0
	fi
	eval version_compare "$VERSION" "$1"
}

# version_compare compares two version strings (either SemVer (Major.Minor.Path),
# or CalVer (YY.MM) version strings. It returns 0 (success) if version A is newer
# or equal than version B, or 1 (fail) otherwise. Patch releases and pre-release
# (-alpha/-beta) are not taken into account
#
# examples:
#
# version_compare 23.0.0 20.10 // 0 (success)
# version_compare 23.0 20.10   // 0 (success)
# version_compare 20.10 19.03  // 0 (success)
# version_compare 20.10 20.10  // 0 (success)
# version_compare 19.03 20.10  // 1 (fail)
version_compare() (
	set +x

	yy_a="$(echo "$1" | cut -d'.' -f1)"
	yy_b="$(echo "$2" | cut -d'.' -f1)"
	if [ "$yy_a" -lt "$yy_b" ]; then
		return 1
	fi
	if [ "$yy_a" -gt "$yy_b" ]; then
		return 0
	fi
	mm_a="$(echo "$1" | cut -d'.' -f2)"
	mm_b="$(echo "$2" | cut -d'.' -f2)"

	# trim leading zeros to accommodate CalVer
	mm_a="${mm_a#0}"
	mm_b="${mm_b#0}"

	if [ "${mm_a:-0}" -lt "${mm_b:-0}" ]; then
		return 1
	fi

	return 0
)

is_dry_run() {
	if [ -z "$DRY_RUN" ]; then
		return 1
	else
		return 0
	fi
}

is_wsl() {
	case "$(uname -r)" in
	*microsoft* ) true ;; # WSL 2
	*Microsoft* ) true ;; # WSL 1
	* ) false;;
	esac
}

is_darwin() {
	case "$(uname -s)" in
	*darwin* ) true ;;
	*Darwin* ) true ;;
	* ) false;;
	esac
}

deprecation_notice() {
	distro=$1
	distro_version=$2
	echo
	printf "\033[91;1mDEPRECATION WARNING\033[0m\n"
	printf "    This Linux distribution (\033[1m%s %s\033[0m) reached end-of-life and is no longer supported by this script.\n" "$distro" "$distro_version"
	echo   "    No updates or security fixes will be released for this distribution, and users are recommended"
	echo   "    to upgrade to a currently maintained version of $distro."
	echo
	printf   "Press \033[1mCtrl+C\033[0m now to abort this script, or wait for the installation to continue."
	echo
	sleep 10
}

get_distribution() {
	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	# Returning an empty string here should be alright since the
	# case statements don't act unless you provide an actual value
	echo "$lsb_dist"
}

echo_docker_as_nonroot() {
	if is_dry_run; then
		return
	fi
	if command_exists docker && [ -e /var/run/docker.sock ]; then
		(
			set -x
			$sh_c 'docker version'
		) || true
	fi

	# intentionally mixed spaces and tabs here -- tabs are stripped by "<<-EOF", spaces are kept in the output
	echo
	echo "================================================================================"
	echo
	if version_gte "20.10"; then
		echo "To run Docker as a non-privileged user, consider setting up the"
		echo "Docker daemon in rootless mode for your user:"
		echo
		echo "    dockerd-rootless-setuptool.sh install"
		echo
		echo "Visit https://docs.docker.com/go/rootless/ to learn about rootless mode."
		echo
	fi
	echo
	echo "To run the Docker daemon as a fully privileged service, but granting non-root"
	echo "users access, refer to https://docs.docker.com/go/daemon-access/"
	echo
	echo "WARNING: Access to the remote API on a privileged Docker daemon is equivalent"
	echo "         to root access on the host. Refer to the 'Docker daemon attack surface'"
	echo "         documentation for details: https://docs.docker.com/go/attack-surface/"
	echo
	echo "================================================================================"
	echo
}

# Check if this is a forked Linux distro
check_forked() {

	# Check for lsb_release command existence, it usually exists in forked distros
	if command_exists lsb_release; then
		# Check if the `-u` option is supported
		set +e
		lsb_release -a -u > /dev/null 2>&1
		lsb_release_exit_code=$?
		set -e

		# Check if the command has exited successfully, it means we're in a forked distro
		if [ "$lsb_release_exit_code" = "0" ]; then
			# Print info about current distro
			cat <<-EOF
			You're using '$lsb_dist' version '$dist_version'.
			EOF

			# Get the upstream release info
			lsb_dist=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'id' | cut -d ':' -f 2 | tr -d '[:space:]')
			dist_version=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'codename' | cut -d ':' -f 2 | tr -d '[:space:]')

			# Print info about upstream distro
			cat <<-EOF
			Upstream release is '$lsb_dist' version '$dist_version'.
			EOF
		else
			if [ -r /etc/debian_version ] && [ "$lsb_dist" != "ubuntu" ] && [ "$lsb_dist" != "raspbian" ]; then
				if [ "$lsb_dist" = "osmc" ]; then
					# OSMC runs Raspbian
					lsb_dist=raspbian
				else
					# We're Debian and don't even know it!
					lsb_dist=debian
				fi
				dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
				case "$dist_version" in
					12)
						dist_version="bookworm"
					;;
					11)
						dist_version="bullseye"
					;;
					10)
						dist_version="buster"
					;;
					9)
						dist_version="stretch"
					;;
					8)
						dist_version="jessie"
					;;
				esac
			fi
		fi
	fi
}

do_install() {
	echo "# Executing docker install script, commit: $SCRIPT_COMMIT_SHA"

	if command_exists docker; then
		cat >&2 <<-'EOF'
			Warning: the "docker" command appears to already exist on this system.

			If you already have Docker installed, this script can cause trouble, which is
			why we're displaying this warning and provide the opportunity to cancel the
			installation.

			If you installed the current Docker package using this script and are using it
			again to update Docker, you can safely ignore this message.

			You may press Ctrl+C now to abort this script.
		EOF
		( set -x; sleep 20 )
	fi

	user="$(id -un 2>/dev/null || true)"

	sh_c='sh -c'
	if [ "$user" != 'root' ]; then
		if command_exists sudo; then
			sh_c='sudo -E sh -c'
		elif command_exists su; then
			sh_c='su -c'
		else
			cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
			exit 1
		fi
	fi

	if is_dry_run; then
		sh_c="echo"
	fi

	# perform some very rudimentary platform detection
	lsb_dist=$( get_distribution )
	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

	if is_wsl; then
		echo
		echo "WSL DETECTED: We recommend using Docker Desktop for Windows."
		echo "Please get Docker Desktop from https://www.docker.com/products/docker-desktop/"
		echo
		cat >&2 <<-'EOF'

			You may press Ctrl+C now to abort this script.
		EOF
		( set -x; sleep 20 )
	fi

	case "$lsb_dist" in

		ubuntu)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
		;;

		debian|raspbian)
			dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
			case "$dist_version" in
				12)
					dist_version="bookworm"
				;;
				11)
					dist_version="bullseye"
				;;
				10)
					dist_version="buster"
				;;
				9)
					dist_version="stretch"
				;;
				8)
					dist_version="jessie"
				;;
			esac
		;;

		centos|rhel|sles)
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --release | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

	esac

	# Check if this is a forked Linux distro
	check_forked

	# Print deprecation warnings for distro versions that recently reached EOL,
	# but may still be commonly used (especially LTS versions).
	case "$lsb_dist.$dist_version" in
		debian.stretch|debian.jessie)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		raspbian.stretch|raspbian.jessie)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		ubuntu.xenial|ubuntu.trusty)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		ubuntu.impish|ubuntu.hirsute|ubuntu.groovy|ubuntu.eoan|ubuntu.disco|ubuntu.cosmic)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		fedora.*)
			if [ "$dist_version" -lt 36 ]; then
				deprecation_notice "$lsb_dist" "$dist_version"
			fi
			;;
	esac

	# Run setup for each distro accordingly
	case "$lsb_dist" in
		ubuntu|debian|raspbian)
			pre_reqs="apt-transport-https ca-certificates curl"
			if ! command -v gpg > /dev/null; then
				pre_reqs="$pre_reqs gnupg"
			fi
			apt_repo="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $DOWNLOAD_URL/linux/$lsb_dist $dist_version $CHANNEL"
			(
				if ! is_dry_run; then
					set -x
				fi
				$sh_c 'apt-get update -qq >/dev/null'
				$sh_c "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pre_reqs >/dev/null"
				$sh_c 'install -m 0755 -d /etc/apt/keyrings'
				$sh_c "curl -fsSL \"$DOWNLOAD_URL/linux/$lsb_dist/gpg\" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg"
				$sh_c "chmod a+r /etc/apt/keyrings/docker.gpg"
				$sh_c "echo \"$apt_repo\" > /etc/apt/sources.list.d/docker.list"
				$sh_c 'apt-get update -qq >/dev/null'
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				if is_dry_run; then
					echo "# WARNING: VERSION pinning is not supported in DRY_RUN"
				else
					# Will work for incomplete versions IE (17.12), but may not actually grab the "latest" if in the test channel
					pkg_pattern="$(echo "$VERSION" | sed 's/-ce-/~ce~.*/g' | sed 's/-/.*/g')"
					search_command="apt-cache madison docker-ce | grep '$pkg_pattern' | head -1 | awk '{\$1=\$1};1' | cut -d' ' -f 3"
					pkg_version="$($sh_c "$search_command")"
					echo "INFO: Searching repository for VERSION '$VERSION'"
					echo "INFO: $search_command"
					if [ -z "$pkg_version" ]; then
						echo
						echo "ERROR: '$VERSION' not found amongst apt-cache madison results"
						echo
						exit 1
					fi
					if version_gte "18.09"; then
							search_command="apt-cache madison docker-ce-cli | grep '$pkg_pattern' | head -1 | awk '{\$1=\$1};1' | cut -d' ' -f 3"
							echo "INFO: $search_command"
							cli_pkg_version="=$($sh_c "$search_command")"
					fi
					pkg_version="=$pkg_version"
				fi
			fi
			(
				pkgs="docker-ce${pkg_version%=}"
				if version_gte "18.09"; then
						# older versions didn't ship the cli and containerd as separate packages
						pkgs="$pkgs docker-ce-cli${cli_pkg_version%=} containerd.io"
				fi
				if version_gte "20.10"; then
						pkgs="$pkgs docker-compose-plugin docker-ce-rootless-extras$pkg_version"
				fi
				if version_gte "23.0"; then
						pkgs="$pkgs docker-buildx-plugin"
				fi
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkgs >/dev/null"
			)
			echo_docker_as_nonroot
			exit 0
			;;
		centos|fedora|rhel)
			if [ "$(uname -m)" != "s390x" ] && [ "$lsb_dist" = "rhel" ]; then
				echo "Packages for RHEL are currently only available for s390x."
				exit 1
			fi
			if [ "$lsb_dist" = "fedora" ]; then
				pkg_manager="dnf"
				config_manager="dnf config-manager"
				enable_channel_flag="--set-enabled"
				disable_channel_flag="--set-disabled"
				pre_reqs="dnf-plugins-core"
				pkg_suffix="fc$dist_version"
			else
				pkg_manager="yum"
				config_manager="yum-config-manager"
				enable_channel_flag="--enable"
				disable_channel_flag="--disable"
				pre_reqs="yum-utils"
				pkg_suffix="el"
			fi
			repo_file_url="$DOWNLOAD_URL/linux/$lsb_dist/$REPO_FILE"
			(
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "$pkg_manager install -y -q $pre_reqs"
				$sh_c "$config_manager --add-repo $repo_file_url"

				if [ "$CHANNEL" != "stable" ]; then
					$sh_c "$config_manager $disable_channel_flag 'docker-ce-*'"
					$sh_c "$config_manager $enable_channel_flag 'docker-ce-$CHANNEL'"
				fi
				$sh_c "$pkg_manager makecache"
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				if is_dry_run; then
					echo "# WARNING: VERSION pinning is not supported in DRY_RUN"
				else
					pkg_pattern="$(echo "$VERSION" | sed 's/-ce-/\\\\.ce.*/g' | sed 's/-/.*/g').*$pkg_suffix"
					search_command="$pkg_manager list --showduplicates docker-ce | grep '$pkg_pattern' | tail -1 | awk '{print \$2}'"
					pkg_version="$($sh_c "$search_command")"
					echo "INFO: Searching repository for VERSION '$VERSION'"
					echo "INFO: $search_command"
					if [ -z "$pkg_version" ]; then
						echo
						echo "ERROR: '$VERSION' not found amongst $pkg_manager list results"
						echo
						exit 1
					fi
					if version_gte "18.09"; then
						# older versions don't support a cli package
						search_command="$pkg_manager list --showduplicates docker-ce-cli | grep '$pkg_pattern' | tail -1 | awk '{print \$2}'"
						cli_pkg_version="$($sh_c "$search_command" | cut -d':' -f 2)"
					fi
					# Cut out the epoch and prefix with a '-'
					pkg_version="-$(echo "$pkg_version" | cut -d':' -f 2)"
				fi
			fi
			(
				pkgs="docker-ce$pkg_version"
				if version_gte "18.09"; then
					# older versions didn't ship the cli and containerd as separate packages
					if [ -n "$cli_pkg_version" ]; then
						pkgs="$pkgs docker-ce-cli-$cli_pkg_version containerd.io"
					else
						pkgs="$pkgs docker-ce-cli containerd.io"
					fi
				fi
				if version_gte "20.10"; then
					pkgs="$pkgs docker-compose-plugin docker-ce-rootless-extras$pkg_version"
				fi
				if version_gte "23.0"; then
						pkgs="$pkgs docker-buildx-plugin"
				fi
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "$pkg_manager install -y -q $pkgs"
			)
			echo_docker_as_nonroot
			exit 0
			;;
		sles)
			if [ "$(uname -m)" != "s390x" ]; then
				echo "Packages for SLES are currently only available for s390x"
				exit 1
			fi
			if [ "$dist_version" = "15.3" ]; then
				sles_version="SLE_15_SP3"
			else
				sles_minor_version="${dist_version##*.}"
				sles_version="15.$sles_minor_version"
			fi
			repo_file_url="$DOWNLOAD_URL/linux/$lsb_dist/$REPO_FILE"
			pre_reqs="ca-certificates curl libseccomp2 awk"
			(
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "zypper install -y $pre_reqs"
				$sh_c "zypper addrepo $repo_file_url"
				if ! is_dry_run; then
						cat >&2 <<-'EOF'
						WARNING!!
						openSUSE repository (https://download.opensuse.org/repositories/security:SELinux) will be enabled now.
						Do you wish to continue?
						You may press Ctrl+C now to abort this script.
						EOF
						( set -x; sleep 30 )
				fi
				opensuse_repo="https://download.opensuse.org/repositories/security:SELinux/$sles_version/security:SELinux.repo"
				$sh_c "zypper addrepo $opensuse_repo"
				$sh_c "zypper --gpg-auto-import-keys refresh"
				$sh_c "zypper lr -d"
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				if is_dry_run; then
					echo "# WARNING: VERSION pinning is not supported in DRY_RUN"
				else
					pkg_pattern="$(echo "$VERSION" | sed 's/-ce-/\\\\.ce.*/g' | sed 's/-/.*/g')"
					search_command="zypper search -s --match-exact 'docker-ce' | grep '$pkg_pattern' | tail -1 | awk '{print \$6}'"
					pkg_version="$($sh_c "$search_command")"
					echo "INFO: Searching repository for VERSION '$VERSION'"
					echo "INFO: $search_command"
					if [ -z "$pkg_version" ]; then
						echo
						echo "ERROR: '$VERSION' not found amongst zypper list results"
						echo
						exit 1
					fi
					search_command="zypper search -s --match-exact 'docker-ce-cli' | grep '$pkg_pattern' | tail -1 | awk '{print \$6}'"
					# It's okay for cli_pkg_version to be blank, since older versions don't support a cli package
					cli_pkg_version="$($sh_c "$search_command")"
					pkg_version="-$pkg_version"
				fi
			fi
			(
				pkgs="docker-ce$pkg_version"
				if version_gte "18.09"; then
					if [ -n "$cli_pkg_version" ]; then
						# older versions didn't ship the cli and containerd as separate packages
						pkgs="$pkgs docker-ce-cli-$cli_pkg_version containerd.io"
					else
						pkgs="$pkgs docker-ce-cli containerd.io"
					fi
				fi
				if version_gte "20.10"; then
					pkgs="$pkgs docker-compose-plugin docker-ce-rootless-extras$pkg_version"
				fi
				if version_gte "23.0"; then
						pkgs="$pkgs docker-buildx-plugin"
				fi
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "zypper -q install -y $pkgs"
			)
			echo_docker_as_nonroot
			exit 0
			;;
		*)
			if [ -z "$lsb_dist" ]; then
				if is_darwin; then
					echo
					echo "ERROR: Unsupported operating system 'macOS'"
					echo "Please get Docker Desktop from https://www.docker.com/products/docker-desktop"
					echo
					exit 1
				fi
			fi
			echo
			echo "ERROR: Unsupported distribution '$lsb_dist'"
			echo
			exit 1
			;;
	esac
	exit 1
}

install_taichi() {
	# 安装操作
	echo "开始安装..."
	# 检查Docker是否已安装
	if ! command -v docker &> /dev/null
	then
		echo "Docker 没有安装, 将自动安装"
		do_install
	else
		echo "Docker 已经安装."
	fi

	# 覆盖/etc/docker/daemon.json
	if [ ! -d "/etc/docker" ]; then
		mkdir -p /etc/docker
	fi

  tee /etc/docker/daemon.json <<-'EOF'
{
    "registry-mirrors": [
        "https://dockerproxy.com",
        "https://docker.mirrors.ustc.edu.cn",
        "https://docker.nju.edu.cn"
    ]
}
EOF
	systemctl daemon-reload || true
	systemctl restart docker || true


	mkdir -p /usr/taichi
	echo "目录创建完成"
	rm -rf /usr/taichi/TAICHI_O*
	wget -P /usr/taichi https://download.kookoo.top/TAICHI_OS
	echo "文件下载完成"



	# 授予权限
	chmod 755 /usr/taichi/TAICHI_OS
	echo "授予权限完成"

	# 写入service
	echo "请输入程序运行的端口："
	read port
	cat << EOF > /etc/systemd/system/taichi.service
	[Unit]
	Description=Taichi
	Documentation=https://app.kookoo.top
	After=network.target
	Wants=network.target

	[Service]
	WorkingDirectory=/usr/taichi
	ExecStart=/usr/taichi/TAICHI_OS --port=${port}
	Restart=on-abnormal
	RestartSec=5s
	KillMode=mixed

	StandardOutput=null
	StandardError=syslog

	[Install]
	WantedBy=multi-user.target
EOF
	echo "服务写入完成"

	# 更新配置
	systemctl daemon-reload
	echo "配置更新完成"

	# 启动服务
	systemctl start taichi
	echo "服务启动完成"

	# 设置开机启动
	systemctl enable taichi
	echo "设置开机启动完成"

	# 获取用户的IP地址
	ip=$(hostname -I | awk '{print $1}')

	echo "太极OS安装完成，您可以通过以下地址访问：${ip}:${port}"
}

python_install_taichi() {
	# 安装操作
	echo "开始安装..."
	# 检查Docker是否已安装
	if ! command -v docker &> /dev/null
	then
		echo "Docker 没有安装, 将自动安装"
		do_install
	else
		echo "Docker 已经安装."
	fi

	# 覆盖/etc/docker/daemon.json
	if [ ! -d "/etc/docker" ]; then
		mkdir -p /etc/docker
	fi

  tee /etc/docker/daemon.json <<-'EOF'
{
    "registry-mirrors": [
        "https://dockerproxy.com",
        "https://docker.mirrors.ustc.edu.cn",
        "https://docker.nju.edu.cn"
    ]
}
EOF
	systemctl daemon-reload || true
	systemctl restart docker || true
	echo "Docker配置覆盖完成"
	echo "系统更新并安装依赖"
	if [ -f /etc/os-release ]; then
		. /etc/os-release
		OS=$ID
	else
		echo "Cannot identify the OS"
		exit 1
	fi

	if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
		sudo apt -y update
		sudo apt-get install -y make build-essential libssl-dev zlib1g-dev libbz2-dev \
		libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev \
		xz-utils tk-dev libffi-dev liblzma-dev python3-openssl git unzip
	elif [ "$OS" = "centos" ]; then
		sudo yum update -y
		sudo yum groupinstall -y "Development Tools"
		sudo yum install -y zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl-devel xz xz-devel libffi-devel findutils unzip
	elif [ "$OS" = "fedora" ]; then
		sudo dnf upgrade -y
		sudo dnf groupinstall -y "Development Tools"
		sudo dnf install -y zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl-devel xz xz-devel libffi-devel findutils unzip
	elif [ "$OS" = "opensuse-leap" ]; then
		sudo zypper refresh
		sudo zypper install -y make gcc libssl-devel zlib-devel libbz2-devel \
		readline-devel sqlite3-devel wget curl llvm ncurses-devel ncurses5-devel \
		xz-utils tk-devel libffi-devel liblzma5 python-openssl git unzip
	elif [ "$OS" = "arch" ]; then
		sudo pacman -Syu --needed --noconfirm make gcc openssl zlib bzip2 \
		readline sqlite wget curl llvm ncurses xz tk libffi xz python openssl git unzip
	else
		echo "Unsupported OS"
		exit 1
	fi


	mkdir -p /usr/taichi
	echo "目录创建完成"
	wget -P /usr/taichi https://codeload.github.com/Xingsandesu/TaiChi_OS/zip/refs/heads/master
	unzip /usr/taichi/master -d /usr/taichi
	echo "文件下载并解压完成"
	echo "解压Python源码"
	tar -zvxf /usr/taichi/TaiChi_OS-master/.shell/Python-3.11.7.tgz -C /usr/taichi/TaiChi_OS-master/.shell/
	echo "编译安装Python"
	cd /usr/taichi/TaiChi_OS-master/.shell/Python-3.11.7
	echo "Python源码lto优化"
	./configure --enable-optimizations --prefix=/usr/taichi/python
	echo "Python源码编译"
	make
	echo "Python源码编译"
	make install
	echo "安装软件依赖, 更换国内源"
	cd /usr/taichi/TaiChi_OS-master
	/usr/taichi/python/bin/pip3 install -i https://mirrors.aliyun.com/pypi/simple/ pip -U
	/usr/taichi/python/bin/pip3 config set global.index-url https://mirrors.aliyun.com/pypi/simple/
	/usr/taichi/python/bin/pip3 install -r requirements.txt



	# 写入service
	echo "请输入程序运行的端口："
	read port
	cat << EOF > /etc/systemd/system/taichi.service
	[Unit]
	Description=Taichi
	Documentation=https://app.kookoo.top
	After=network.target
	Wants=network.target

	[Service]
	WorkingDirectory=/usr/taichi
	ExecStart=/usr/taichi/python/bin/python3 /usr/taichi/TaiChi_OS-master/run.py --port=${port}
	Restart=on-abnormal
	RestartSec=5s
	KillMode=mixed

	StandardOutput=null
	StandardError=syslog

	[Install]
	WantedBy=multi-user.target
EOF
	echo "服务写入完成"

	# 更新配置
	systemctl daemon-reload
	echo "配置更新完成"

	# 启动服务
	systemctl start taichi
	echo "服务启动完成"

	# 设置开机启动
	systemctl enable taichi
	echo "设置开机启动完成"

	# 获取用户的IP地址
	ip=$(hostname -I | awk '{print $1}')

	echo "太极OS安装完成，您可以通过以下地址访问：${ip}:${port}"
}


docker_install_taichi() {
	# 安装操作
	echo "开始安装..."
	# 检查Docker是否已安装
	if ! command -v docker &> /dev/null
	then
		echo "Docker 没有安装, 将自动安装"
		do_install
	else
		echo "Docker 已经安装."
	fi

	# 覆盖/etc/docker/daemon.json
	if [ ! -d "/etc/docker" ]; then
		mkdir -p /etc/docker
	fi

  tee /etc/docker/daemon.json <<-'EOF'
{
    "registry-mirrors": [
        "https://dockerproxy.com",
        "https://docker.mirrors.ustc.edu.cn",
        "https://docker.nju.edu.cn"
    ]
}
EOF
	systemctl daemon-reload || true
	systemctl restart docker || true
	echo "Docker配置覆盖完成"

	mkdir -p /usr/taichi
	touch /usr/taichi/config.json
	touch /usr/taichi/data.db
	echo "目录创建完成"

	# 询问用户输入端口
	echo "请输入程序运行的端口:"
	read host_port

	docker run -itd  \
		-p ${host_port}:80 \
		-v /var/run/docker.sock:/var/run/docker.sock  \
		--mount type=bind,source=/usr/taichi/config.json,target=/taichi_os/config.json \
		--mount type=bind,source=/usr/taichi/data.db,target=/taichi_os/data.db \
		--name taichios \
		--restart=always \
		fushin/taichios

	# 获取用户的IP地址
	ip=$(hostname -I | awk '{print $1}' || true)

	echo "太极OS安装完成，您可以通过以下地址访问：${ip}:${host_port}"
}


uninstall_taichi() {
	docker stop taichios || true
	docker rm taichios || true
	docker rmi fushin/taichios || true
	systemctl stop taichi || true
	systemctl disable taichi || true
	rm -rf /usr/taichi || true
	rm -f /etc/systemd/system/taichi.service || true
	systemctl daemon-reload || true
}
update_taichi() {
	if systemctl --all --type=service | grep -q 'taichi'; then
		# systemd版本
		systemctl stop taichi
		rm -rf /usr/taichi/TAICHI_O*
		wget -P /usr/taichi https://download.kookoo.top/TAICHI_OS
		chmod 755 /usr/taichi/TAICHI_OS
		systemctl start taichi
		systemctl daemon-reload
	else
		# Docker版本
		docker stop taichios
		docker rm taichios
		docker rmi fushin/taichios
		# 询问用户输入端口
    	echo "请输入程序运行的端口:"
    	read host_port

    	docker run -itd  \
    		-p ${host_port}:80 \
    		-v /var/run/docker.sock:/var/run/docker.sock  \
    		--mount type=bind,source=/usr/taichi/config.json,target=/taichi_os/config.json \
    		--mount type=bind,source=/usr/taichi/data.db,target=/taichi_os/data.db \
    		--name taichios \
    		--restart=always \
    		fushin/taichios
	fi
}

python_update_taichi() {
	systemctl stop taichi
	mv /usr/taichi/python /tmp/
	mv /usr/taichi/TaiChi_OS-master/config.json /tmp/
	mv /usr/taichi/TaiChi_OS-master/data.db /tmp/
	rm -rf /usr/taichi/*
	wget -P /usr/taichi https://codeload.github.com/Xingsandesu/TaiChi_OS/zip/refs/heads/master
	unzip /usr/taichi/master -d /usr/taichi
	mv /tmp/python /usr/taichi/python
  mv /tmp/config.json /usr/taichi/TaiChi_OS-master/config.json
 	mv /tmp/data.db /usr/taichi/TaiChi_OS-master/data.db
	systemctl start taichi
	systemctl daemon-reload
}


# 获取 Docker 数据路径
get_docker_data_path() {
	docker_info=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "")
	if [ -z "$docker_info" ]; then
		echo "无法获取 Docker 数据路径"
	else
		echo $docker_info
	fi
}

docker_data_path=$(get_docker_data_path)

systemd_status=$(systemctl is-active taichi 2>/dev/null || true)
docker_status=$(docker ps --filter "name=taichi" --format "{{.Status}}" 2>/dev/null || true)

status="未安装"

if [ -n "$systemd_status" ]; then
	status="Systemd 服务 'taichi' 状态: $systemd_status"
fi

if [ -n "$docker_status" ]; then
	status="Docker 容器 'taichi' 状态: $docker_status"
fi

echo "=========太极OS========="
echo "WIKI: https://github.com/Xingsandesu/TaiChi_OS"
echo "官方软件源: https://app.kookoo.top"
echo "$status"
echo "Docker 路径:$docker_data_path"
echo "========================"

echo "请选择操作："
echo "1. 二进制安装(不再维护)"
echo "2. 卸载"
echo "3. 更新"
echo "4. 重启"
echo "5. 恢复默认设置"
echo "6. 重置账号密码"
echo "7. 更换端口"
echo "8. 更换软件源"
echo "9. 使用Docker安装(AMD64, ARM64 如果遇到没有对应glibc库,使用Docker安装,文件管理需要自己指定映射目录)"
echo "10. 源码安装(适用于所有架构, 推荐)"
echo "11. 源码更新"
echo "12. 查看状态"
echo "========================"
echo "优先使用源码安装"
echo "群晖或者OpenWRT使用Docker安装"
echo "========================"

read -p "请输入你的选择（1-12）：" operation

case $operation in
	1)
		# 安装操作
		echo "开始安装..."
		install_taichi
		;;
	2)
		# 卸载操作
		echo "开始卸载..."
		uninstall_taichi
		echo "卸载完成"
		;;
	3)
		# 更新操作
		echo "开始更新..."
		update_taichi
		echo "更新完毕"
		;;
	4)
		# 重启操作
		echo "开始重启..."
		if systemctl --all --type=service | grep -q 'taichi'; then
			  	systemctl restart taichi

    	else
    		docker restart taichios
    	fi
		echo "重启完毕"
		;;
	5)
		# 恢复默认设置
		echo "开始恢复默认设置..."
		if [ -f "/usr/taichi/TaiChi_OS-master/config.json" ]; then
			rm -rf /usr/taichi/TaiChi_OS-master/config.json
		else
			rm -rf /usr/taichi/config.json
		fi
		if systemctl --all --type=service | grep -q 'taichi'; then
			systemctl restart taichi
		else
			docker restart taichios
		fi
		echo "恢复默认设置完毕"
		;;
	6)
		# 重置账号密码
		echo "开始重置账号密码..."
		if [ -f "/usr/taichi/TaiChi_OS-master/data.db" ]; then
			rm -rf /usr/taichi/TaiChi_OS-master/data.db
		else
			rm -rf /usr/taichi/data.db
		fi
		if systemctl --all --type=service | grep -q 'taichi'; then
			systemctl restart taichi
		else
			docker restart taichios
		fi
		echo "重置账号密码完毕"
		;;
	7)
		# 更换端口
		echo "请输入新的端口："
		read new_port
		if docker ps -a --format '{{.Names}}' | grep -q '^taichios$'; then
			docker stop taichios
			docker rm taichios
			docker run -itd  \
				-p ${new_port}:80 \
				-v /var/run/docker.sock:/var/run/docker.sock  \
				--mount type=bind,source=/usr/taichi/config.json,target=/taichi_os/config.json \
				--mount type=bind,source=/usr/taichi/data.db,target=/taichi_os/data.db \
				--name taichios \
				--restart=always \
				fushin/taichios
			echo "Docker 端口更新完毕"
		else
			sed -i "s/--port=[0-9]*/--port=${new_port}/g" /etc/systemd/system/taichi.service
			systemctl daemon-reload
			systemctl restart taichi
			echo "端口更新完毕"
		fi
		;;
	8)
		# 更换软件源
		echo "请输入新的软件源："
		read new_source
		if [[ $new_source != http://* ]]; then
			new_source="http://${new_source}"
		fi
		if [ -f "/usr/taichi/TaiChi_OS-master/config.json" ]; then
			sed -i 's|\("source_url": "\)[^"]*"|\1'${new_source}'"|' /usr/taichi/TaiChi_OS-master/config.json
		else
			sed -i 's|\("source_url": "\)[^"]*"|\1'${new_source}'"|' /usr/taichi/config.json
		fi
		if systemctl --all --type=service | grep -q 'taichi'; then
			systemctl restart taichi
		else
			docker restart taichios
		fi
		;;
	9)
		echo "Docker安装开始"
		docker_install_taichi
		echo "Docker安装完毕"
		;;
	10)
		echo "源码安装开始"
		python_install_taichi
		echo "源码安装完毕"
		;;
	11)
		echo "源码更新开始"
		python_update_taichi
		echo "源码更新完毕"
		;;
	12)
		if docker ps -a --format '{{.Names}}' | grep -q '^taichios$'; then
          docker inspect taichios
		else
        	systemctl status taichi || echo "服务 'taichi' 未运行或不存在"
		fi
		;;
	13)
		echo "请输入新的 Docker 路径："
		read new_docker_path
		if [ -f "/usr/taichi/TaiChi_OS-master/config.json" ]; then
			sed -i 's|\("docker_data_path": "\)[^"]*"|\1'${new_docker_path}'"|' /usr/taichi/TaiChi_OS-master/config.json
		else
			sed -i 's|\("docker_data_path": "\)[^"]*"|\1'${new_docker_path}'"|' /usr/taichi/config.json
		fi
		if systemctl --all --type=service | grep -q 'taichi'; then
			systemctl restart taichi
		else
			docker restart taichios
		fi
		;;
	14)
		echo "修复开始"
		echo "Docker 路径:$docker_data_path"
		docker stop taichios
		if [ -f "/usr/taichi/TaiChi_OS-master/config.json" ]; then
			sed -i 's|\("docker_data_path": "\)[^"]*"|\1'${docker_data_path}'"|' /usr/taichi/TaiChi_OS-master/config.json
		else
			sed -i 's|\("docker_data_path": "\)[^"]*"|\1'${docker_data_path}'"|' /usr/taichi/config.json
		fi
		if systemctl --all --type=service | grep -q 'taichi'; then
			systemctl restart taichi
		else
			docker restart taichios
		fi
		;;
	*)
		echo "无效的操作"
		;;
esac
