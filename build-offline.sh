#!/bin/sh
# Offline build script for nmap-unprivileged.
# Requirements: gcc, g++, make (standard build-essential on any Linux distro).
# No network access required — all dependencies are bundled in this source tree.
set -e

# Clean any stale generated files from previous configure runs
# (important when sources come from a Windows checkout)
if [ -f Makefile ]; then
  make distclean || true
fi

# Fix CRLF line endings — required when sources are checked out on Windows.
# Covers shell scripts and autoconf config templates (*.in).
# Do NOT include *.ac or *.am — touching them makes make try to regenerate
# configure via autoconf, which is not available offline.
find . -type f \( \
  -name "*.sh" -o -name "configure" -o -name "depcomp" \
  -o -name "install-sh" -o -name "config.guess" -o -name "config.sub" \
  -o -name "ltmain.sh" -o -name "missing" -o -name "compile" \
  -o -name "ylwrap" -o -name "*.in" \
  \) | xargs sed -i 's/\r$//' 2>/dev/null || true
# Also fix nmap runtime data files (parsed at runtime, CRLF breaks parsing)
sed -i 's/\r$//' nmap-service-probes nmap-services nmap-os-db \
  nmap-protocols nmap-rpc nmap-mac-prefixes 2>/dev/null || true

./configure \
  --without-nping \
  --without-ndiff \
  --without-zenmap \
  --without-ncat \
  --without-openssl \
  --without-libssh2 \
  --with-libpcap=included \
  --with-libdnet=included \
  --with-lua=included

make -j"$(nproc 2>/dev/null || echo 4)"
