# apt-transport-curl: apt over modern HTTPS

The apt of Maemo 5 (0.7.20) fetches `https://` URLs with its own method `/usr/lib/apt/methods/https`, which uses the old libcurl with
OpenSSL 0.9.8. That is TLS 1.0 only, and GitHub, GitHub Pages and most other servers now refuse it
(`SSL23_GET_SERVER_HELLO:tlsv1 alert protocol version`). The package replaces the method with a short bash script (file `https`) that
runs `/usr/bin/curl` 8.x (mbedTLS, TLS 1.2/1.3). apt, Application Manager and `apt-get` need no other change.

## Install
From the repository ([apt-repo.md](../../DOC/apt-repo.md)) over plain HTTP, or by hand: `dpkg -i apt-transport-curl_0.1-1maemo1_armel.deb`
(needs `curl` and the system package `apt-transport-https`). Then a source line such as
```
deb https://USER.github.io/n900-repository fremantle main
```
works. `dpkg-divert` moves the original method to `https.distrib` and `dpkg -r` puts it back (tested).

## How it works
apt starts the method and talks to it on stdin/stdout: `100 Capabilities`, `601 Configuration` (apt settings), `600 URI Acquire`
(URL and target file) answered with `200 URI Start` and `201 URI Done` (size, Last-Modified, MD5/SHA1/SHA256) or `400 URI Failure`.
The script downloads with curl to the file apt names. Requests are handled one after another (`Pipeline: true` is announced because apt
sends several at once).

Two quirks of this old apt, found on the phone:
- if the method answers at once, apt never reads the first message and hangs; the script waits 0.2 s before `100 Capabilities`
  (the compiled methods are slower to start),
- a message must arrive in a single write (the script builds it first).

## Settings (apt.conf)
| Setting | Meaning |
|---|---|
| `Acquire::https::CaInfo` | CA bundle file (default: the one of the curl package) |
| `Acquire::https::Proxy` | proxy URL |
| `Acquire::https::Timeout` | connect and stall timeout in seconds (60) |
| `Acquire::https::Curl-Insecure "true"` | no certificate check |

`Acquire::https::Verify-Peer` is **ignored** on purpose: the phone ships `Verify-Peer "false"` in `/etc/apt/apt.conf.d`, which would
silently disable the check. Certificates are always verified unless `Curl-Insecure` is set.
`APT_CURL_DEBUG=/tmp/log apt-get update` writes the whole conversation with apt into a file.

## Not done
No `If-Modified-Since` (indexes are downloaded again on each `apt-get update`; they are small), no resuming of partial downloads, no
HTTP authentication. Tested with a self-signed server on the PC (CaInfo, missing CA, Curl-Insecure), github.com (TLS 1.3), install of a
package, removal.

## When something does not work (0.1-1maemo2)
"Method https has died unexpectedly" says nothing, so the method now tells why it ends:
- problems go to stderr (apt prints them) and to `/tmp/apt-transport-curl.errors`; a missing `/usr/bin/curl` is reported once at the start and every request then fails with "install the package curl" instead of an exit code;
- a closed output (a pipe to `head`) or the end of the input is not an error, the method ends with 0.

`/usr/share/doc/apt-transport-curl/check.sh` (also `apt-transport-curl-check` in the path) prints the whole state of the installation and changes nothing: the packages (`apt-transport-curl`, `curl`, `apt-transport-https`), the method files (`https` should be our script of about 5 kB, `https.distrib` the original of about 25 kB, the diversion), bash and curl (a modern TLS library), the handshake with apt (`100 Capabilities`), a test download through the method, the clock (a wrong clock breaks certificates), free memory, the apt settings, the sources with `https` and the last lines of the error log. The result is `[ ok ]` / `[FAIL]` lines and a `RESULT:` line; it is meant to be pasted into a bug report. Run it as root: `sh /usr/share/doc/apt-transport-curl/check.sh`.

## The Application Manager and "Preparing installation" (fixed in 0.1-1maemo3)
Up to 0.1-1maemo2 the Application Manager could hang for ever on "Preparing installation" (or while refreshing the lists) when it used this method. Cause, found with `strace` on both ends: the method wrote its first message (`100 Capabilities`) with the printf builtin of bash in **two** `write()` calls (the lines first, the empty line that ends a message a millisecond later). The `apt-worker` of the Application Manager is woken by the first write, reads the 45 bytes, does not see the end of the message and never looks again; the method waits for a request, `apt-worker` waits for the message. `apt-get` copes with a message in pieces, so it worked in a terminal, and a slow `apt-worker` (or `strace` on it) read both pieces at once, so the hang came and went. Since 1maemo3 every message is built in a variable and written with a single `printf '%s'`, which makes one `write()` (checked with `strace -e trace=write`).

## Dependencies (1maemo4)
The script needs `/bin/bash` (package `bash3`) and the GNU coreutils (`coreutils-gnu`): it puts `/usr/bin/gnu` first in `PATH`, because the BusyBox `mktemp` refuses a call without a template and BusyBox lacks `sha256sum`. Found by a user on a phone where both were missing.
