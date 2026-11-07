#!/bin/sh
# fch 的外部构建脚本：编译 App，组装成 .deb。
set -eu
: "${APELIN_PACKAGE_DIR:?run this through apelin_project_build}"
: "${APELIN_PROJECT_ROOT:?}" "${APELIN_BOOTSTRAP:?}" "${APELIN_ARCHITECTURE:?}"
: "${APELIN_BUILD_ID:?}" "${TMPDIR:?}"
: "${APELIN_PREFIX?}" # roothide 上为空，rootless 上是 /var/jb
stage="$(mktemp -d "${TMPDIR:?}stage.XXXXXX")"
trap 'rm -rf -- "${stage:?}"' EXIT

src="${APELIN_PROJECT_ROOT:?}"
cd "${src:?}"

PKGID="$(sed -n 's/^#define FCL_PACKAGE_ID "\(.*\)"$/\1/p' "${src:?}/Sources/pkgid.h" | head -n 1)"
if [ -z "${PKGID:-}" ]; then
	echo "Sources/pkgid.h 里找不到 FCL_PACKAGE_ID" >&2
	exit 1
fi
VERSION="1.0.11"

case "${APELIN_BOOTSTRAP:?}" in
	roothide) ARCHS="arm64e" ;;
	rootless) ARCHS="arm64 arm64e" ;;
	*) echo "未知的 bootstrap: ${APELIN_BOOTSTRAP}" >&2; exit 1 ;;
esac

work="${stage:?}/bin"
mkdir -p "${work:?}"

for arch in ${ARCHS:?}; do
	clang -arch "${arch:?}" -fobjc-arc -O2 -Wall -I"${src:?}/Sources" \
		-o "${work:?}/FCLCallLog-${arch:?}" \
		"${src:?}/Sources/FCLRootController.m" "${src:?}/Sources/FCLAppDelegate.m" \
		"${src:?}/Sources/FCLStore.m" \
		-framework Foundation -framework UIKit -framework CoreGraphics \
		-framework Contacts -framework ContactsUI -lsqlite3
done

# shellcheck disable=SC2086
set -- ${ARCHS:?}
if [ "$#" -eq 1 ]; then
	cp "${work:?}/FCLCallLog-$1" "${work:?}/FCLCallLog"
else
	lipo -create -output "${work:?}/FCLCallLog" \
		"${work:?}/FCLCallLog-arm64" "${work:?}/FCLCallLog-arm64e"
fi

pkg="${stage:?}/root"
base="${pkg:?}${APELIN_PREFIX}"
app="${base:?}/Applications/FCLCallLog.app"
mkdir -p "${app:?}" "${pkg:?}/DEBIAN"

cp "${work:?}/FCLCallLog" "${app:?}/FCLCallLog"
sed "s|@PKGID@|${PKGID}|g" "${src:?}/Resources/App-Info.plist" > "${app:?}/Info.plist"
for icon in "${src:?}/Resources/AppIcon/"*.png; do
	cp "${icon:?}" "${app:?}/"
done
chmod 0755 "${app:?}/FCLCallLog"
chmod 0644 "${app:?}/Info.plist"

sed "s|@PKGID@|${PKGID}|g; s|@PREFIX@|${APELIN_PREFIX}|g" "${src:?}/apelin/postinst" \
	> "${pkg:?}/DEBIAN/postinst"
chmod 0755 "${pkg:?}/DEBIAN/postinst"
sh -n "${pkg:?}/DEBIAN/postinst"

# 签名必须在所有改动之后：先签名再写内容会让签名失效。
sed "s|@PKGID@|${PKGID}|g" "${src:?}/tools/App.entitlements" > "${work:?}/App.entitlements"
ldid -S"${work:?}/App.entitlements" "${app:?}/FCLCallLog"

cat > "${pkg:?}/DEBIAN/control" <<EOF
Package: ${PKGID}
Version: ${VERSION}
Architecture: ${APELIN_ARCHITECTURE}
Section: Tweaks
Priority: optional
Maintainer: fch
Author: fch
Name: 添加通话记录
Description: 一个 App：手动添加通话记录（联系人、号码、时间、呼出/呼入/未接、时长），写入本机通话记录库。
EOF

dpkg-deb -b --root-owner-group "${pkg:?}" "${APELIN_PACKAGE_DIR:?}/"
