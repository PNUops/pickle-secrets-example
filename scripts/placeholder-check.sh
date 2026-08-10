#!/usr/bin/env bash
# Checks that this copy still holds no values.
#
# The README makes two promises about this tree: every credential in it is a
# placeholder, and every address or host name is an example. Both promises fail
# the same way. Not by a value appearing out of nowhere, but by one arriving
# from the original while a change is mirrored across — after which the two
# trees agree, so no comparison against the original can report anything, and
# the table goes on claiming a substitution that no longer happened.
#
# So the rules are checked from this side alone, and stated as shapes. A public
# tree cannot hold a list of the values it must not contain: writing them down
# in order to search for them publishes them. What it can hold is the set of
# shapes that are allowed to appear at all — the documentation address ranges,
# the example domains, and a value written as a placeholder rather than a
# value. Anything else is something real that arrived with a change.
set -euo pipefail

PLACEHOLDER_FAIL=0
pfail() { echo "placeholder: $1" >&2; PLACEHOLDER_FAIL=1; }

# Files to scan: everything tracked except two, both of which are made of the
# samples these rules exist to reject.
#
# This script's own selftest needs a synthetic value of each forbidden shape,
# and scanning itself would bury a real finding among its own probes.
#
# hygiene.sh is the shared publication scanner, byte-identical across every
# repository that carries it, so its samples cannot be rewritten to suit this
# tree alone. They are synthetic already — a made-up key fingerprint and a
# made-up host address, present so the scanner can prove it still refuses that
# shape — which is the property that matters here: they have the shape of a
# secret and none of the content of one. Excluding the file is what keeps the
# copy byte-identical, and the exclusion is narrow enough to name.
placeholder_files() {
  git ls-files -z \
    | grep -zvE '^scripts/(placeholder-check|hygiene)\.sh$'
}

# addr_allowed ADDRESS → 0 when the address may appear in this tree.
addr_allowed() {
  case "$1" in
    # RFC 5737 documentation ranges — what a substituted public address becomes.
    192.0.2.* | 198.51.100.* | 203.0.113.*) return 0 ;;
    # RFC 2544 benchmarking space stands in for the internal bridges. Ordinary
    # private addressing does NOT pass: allowing it wholesale would make a
    # substituted address and a real internal one indistinguishable to the one
    # rule meant to tell them apart.
    198.18.* | 198.19.*) return 0 ;;
    # Loopback, unspecified, broadcast.
    127.* | 0.0.0.0 | 255.255.255.*) return 0 ;;
  esac
  return 1
}

# host_allowed NAME → 0 when a domain name may appear in this tree. The reserved
# example and test names cover every substituted host; github.com and its raw
# file host are the project's own links, which are public by definition.
host_allowed() {
  local h
  h=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$h" in
    example.com | example.net | example.org | *.example.com | *.example.net | *.example.org) return 0 ;;
    example.ac.kr | *.example.ac.kr) return 0 ;;
    *.example | *.invalid | *.test | *.localhost) return 0 ;;
    github.com | *.github.com | githubusercontent.com | *.githubusercontent.com) return 0 ;;
  esac
  return 1
}

# A run of at least twenty characters with no separator inside it. Every
# credential this vault holds is longer than that once generated — a base64
# 24-byte password is 32 characters, a hex 32-byte token is 64, an SSH public key
# body is 68 — while ordinary prose, paths and identifiers break up on a dot,
# dash, slash or underscore long before they get there. The longest run in the
# tree as written is fifteen characters, so the threshold has room above the
# text and still leaves no generated secret below it.
#
# The slash is a separator here rather than part of the alphabet, which does cost
# something: a base64 value that happens to contain one is measured in pieces.
# The alternative costs more. A URL path is the one place ordinary text runs long
# without a break, and reading `com/PNUops/pickle-secrets-example` as a value
# would put the rule's output where nobody would keep reading it.
PLACEHOLDER_VALUE_RUN='[A-Za-z0-9+=]{20,}'

# A private key needs no length rule: its header says what it is.
PLACEHOLDER_PEM='-----BEGIN [A-Z ]*PRIVATE KEY-----'

# Domain names, recognised by a final label that is actually a top-level domain.
# Without that last condition the pattern reads api.env and origin.key as hosts,
# and the rule would spend its output on file names.
PLACEHOLDER_HOST_TLD='(com|net|org|edu|gov|int|mil|io|dev|app|ai|cloud|info|biz|me|co|kr|jp|cn|tw|uk|us|de|fr|eu|ru|in)'
PLACEHOLDER_HOST='\b([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+'"$PLACEHOLDER_HOST_TLD"'\b'

# placeholder_scan GREP-FLAGS PATTERN — grep every file in $files (set by the
# caller) and print the raw hits. Returns 0 when the scan ran, 2 when it broke.
#
# The distinction matters because this is a gate: a scan that never read the
# tree produces no hits, which is indistinguishable from a clean tree by exit
# status alone. grep exits 1 on "no match" and 2 on an error, but xargs
# collapses everything in 1..125 into 123, so the status cannot tell the two
# apart. grep's stderr can — silent on a clean scan, loud on an unreadable file,
# a broken symlink or a bad pattern — so that is what decides here.
#
# The pattern goes after -e because the private-key rule begins with a dash, and
# a grep that reads its pattern as options scans nothing and says so only on
# stderr. Without the -e that rule passed every tree it was ever given, and the
# selftest above is what noticed.
placeholder_scan() {
  local flags="$1" pattern="$2" err out
  err="$(mktemp)" || return 2
  out=$(printf '%s\0' "${files[@]}" | xargs -0 grep "$flags" -E -e "$pattern" 2>"$err" || true)
  if [ -s "$err" ]; then
    echo "placeholder: scan did not complete (rule /$pattern/):" >&2
    cat "$err" >&2
    rm -f "$err"
    return 2
  fi
  rm -f "$err"
  printf '%s' "$out"
}

placeholder_check() {
  PLACEHOLDER_FAIL=0
  local line file item raw
  local -a files

  # Fail closed: an empty file list means the scan did not run (not a git
  # worktree, git missing), which must never read as "clean".
  mapfile -d '' -t files < <(placeholder_files) || true
  if [ "${#files[@]}" -eq 0 ]; then
    echo "placeholder: no files to scan — is this a git worktree?" >&2
    return 1
  fi

  # 1. No address that belongs to anybody.
  raw=$(placeholder_scan -HoI '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b') || PLACEHOLDER_FAIL=1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    file=${line%%:*}
    item=${line#*:}
    addr_allowed "$item" && continue
    pfail "$file carries $item, which is neither a documentation range nor benchmarking space"
  done < <(printf '%s\n' "$raw" | sort -u)

  # 2. No host name that resolves to a real place.
  raw=$(placeholder_scan -HoI "$PLACEHOLDER_HOST") || PLACEHOLDER_FAIL=1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    file=${line%%:*}
    item=${line#*:}
    host_allowed "$item" && continue
    pfail "$file names the host $item, which is not one of the reserved example names"
  done < <(printf '%s\n' "$raw" | sort -u)

  # 3. No value. A placeholder is written as a description of what belongs
  # there; anything with the length and alphabet of generated material is the
  # material itself.
  raw=$(placeholder_scan -HnoI "$PLACEHOLDER_VALUE_RUN") || PLACEHOLDER_FAIL=1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    pfail "an opaque value of credential length appears here (write a placeholder instead): $line"
  done < <(printf '%s\n' "$raw")

  raw=$(placeholder_scan -HnoI "$PLACEHOLDER_PEM") || PLACEHOLDER_FAIL=1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    pfail "a private key block appears here: $line"
  done < <(printf '%s\n' "$raw")

  [ "$PLACEHOLDER_FAIL" -eq 0 ] || return 1
  echo "placeholder OK"
}

# Proves the gate still detects, end to end: a throwaway git repo, one known
# violation at a time, each asserted to fail. It exercises the file listing, the
# greps and the allowances together, not just the predicates — a check that has
# only ever been seen to pass is indistinguishable from one that does nothing.
# Every sample is synthetic. Writing down a value this tree must not contain in
# order to search for it would publish the value.
# shellcheck disable=SC2030,SC2031  # the checks run in subshells by design; the
# variables they read are assigned here and never written back.
placeholder_selftest() {
  local tmp rc=0 self line
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/placeholder-check.sh"
  tmp="$(mktemp -d)" || return 1
  mkdir -p "$tmp/scripts"
  cp "$self" "$tmp/scripts/placeholder-check.sh"
  git -C "$tmp" init -q
  git -C "$tmp" config user.email placeholder@example.invalid
  git -C "$tmp" config user.name placeholder

  while IFS= read -r line; do
    printf '%s\n' "$line" > "$tmp/sample.txt"
    git -C "$tmp" add -A >/dev/null 2>&1
    if ( cd "$tmp" && . scripts/placeholder-check.sh && placeholder_check ) >/dev/null 2>&1; then
      echo "placeholder selftest: no longer detected: $line" >&2
      rc=1
    fi
  done <<'SAMPLES'
PICKLE_PROXY_AGENT_URL=http://11.22.33.44:9443
the bridge answers on 172.31.99.99
reachable at 10.99.99.99 from the host
PICKLE_SSH_HOST=ssh.somewhere-real.kr
the console lives at portal.notanexample.com
PICKLE_DB_PASSWORD=Zk3QvLmRtYwXbNdPfHjSgTc
PICKLE_JWT_SECRET=8f2a41c7bd93e05a6417cf82db309e75
-----BEGIN OPENSSH PRIVATE KEY-----
-----BEGIN RSA PRIVATE KEY-----
SAMPLES

  # A scan that cannot read the tree must fail rather than report a clean run.
  # A dangling symlink is the cheapest way to break grep for real, and it breaks
  # it for root too, unlike a permission bit.
  ln -s missing-target "$tmp/dangling"
  printf 'clean line\n' > "$tmp/sample.txt"
  git -C "$tmp" add -A >/dev/null 2>&1
  if ( cd "$tmp" && . scripts/placeholder-check.sh && placeholder_check ) >/dev/null 2>&1; then
    echo "placeholder selftest: an unreadable tree still reported clean" >&2
    rc=1
  fi
  git -C "$tmp" rm -q --cached dangling >/dev/null 2>&1
  rm -f "$tmp/dangling"

  # The opposite direction: what the tree legitimately contains must pass, or
  # the gate becomes something people work around.
  cat > "$tmp/sample.txt" <<'CLEAN'
PICKLE_PROXY_AGENT_URL=http://198.18.1.10:9443
PICKLE_DB_URL=jdbc:postgresql://localhost:5432/pickle
PICKLE_DB_PASSWORD=<generate: openssl rand -base64 24>
PICKLE_SSH_HOST=ssh.example.ac.kr
PICKLE_SMTP_USERNAME=no-reply@example.ac.kr
PICKLE_VERIFICATION_BASE_URL=https://console.example.com/verify-email
PICKLE_SSH_PLATFORM_PUBLIC_KEY=ssh-ed25519 AAAA<gateway upstream public key>
see https://github.com/PNUops/pickle-secrets-example for the layout
chmod 600 origin-ca/origin.key sshgw-upstream_ed25519_key
the blob begins with the GITCRYPT magic header
listening on 127.0.0.1 and 0.0.0.0
CLEAN
  git -C "$tmp" add -A >/dev/null 2>&1
  if ! ( cd "$tmp" && . scripts/placeholder-check.sh && placeholder_check ) >/dev/null 2>&1; then
    echo "placeholder selftest: false positive on legitimate content" >&2
    ( cd "$tmp" && . scripts/placeholder-check.sh && placeholder_check ) >&2 || true
    rc=1
  fi

  rm -rf "$tmp"
  [ "$rc" -eq 0 ] && echo "placeholder selftest OK"
  return "$rc"
}
