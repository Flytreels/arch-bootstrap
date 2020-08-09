
#
# arch-bootstrap: 使用任何GNU发行版来制作一个基本的Arch Linux系统。
#
# 必要依赖: bash >= 4, coreutils, wget, sed, gawk, tar, gzip, chroot(proot), xz.
# 原Project: https://github.com/tokland/arch-bootstrap
# 由Flytreels给予zh_cn的语言支持并修改完善,GPLv2

# 安装:
#
#   # install -m 755 arch-bootstrap.sh /usr/local/bin/arch-bootstrap
#

# pacman所需的软件包（请参阅get-pacman-dependencies.sh）
PACMAN_PACKAGES=(
  acl archlinux-keyring attr bzip2 curl expat glibc gpgme libarchive
  libassuan libgpg-error libnghttp2 libssh2 lzo openssl pacman pacman-mirrorlist xz zlib
  krb5 e2fsprogs keyutils libidn2 libunistring gcc-libs lz4 libpsl icu libunistring zstd ncurses readline bash
)
BASIC_PACKAGES=(${PACMAN_PACKAGES[*]} filesystem)
EXTRA_PACKAGES=(coreutils grep gawk file tar systemd sed)
#DEFAULT_REPO_URL="http://mirrors.kernel.org/archlinux"
#DEFAULT_ARM_REPO_URL="http://mirror.archlinuxarm.org"
DEFAULT_REPO_URL="http://mirrors.163.com/archlinux"
DEFAULT_ARM_REPO_URL="http://mirrors.163.com/archlinuxarm"

stderr() { 
  echo "$@" >&2 
}

debug() {
  stderr "--- $@"
}

extract_href() {
  sed -n '/<a / s/^.*<a [^>]*href="\([^\"]*\)".*$/\1/p'
}

fetch() {
  curl -L -s -q "$@"
}

fetch_file() {
  local FILEPATH=$1
  shift
  if [[ -e "$FILEPATH" ]]; then
    curl -L -z -q "$FILEPATH" -o "$FILEPATH" "$@"
  else
    curl -L -o -q "$FILEPATH" "$@"
  fi
}

uncompress() {
  local FILEPATH=$1 DEST=$2
  
  case "$FILEPATH" in
    *.gz) 
      tar xzf "$FILEPATH" -C "$DEST";;
    *.tar.xz) 
     tar xJf "$FILEPATH" -C "$DEST/";;
    *) 
      debug "错误: 未知的软件包格式: $FILEPATH"
      return 1;;
  esac
}  

###

get_default_repo() {
  local ARCH=$1
  if [[ "$ARCH" == arm* || "$ARCH" == aarch64 ]]; then
    echo $DEFAULT_ARM_REPO_URL
  else
    echo $DEFAULT_REPO_URL
  fi
}

get_core_repo_url() {
  local REPO_URL=$1 ARCH=$2
  if [[ "$ARCH" == arm* || "$ARCH" == aarch64 ]]; then
    echo "${REPO_URL%/}/$ARCH/core"
  else
    echo "${REPO_URL%/}/core/os/$ARCH"
  fi
}

get_template_repo_url() {
  local REPO_URL=$1 ARCH=$2
  if [[ "$ARCH" == arm* || "$ARCH" == aarch64 ]]; then
    echo "${REPO_URL%/}/$ARCH/\$repo"
  else
    echo "${REPO_URL%/}/\$repo/os/$ARCH"
  fi
}

configure_pacman() {
  local DEST=$1 ARCH=$2
  debug "正在配置DNS与pacman"
  rm -rf $DEST/etc/resolv.conf
  if [ -f "/etc/resolv.conf" ];then
  cat "/etc/resolv.conf" >"$DEST/etc/resolv.conf"
  else
  echo "nameserver 114.114.114.114">$DEST/etc/resolv.conf
  fi
  SERVER=$(get_template_repo_url "$REPO_URL" "$ARCH")
  echo "Server = $SERVER" > "$DEST/etc/pacman.d/mirrorlist"
}

configure_minimal_system() {
  local DEST=$1
  
  mkdir -p "$DEST/dev"
  sed -ie 's/^root:.*$/root:$1$GT9AUpJe$oXANVIjIzcnmOpY07iaGi\/:14657::::::/' "$DEST/etc/shadow"
  touch "$DEST/etc/group"
  echo "localhost" > "$DEST/etc/hostname"

  rm -f "$DEST/etc/mtab"
  echo "rootfs / rootfs rw 0 0" > "$DEST/etc/mtab"
  test -e "$DEST/dev/null" || mknod "$DEST/dev/null" c 1 3
  test -e "$DEST/dev/random" || mknod -m 0644 "$DEST/dev/random" c 1 8
  test -e "$DEST/dev/urandom" || mknod -m 0644 "$DEST/dev/urandom" c 1 9

  sed -i "s/^[[:space:]]*\(CheckSpace\)/# \1/" "$DEST/etc/pacman.conf"
  sed -i "s/^[[:space:]]*SigLevel[[:space:]]*=.*$/SigLevel = Never/" "$DEST/etc/pacman.conf"
}

fetch_packages_list() {
  local REPO=$1 
  
  debug "fetch packages list: $REPO/"
  fetch "$REPO/" | extract_href | awk -F"/" '{print $NF}' | sort -rn ||
    { debug "Error: cannot fetch packages list: $REPO"; return 1; }
}

install_pacman_packages() {
  local BASIC_PACKAGES=$1 DEST=$2 LIST=$3 DOWNLOAD_DIR=$4
  debug "pacman package and dependencies: $BASIC_PACKAGES"
  
  for PACKAGE in $BASIC_PACKAGES; do
    local FILE=$(echo "$LIST" | grep -m1 "^$PACKAGE-[[:digit:]].*\(\.gz\|\.xz\)$")
    test "$FILE" || { debug "错误: 无法找到以下软件包: $PACKAGE"; return 1; }
    local FILEPATH="$DOWNLOAD_DIR/$FILE"
    
    debug "下载软件包: $REPO/$FILE"
    fetch_file "$FILEPATH" "$REPO/$FILE"
    debug "解压软件包: $FILEPATH"
    uncompress "$FILEPATH" "$DEST"
  done
}

configure_static_qemu() {
  local ARCH=$1 DEST=$2
  [[ "$ARCH" == arm* ]] && ARCH=arm
  QEMU_STATIC_BIN=$(which qemu-$ARCH-static || echo )
  [[ -e "$QEMU_STATIC_BIN" ]] ||\
    { debug "无法找到为 $ARCH 使用的QEMU, 已被忽略"; return 0; }
  cp "$QEMU_STATIC_BIN" "$DEST/usr/bin"
}

install_packages() {
  local ARCH=$1 DEST=$2 PACKAGES=$3
  debug "安装软件包: $PACKAGES"
  LD_PRELOAD
  LC_ALL=C
  if [ `id -u` -eq 0 ];then
     chroot "$DEST" /usr/bin/pacman --noconfirm --arch $ARCH -Syq --overwrite="*" --noconfirm acl archlinux-keyring attr bzip2 curl expat glibc gpgme libarchive libassuan libgpg-error libnghttp2 libssh2 lzo openssl pacman pacman-mirrorlist xz zlib krb5 e2fsprogs keyutils libidn2 libunistring gcc-libs lz4 libpsl icu libunistring zstd ncurses readline bash
  else
     proot -r "$DEST" /usr/bin/pacman --noconfirm --arch $ARCH -Syq --overwrite="*" --noconfirm acl archlinux-keyring attr bzip2 curl expat glibc gpgme libarchive libassuan libgpg-error libnghttp2 libssh2 lzo openssl pacman pacman-mirrorlist xz zlib krb5 e2fsprogs keyutils libidn2 libunistring gcc-libs lz4 libpsl icu libunistring zstd ncurses readline bash
  fi

}

show_usage() {
  stderr "用法: $(basename "$0") [-q] [-a i686|x86_64|arm|aarch64] [-r 软件源连接] [-d Rootfs目标目录] 发行版名称"
}

main() {
  # Process arguments and options
  test $# -eq 0 && set -- "-h"
  local ARCH=
  local REPO_URL=
  local USE_QEMU=
  local DOWNLOAD_DIR=
  local PRESERVE_DOWNLOAD_DIR=
  
  while getopts "qa:r:d:h" ARG; do
    case "$ARG" in
      a) ARCH=$OPTARG;;
      r) REPO_URL=$OPTARG;;
      q) USE_QEMU=true;;
      d) DOWNLOAD_DIR=$OPTARG
         PRESERVE_DOWNLOAD_DIR=true;;
      *) show_usage; return 1;;
    esac
  done
  shift $(($OPTIND-1))
  test $# -eq 1 || { show_usage; return 1; }
  
  [[ -z "$ARCH" ]] && ARCH=$(uname -m)
  [[ -z "$REPO_URL" ]] &&REPO_URL=$(get_default_repo "$ARCH")
  
  local DEST=$1
  local REPO=$(get_core_repo_url "$REPO_URL" "$ARCH")
  [[ -z "$DOWNLOAD_DIR" ]] && DOWNLOAD_DIR=$(mktemp -d)
  mkdir -p "$DOWNLOAD_DIR"
  [[ -z "$PRESERVE_DOWNLOAD_DIR" ]] && trap "rm -rf '$DOWNLOAD_DIR'" KILL TERM EXIT
  debug "发行版名称: $DEST"
  debug "Core软件包: $REPO"
  debug "目标目录: $DOWNLOAD_DIR"
  
  # Fetch packages, install system and do a minimal configuration
  mkdir -p "$DEST"
  local LIST=$(fetch_packages_list $REPO)
  install_pacman_packages "${BASIC_PACKAGES[*]}" "$DEST" "$LIST" "$DOWNLOAD_DIR"
  configure_pacman "$DEST" "$ARCH"
  configure_minimal_system "$DEST"
  [[ -n "$USE_QEMU" ]] && configure_static_qemu "$ARCH" "$DEST"
  install_packages "$ARCH" "$DEST" "${BASIC_PACKAGES[*]} ${EXTRA_PACKAGES[*]}"
  configure_pacman "$DEST" "$ARCH" # Pacman must be re-configured
  [[ -z "$PRESERVE_DOWNLOAD_DIR" ]] && rm -rf "$DOWNLOAD_DIR"
  
  debug "完成!"
  debug 
}

main "$@"
