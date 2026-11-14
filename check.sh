#!/bin/sh
# apt-transport-curl-check: prints the state of the installation of apt-transport-curl (the replacement of the https method of apt).
# Run it as root on the phone and paste the output when something does not work:   sh /usr/share/doc/apt-transport-curl/check.sh
# It changes nothing. No account data or addresses of the phone are printed.
M=/usr/lib/apt/methods
say() { printf '%s\n' "$*"; }
ok() { say "[ ok ] $*"; }
bad() { say "[FAIL] $*"; FAILS=$((FAILS + 1)); }
FAILS=0

say "== apt-transport-curl check ($(date '+%F %T' 2>/dev/null))"
[ "$(id -u 2>/dev/null)" = 0 ] && ok "running as root" || say "[note] not root: some checks may be incomplete (use: sudo gainroot)"

say; say "== packages"
for p in apt-transport-curl curl apt-transport-https; do
    st=$(dpkg -l "$p" 2>/dev/null | grep "^.. *$p " | cut -c1-2,5-)
    case $st in ii*) ok "$p: $(dpkg -l "$p" | grep "^ii" | tr -s ' ' | cut -d' ' -f3)" ;; *) bad "$p is not installed properly (${st:-not found}); install curl first, then apt-transport-curl" ;; esac
done

say; say "== the method files"
ls -l $M/https $M/https.distrib 2>&1
if [ -x $M/https ]; then
    first=$(head -n 1 $M/https 2>/dev/null)
    size=$(wc -c < $M/https | tr -d ' ')
    case $first in
        '#!/bin/bash'*) ok "https is the script of apt-transport-curl ($size bytes)" ;;
        *) bad "https is not our script (first bytes differ; a size around 5 kB is expected, the original is about 25 kB): reinstall apt-transport-curl with dpkg -i" ;;
    esac
    [ -x $M/https.distrib ] && ok "the original method is kept as https.distrib" || bad "https.distrib is missing (the diversion did not happen)"
    dpkg-divert --list 2>/dev/null | grep "https" || say "(no diversion of https listed)"
else
    bad "$M/https is missing or not executable"
fi
[ -x /bin/bash ] && ok "bash: $(/bin/bash --version | head -n 1)" || bad "/bin/bash is missing: the method is a bash script"

say; say "== curl"
if [ -x /usr/bin/curl ]; then
    v=$(/usr/bin/curl --version 2>&1 | head -n 1)
    say "$v"
    case $v in *mbedTLS*|*OpenSSL/3*) ok "curl has a modern TLS library" ;; *) bad "this curl is probably the old one of the system (TLS 1.0 only): install the package curl of the repository" ;; esac
else
    bad "/usr/bin/curl is missing: install the package curl"
fi

say; say "== the handshake with apt"
out=$(: | timeout -t 5 $M/https 2>&1 | head -n 3)
if [ -z "$out" ]; then out=$(: | $M/https 2>&1 | head -n 3); fi
say "$out"
case $out in *"100 Capabilities"*) ok "the method answers 100 Capabilities" ;; *) bad "the method does not say 100 Capabilities: this is why apt reports that the method died" ;; esac

say; say "== a download (github.com over TLS 1.2/1.3, through the method)"
res=$(printf '600 URI Acquire\nURI: https://github.com/robots.txt\nFilename: /tmp/atc-check.out\n\n' | timeout -t 40 $M/https 2>&1 | head -n 12)
rm -f /tmp/atc-check.out
say "$res" | head -n 4
case $res in *"201 URI Done"*) ok "a file was downloaded" ;; *) bad "the download failed (see the message above; a wrong clock breaks the certificate check)" ;; esac

say; say "== clock and memory"
y=$(date +%Y 2>/dev/null); say "year: $y"
[ "${y:-0}" -ge 2024 ] 2>/dev/null && ok "the clock looks right" || bad "the clock is wrong: certificates cannot be verified (set the date/time, ntp-sync)"
grep -i "^\(MemFree\|SwapFree\)" /proc/meminfo 2>/dev/null

say; say "== apt settings that matter"
apt-config dump 2>/dev/null | grep -i "^Acquire::https" | head -n 8
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do [ -f "$f" ] && grep -H "^deb.*https" "$f"; done 2>/dev/null

say; say "== what the method wrote to its error log (/tmp/apt-transport-curl.errors)"
if [ -s /tmp/apt-transport-curl.errors ]; then tail -n 10 /tmp/apt-transport-curl.errors; else say "(empty)"; fi
say "For the whole conversation with apt: touch /etc/apt/apt-transport-curl.debug, run apt-get update, then cat /tmp/apt-transport-curl.log"

say
if [ "$FAILS" -eq 0 ]; then say "RESULT: everything looks right"; else say "RESULT: $FAILS problem(s) found, see the [FAIL] lines"; fi
exit 0
