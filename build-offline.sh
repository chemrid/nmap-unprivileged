#!/bin/sh
# Offline build script for nmap-unprivileged.
#
# Requirements (all standard on any Linux distro):
#   - gcc, g++, make  (build-essential / Development Tools)
#   - perl             (required by OpenSSL ./Configure)
#   - linux-libc-dev OR linux-headers-* (kernel headers: linux/limits.h etc.)
#   - javac            (optional: only needed to compile JDWP NSE helper classes)
#
# No network access required — all dependencies are bundled in this source tree.
# OpenSSL 3.4.1 is included under openssl/ (Apache 2.0 license).
# Text::Template Perl module is vendored under vendor/perl/ (Artistic/GPL).
set -e

SRCDIR="$(cd "$(dirname "$0")" && pwd)"
OPENSSL_DIR="$SRCDIR/openssl"
OPENSSL_PREFIX="$SRCDIR/openssl-build"

# Use vendored Perl modules (Text::Template etc.) without installing them
# system-wide. This allows building on air-gapped systems where
# libtext-template-perl / perl-Text-Template is not available in the repo.
export PERL5LIB="$SRCDIR/vendor/perl${PERL5LIB:+:$PERL5LIB}"

# ---------------------------------------------------------------------------
# 0. Preflight checks — catch missing build dependencies early with clear
#    error messages instead of cryptic mid-build failures.
# ---------------------------------------------------------------------------
if ! command -v gcc >/dev/null 2>&1; then
  echo "ERROR: gcc not found. Install build tools:"
  echo "       Debian/Astra: apt-get install build-essential"
  echo "       RHEL/CentOS:  yum install gcc gcc-c++ make"
  exit 1
fi

# Check for Linux kernel headers (provides linux/limits.h).
# Prefer /usr/include/linux (linux-libc-dev), but also accept headers
# installed by linux-headers-* packages (Astra Linux, minimal Debian).
KERNEL_INCLUDE=""
if [ -f /usr/include/linux/limits.h ]; then
  KERNEL_INCLUDE="/usr/include"
else
  KERNEL_INCLUDE="$(find /usr/src -maxdepth 5 -name 'limits.h' \
    -path '*/linux/limits.h' 2>/dev/null | head -1 | sed 's|/linux/limits\.h||')"
fi
if [ -z "$KERNEL_INCLUDE" ]; then
  echo "ERROR: Linux kernel headers not found (linux/limits.h is missing)."
  echo "       Debian/Astra: apt-get install linux-libc-dev"
  echo "       or:           apt-get install linux-headers-\$(uname -r)"
  echo "       RHEL/CentOS:  yum install kernel-headers"
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Clean any stale generated files from previous configure runs
#    (important when sources come from a Windows checkout)
# ---------------------------------------------------------------------------
if [ -f Makefile ]; then
  make distclean || true
fi

# ---------------------------------------------------------------------------
# 2. Fix CRLF line endings — required when sources are checked out on Windows.
#    Covers shell scripts and autoconf config templates (*.in).
#    Do NOT include *.ac or *.am — touching them makes make try to regenerate
#    configure via autoconf, which is not available offline.
# ---------------------------------------------------------------------------
find . -type f \( \
  -name "*.sh" -o -name "configure" -o -name "depcomp" \
  -o -name "install-sh" -o -name "config.guess" -o -name "config.sub" \
  -o -name "ltmain.sh" -o -name "missing" -o -name "compile" \
  -o -name "ylwrap" -o -name "*.in" \
  \) | xargs sed -i 's/$//' 2>/dev/null || true
# Also fix nmap runtime data files (parsed at runtime, CRLF breaks parsing)
sed -i 's/$//' nmap-service-probes nmap-services nmap-os-db \
  nmap-protocols nmap-rpc nmap-mac-prefixes 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Patch nmap configure for OpenSSL 3.x compatibility.
#    In OpenSSL 3.x, BIO_int_ctrl() was converted from a real function to
#    a macro wrapping BIO_ctrl(). As a result, AC_CHECK_LIB(crypto,
#    BIO_int_ctrl) returns "no" even when libcrypto is correctly linked,
#    causing configure to abort with "libcrypto was not found".
#    Replace the check with BIO_new, which is a real function in all
#    OpenSSL versions (1.x and 3.x).
# ---------------------------------------------------------------------------
sed -i 's/BIO_int_ctrl/BIO_new/g' configure

# ---------------------------------------------------------------------------
# 4. Compile JDWP NSE helper classes from Java source (no binary blobs).
#    Requires javac. Skipped with a warning if javac is not installed.
# ---------------------------------------------------------------------------
JDWP_DIR="$SRCDIR/nselib/data/jdwp-class"
if command -v javac >/dev/null 2>&1; then
  echo "Compiling JDWP NSE helper classes..."
  javac -source 8 -target 8 "$JDWP_DIR"/*.java 2>&1 || \
    { echo "WARNING: javac failed — JDWP NSE scripts will not work"; }
else
  echo "WARNING: javac not found — JDWP NSE scripts (jdwp-*.nse) will not work."
  echo "         Install a JDK to enable Java Debug Wire Protocol scanning."
fi

# ---------------------------------------------------------------------------
# 5. Build OpenSSL 3.4.1 as a static library (Apache 2.0, source in openssl/).
#    Requires: perl (for OpenSSL's ./Configure script).
#    Result is installed to openssl-build/ inside the source tree.
# ---------------------------------------------------------------------------
if [ ! -f "$OPENSSL_PREFIX/lib/libssl.a" ] && \
   [ ! -f "$OPENSSL_PREFIX/lib64/libssl.a" ]; then
  echo "Building bundled OpenSSL 3.4.1..."
  if ! command -v perl >/dev/null 2>&1; then
    echo "ERROR: perl is required to build OpenSSL. Install perl and retry."
    exit 1
  fi
  if ! perl -MText::Template -e1 2>/dev/null; then
    echo "ERROR: Perl module Text::Template not found even in vendor/perl/."
    echo "       This should not happen — check that vendor/perl/Text/Template.pm exists."
    exit 1
  fi
  mkdir -p "$OPENSSL_PREFIX"
  cd "$OPENSSL_DIR"
  perl Configure \
    no-shared no-tests no-ui-console no-asm \
    --prefix="$OPENSSL_PREFIX" \
    --openssldir="$OPENSSL_PREFIX/ssl" \
    --libdir=lib
  make -j"$(nproc 2>/dev/null || echo 4)"
  make install_sw
  cd "$SRCDIR"
  echo "OpenSSL build complete: $OPENSSL_PREFIX"
else
  echo "OpenSSL already built, skipping."
fi

# Resolve actual lib dir (some systems use lib64)
OPENSSL_LIBDIR="$OPENSSL_PREFIX/lib"
[ -f "$OPENSSL_PREFIX/lib64/libssl.a" ] && OPENSSL_LIBDIR="$OPENSSL_PREFIX/lib64"

# ---------------------------------------------------------------------------
# 6. Configure and build nmap.
#    LIBS="-ldl -pthread" is required because static libcrypto.a (built with
#    no-shared) depends on libdl and pthreads. Without these flags, the
#    configure AC_CHECK_LIB(crypto, BIO_new) link test fails even though
#    the library is correctly present, and configure aborts.
#
#    CPPFLAGS: if kernel headers are in a non-standard path (Astra Linux with
#    linux-headers-* but no linux-libc-dev), pass the include path explicitly.
# ---------------------------------------------------------------------------
EXTRA_CPPFLAGS=""
[ "$KERNEL_INCLUDE" != "/usr/include" ] && EXTRA_CPPFLAGS="-I$KERNEL_INCLUDE"

LIBS="-ldl -pthread" CPPFLAGS="$EXTRA_CPPFLAGS" ./configure \
  --without-nping \
  --without-ndiff \
  --without-zenmap \
  --without-ncat \
  --without-libssh2 \
  --with-openssl="$OPENSSL_PREFIX" \
  --with-libpcap=included \
  --with-libdnet=included \
  --with-lua=included

make -j"$(nproc 2>/dev/null || echo 4)"
