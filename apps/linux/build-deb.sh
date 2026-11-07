#!/usr/bin/env bash
# Builds extendpad-sender_<version>_<arch>.deb.
#
#   ./build-deb.sh              # amd64, version 0.1.0
#   VERSION=0.2.0 ./build-deb.sh
#
# Requires Go and dpkg-deb (Ubuntu/Debian).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

version="${VERSION:-0.1.0}"
arch="${ARCH:-amd64}"
package="extendpad-sender"
build="$here/build"
stage="$build/stage"

rm -rf "$build"
mkdir -p "$stage/DEBIAN" \
         "$stage/usr/bin" \
         "$stage/lib/systemd/system" \
         "$stage/usr/share/doc/$package"

CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
  go build -trimpath -ldflags "-s -w -X main.version=$version" \
  -o "$stage/usr/bin/extendpad" .

install -m 0644 packaging/extendpad@.service "$stage/lib/systemd/system/extendpad@.service"
install -m 0644 README.md "$stage/usr/share/doc/$package/README.md"
if [ -f "$here/../../NOTICE.md" ]; then
  install -m 0644 "$here/../../NOTICE.md" "$stage/usr/share/doc/$package/NOTICE.md"
fi
if [ -f "$here/../../LICENSE" ]; then
  install -m 0644 "$here/../../LICENSE" "$stage/usr/share/doc/$package/copyright"
fi

cat > "$stage/DEBIAN/control" <<EOF
Package: $package
Version: $version
Section: net
Priority: optional
Architecture: $arch
Depends: ffmpeg, x11-xserver-utils, xcvt
Recommends: android-tools-adb
Maintainer: ExtendPad <noreply@extendpad.local>
Description: Show this Linux desktop on an ExtendPad receiver
 The optional Linux sender from the ExtendPad project. It mirrors an X11
 desktop to an Android or Mac ExtendPad receiver over Wi-Fi or USB, and lets
 the receiver's touch and keyboard drive the desktop.
EOF

cat > "$stage/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
systemctl daemon-reload >/dev/null 2>&1 || true
user="${SUDO_USER:-}"
if [ -n "$user" ] && [ "$user" != "root" ] && id "$user" >/dev/null 2>&1; then
  systemctl enable "extendpad@$user.service" >/dev/null 2>&1 || true
  # The advertisement and wake listener now live inside `extendpad run`.
  systemctl disable --now "extendpad-pair@$user.service" >/dev/null 2>&1 || true
  echo "ExtendPad sender installed for $user."
  echo "Pair from the tablet: tap Connect on the \"Ubuntu ($user)\" host"
  echo "  and run: extendpad confirm <code>"
  echo "Or pair from here:    sudo -u $user extendpad pair --host <tablet-ip>"
  echo "Start streaming:      sudo systemctl start extendpad@$user.service"
fi
exit 0
EOF

cat > "$stage/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ]; then
  for pattern in 'extendpad@*.service' 'extendpad-pair@*.service'; do
    systemctl list-units --type=service --all --no-legend "$pattern" 2>/dev/null |
      awk '{print $1}' | while read -r unit; do
        [ -n "$unit" ] && systemctl stop "$unit" >/dev/null 2>&1 || true
      done
  done
fi
exit 0
EOF

cat > "$stage/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
systemctl daemon-reload >/dev/null 2>&1 || true
exit 0
EOF

chmod 0755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/prerm" "$stage/DEBIAN/postrm"
find "$stage" -type d -exec chmod 0755 {} +

output="$build/${package}_${version}_${arch}.deb"
dpkg-deb --build --root-owner-group "$stage" "$output" >/dev/null
echo "$output"
