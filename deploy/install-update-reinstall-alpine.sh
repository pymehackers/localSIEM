#!/bin/bash

set -euo pipefail

# localSIEM installer, updater and reinstaller for Alpine Linux 3.24 or newer
# (OpenRC). It installs the core of localSIEM only, never a module: the
# modules are installed from the web only (Modules › Installable), and
# then, as root, manage.py setup-modules lets localsiem read their logs.
# Straight from GitHub (Alpine has neither bash nor curl by default: apk add
# bash curl first):
#   curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install
#   curl -fsSL ...same URL... | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
#   curl -fsSL ...same URL... | bash -s -- --update
# It always needs one action, and without one it stops: --install (a server
# without localSIEM), --update (an installed localSIEM: it keeps everything),
# --reinstall (it deletes the installed localSIEM with all its data and
# installs it again from zero) or --uninstall. Run from a complete copy of
# the project it installs that copy; piped, run alone, or with --ref or
# --source-url, it downloads the archive of the repository. It installs what
# it needs (python3, openssl, acl...) when it is missing. --update can be run
# again and again; the options given once are remembered in
# /opt/localsiem/config/install.env.
#
# What it prints: a header, numbered steps ([3/12] Getting localSIEM) with
# one line per result (✓ done, ! warning, ✗ failure, · information, details
# dimmed below) and a summary with the next steps. Colours only on a
# terminal, never with NO_COLOR, TERM=dumb or LOCALSIEM_COLOR=never. The log
# (/root/webapp-install.log) receives the same lines without colour codes,
# the times in the storage format, and the whole output of the commands the
# screen sums up in one line (apk, pip, tar, rc-service...); when one of
# them fails, the screen shows its last lines.

cRepository='https://github.com/PYMEHackers/localSIEM'
cRepositoryApi='https://api.github.com/repos/PYMEHackers/localSIEM'
# Sent with every download: neither GitHub nor a proxy on the way may answer
# with a copy kept from before.
aNoCache=(-H 'Cache-Control: no-cache' -H 'Pragma: no-cache')
cDestination='/opt/localsiem/webapp'
cVenv='/opt/localsiem/venv'
cInstallLog='/root/webapp-install.log'
cCredentials='/root/webapp-credentials.txt'
aPackages=(python3 openssl ca-certificates acl logrotate sed curl tar gzip)
# The output, once the log is open (fStartLog), is one ordered stream that
# fSplitOutput sends to the screen and to the log. A line that starts with
# cLogOnly goes to the log only; one that starts with cScreenOnly, to the
# screen only.
cLogOnly=$'\x1e'
cScreenOnly=$'\x1d'
# Colour codes (and any other CSI sequence), never written to the log.
cColorRegex=$'\e\\[[0-9;?]*[A-Za-z]'
vSourcePath=''
vTemporaryPath=''
vDownloadPath=''
vRef=''
vSourceUrl=''
# install, update, reinstall or uninstall: always exactly one.
vAction=''
vYes=''
# Set by fConfirmRemoval when the administrator agrees to delete localSIEM.
vConfirmed=''
# Set by fRemoveInstallation when it finds something of localSIEM to delete.
vRemovedAny=''
# Set by fInitStyle; empty without colours.
vBold=''
vDim=''
vRed=''
vGreen=''
vYellow=''
vAccent=''
vReset=''
# always or never: LOCALSIEM_COLOR of the Python tools this script runs.
vColorMode='never'
# The numbered steps of the action (fStep).
vStep=0
vStepTotal=0
vStepTitle=''
# Set by fStartLog.
vLogStarted=''
vSplitterPid=''
# The output of the last command run by fRunToLog.
vOutputFile=''

fCleanup() {
  if [ -n "$vTemporaryPath" ]; then
    case "$vTemporaryPath" in
      "$vSourcePath"/_/temp/install.*)
        rm -rf -- "$vTemporaryPath"
        ;;
    esac
  fi
  if [ -n "$vDownloadPath" ]; then
    case "$vDownloadPath" in
      /tmp/localsiem-install.*)
        rm -rf -- "$vDownloadPath"
        ;;
    esac
  fi
  if [ -n "$vOutputFile" ]; then
    case "$vOutputFile" in
      /tmp/localsiem-output.*)
        rm -f -- "$vOutputFile"
        ;;
    esac
  fi
  if [ -n "$vSplitterPid" ]; then
    fStopLog
  fi
}

trap fCleanup EXIT

fGetTimestamp() {
  # Now, in UTC, in the storage format: 2026-10-29@13-59-59.723.
  local vNow
  vNow="${EPOCHREALTIME/,/.}"
  TZ=UTC0 printf '%(%Y-%m-%d@%H-%M-%S)T.%s\n' "${vNow%.*}" "${vNow:(-6):3}"
}

fFormatDisplay() {
  # The display format (2026/10/29@13:59:59.723) of a time in the storage
  # format (2026-10-29@13-59-59.723).
  local pStamp="$1"
  local vDate="${pStamp%%@*}"
  local vTime="${pStamp#*@}"
  printf '%s@%s\n' "${vDate//-//}" "${vTime//-/:}"
}

fInitStyle() {
  # Colours only when stdout and stderr are a terminal, and never with
  # TERM=dumb nor NO_COLOR; LOCALSIEM_COLOR=always or never decides first.
  # Decided once, before the output goes through the log; the Python tools
  # this script runs follow it (LOCALSIEM_COLOR), since what they print goes
  # to the pipe of the log, not to the terminal.
  local vColor=''
  case "${LOCALSIEM_COLOR:-}" in
    always)
      vColor='yes'
      ;;
    never)
      ;;
    *)
      if [ -t 1 ] && [ -t 2 ] && [ "${TERM:-}" != 'dumb' ] && [ -z "${NO_COLOR:-}" ]; then
        vColor='yes'
      fi
      ;;
  esac
  if [ -n "$vColor" ]; then
    vBold=$'\e[1m'
    vDim=$'\e[2m'
    vRed=$'\e[31m'
    vGreen=$'\e[32m'
    vYellow=$'\e[33m'
    vAccent=$'\e[36m'
    vReset=$'\e[0m'
    vColorMode='always'
  fi
  export LOCALSIEM_COLOR="$vColorMode"
}

fToScreen() {
  # A line for the screen only.
  if [ -n "$vLogStarted" ]; then
    printf '%s%s\n' "$cScreenOnly" "$1"
  else
    printf '%s\n' "$1"
  fi
}

fToLog() {
  # A line for the log only (nothing before the log is open).
  if [ -n "$vLogStarted" ]; then
    printf '%s%s\n' "$cLogOnly" "$1"
  fi
}

fStep() {
  # The next numbered step: [3/12] Getting localSIEM.
  vStep=$((vStep + 1))
  vStepTitle="$1"
  printf '\n%s %s\n' "${vAccent}${vBold}[$vStep/$vStepTotal]${vReset}" "${vBold}$1${vReset}"
}

fOk() {
  printf '  %s %s\n' "${vGreen}✓${vReset}" "$1"
}

fWarn() {
  printf '  %s %s\n' "${vYellow}${vBold}!${vReset}" "$1"
}

fFail() {
  printf '  %s %s\n' "${vRed}✗${vReset}" "$1"
}

fInfo() {
  printf '  %s %s\n' "${vDim}·${vReset}" "$1"
}

fDetail() {
  # A secondary line, dimmed, below the result it explains.
  printf '    %s\n' "${vDim}$1${vReset}"
}

fDetailFile() {
  # Each line of a file, as a detail.
  local pFile="$1"
  local vLine
  while IFS= read -r vLine || [ -n "$vLine" ]; do
    fDetail "$vLine"
  done < "$pFile"
}

fError() {
  # An error before the log is open, on stderr: the first argument with the
  # mark, the others below it.
  local vLine
  printf '%s %s\n' "${vRed}✗${vReset}" "$1" >&2
  shift
  for vLine in "$@"; do
    printf '  %s\n' "$vLine" >&2
  done
}

fIndent() {
  # What a localSIEM tool or the system prints for the administrator, under
  # its step: indented (pIndent, two spaces by default) and with an optional
  # style (pStyle).
  local pIndent="${1:-  }"
  local pStyle="${2:-}"
  local vLine
  while IFS= read -r vLine || [ -n "$vLine" ]; do
    if [ -n "$pStyle" ]; then
      printf '%s%s\n' "$pIndent" "${pStyle}${vLine}${vReset}"
    else
      printf '%s%s\n' "$pIndent" "$vLine"
    fi
  done
}

fRule() {
  printf '%s\n' "${vDim}────────────────────────────────────────────────────────────${vReset}"
}

fField() {
  # A row of the header or of the summary: label and value.
  local vLabel
  printf -v vLabel '%-13s' "$1"
  printf '  %s%s\n' "${vDim}${vLabel}${vReset}" "$2"
}

fShowTimestamp() {
  # A row with the time: on the screen in the display format, in the log in
  # the storage format (both UTC).
  local pLabel="$1"
  local vLabel
  local vStamp
  vStamp="$(fGetTimestamp)" || return 1
  printf -v vLabel '%-13s' "$pLabel"
  fToScreen "  ${vDim}${vLabel}${vReset}$(fFormatDisplay "$vStamp") UTC"
  fToLog "  ${vLabel}${vStamp}"
}

fShowHeader() {
  # The first lines of a run: what it does, on which server and system, when,
  # and where its log is.
  local pTitle="$1"
  local vSystem
  vSystem="$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null || true)"
  vSystem="${vSystem#\"}"
  vSystem="${vSystem%\"}"
  if [ -z "$vSystem" ]; then
    vSystem="$(uname -s)"
  fi
  printf '\n%s\n' "${vBold}localSIEM${vReset} ${vDim}·${vReset} ${vBold}$pTitle${vReset}"
  fRule
  fField 'Server' "$(uname -n)"
  fField 'System' "$vSystem"
  fShowTimestamp 'Started' || return 1
  fField 'Log' "$cInstallLog"
}

fStartLog() {
  # From here on, stdout and stderr go through fSplitOutput: the screen and
  # the log receive one ordered stream.
  exec > >(fSplitOutput) 2>&1
  vSplitterPid=$!
  vLogStarted='yes'
}

fSplitOutput() {
  # Each line of the stream, in order, to the screen and, without colour
  # codes, to the log; the lines marked cLogOnly or cScreenOnly only to one
  # of them. It ignores Ctrl+C and a closed terminal, so the log receives
  # everything until the installer ends. Plain bash, without sed nor tee: the
  # same on Debian and on the BusyBox of Alpine.
  local vLine
  trap '' INT HUP
  exec 4>>"$cInstallLog"
  while IFS= read -r vLine || [ -n "$vLine" ]; do
    case "$vLine" in
      "$cLogOnly"*)
        fWriteLog "${vLine#"$cLogOnly"}"
        ;;
      "$cScreenOnly"*)
        printf '%s\n' "${vLine#"$cScreenOnly"}" || true
        ;;
      *)
        printf '%s\n' "$vLine" || true
        fWriteLog "$vLine"
        ;;
    esac
  done
}

fWriteLog() {
  local vText="$1"
  while [[ "$vText" =~ $cColorRegex ]]; do
    vText="${vText/"${BASH_REMATCH[0]}"/}"
  done
  printf '%s\n' "$vText" >&4 || true
}

fStopLog() {
  # The end of the stream: fSplitOutput writes its last lines before the
  # shell prompt comes back (it waits 5 seconds at most).
  local vWaited=0
  exec >/dev/null 2>&1
  while kill -0 "$vSplitterPid" 2>/dev/null && [ "$vWaited" -lt 50 ]; do
    sleep 0.1 || true
    vWaited=$((vWaited + 1))
  done
  vSplitterPid=''
}

fNewOutputFile() {
  if [ -n "$vOutputFile" ]; then
    rm -f -- "$vOutputFile"
  fi
  vOutputFile="$(mktemp /tmp/localsiem-output.XXXXXX)"
}

fRunToLog() {
  # Runs a command (stdin /dev/null) and sends its whole output (stdout and
  # stderr) to the log only, below a line with the command; the screen shows
  # nothing. Returns its exit status. Its output stays in vOutputFile, for
  # fShowOutputTail, until the next command.
  local vLine
  local vStatus=0
  fNewOutputFile || return 1
  "$@" > "$vOutputFile" 2>&1 < /dev/null || vStatus=$?
  fToLog "    \$ $*"
  while IFS= read -r vLine || [ -n "$vLine" ]; do
    fToLog "    | $vLine"
  done < "$vOutputFile"
  return "$vStatus"
}

fRun() {
  # A command whose output only matters to the log (fRunToLog): the screen
  # shows one line with its result, pDone (nothing when it is empty), or,
  # when it fails, pFailed and its last lines.
  local pDone="$1"
  local pFailed="$2"
  local vStatus=0
  shift 2
  fRunToLog "$@" || vStatus=$?
  if [ "$vStatus" -eq 0 ]; then
    if [ -n "$pDone" ]; then
      fOk "$pDone"
    fi
    return 0
  fi
  fFail "$pFailed (exit status $vStatus)."
  fShowOutputTail
  return "$vStatus"
}

fShowOutputTail() {
  # The last lines of the output of the command that failed, on the screen
  # only (the log already has all of it), and where to read the rest.
  local vLine
  if [ -s "$vOutputFile" ]; then
    fToScreen "    ${vDim}Last lines of its output:${vReset}"
    tail -n 20 "$vOutputFile" | while IFS= read -r vLine || [ -n "$vLine" ]; do
      fToScreen "    ${vDim}|${vReset} $vLine"
    done
  fi
  fToScreen "    ${vDim}Whole output: $cInstallLog${vReset}"
}

fShowFailure() {
  # The end of a run that failed, on stderr.
  local vWhat='installation, update, reinstallation or uninstallation'
  case "$vAction" in
    install)
      vWhat='installation'
      ;;
    update)
      vWhat='update'
      ;;
    reinstall)
      vWhat='reinstallation'
      ;;
    uninstall)
      vWhat='uninstallation'
      ;;
  esac
  if [ -z "$vLogStarted" ]; then
    printf '%s %s\n' "${vRed}✗${vReset}" "${vBold}localSIEM $vWhat failed.${vReset}" >&2
    return 0
  fi
  printf '\n%s %s\n' "${vRed}✗${vReset}" "${vBold}localSIEM $vWhat failed.${vReset} Read $cInstallLog." >&2
  if [ "$vStep" -gt 0 ]; then
    fDetail "It stopped at step $vStep/$vStepTotal: $vStepTitle." >&2
  fi
  fShowTimestamp 'Stopped' >&2 || true
}

fShowHelp() {
  printf '%s\n' \
    "${vBold}Usage${vReset}" \
    '  bash deploy/install-update-reinstall-alpine.sh ACTION [options]' \
    "  curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- ACTION [options]" \
    '' \
    "${vBold}ACTION${vReset}, always exactly one:" \
    '  --install                install localSIEM on a server that does not have it' \
    '  --update                 update the installed localSIEM: it keeps its data, accounts, settings, modules' \
    '                           and the options given before' \
    '  --reinstall [--yes]      delete the installed localSIEM with all its data and install it again from zero,' \
    '                           with new passwords (asks first; --yes does not ask). The options given before are' \
    '                           not kept: give them again' \
    '  --uninstall [--yes]      delete localSIEM and all its data from this server (asks first; --yes does not ask)' \
    '' \
    "${vBold}Options of --install, --update and --reinstall${vReset}" \
    '  (the web always listens with HTTPS on port 10443; self-signed certificate if there is no other)' \
    '  --allow-from LIST        IPs and CIDR allowed to reach the web, separated by commas' \
    '  --soc-url URL            SOC (default https://soc.pymehackers.com)' \
    '  --soc-token TOKEN        ingestion token of this client in the SOC (optional: without a SOC localSIEM works on its own)' \
    '  --soc-ca-file PATH       CA of a SOC with a private certificate (test servers)' \
    '  --domain NAME            name of this server (certificate and SIEM address)' \
    '  --certificate PATH --private-key PATH   certificate to use' \
    '  --retention-days N       days of events (default 90)' \
    '  --max-disk SIZE          maximum database size (2G, 500M; default auto: lesser of 15 % and 10 GB)' \
    '  --enable-mfa             two-step verification mandatory for every account; --disable-mfa turns it off' \
    '                           (default: off on a new installation; an update keeps the setting of the web)' \
    '  --rotate-credentials     new JWT secret' \
    '  --ref REF                branch or tag of localSIEM to download (default main)' \
    '  --source-url URL         archive (.tar.gz) of localSIEM to install instead of GitHub' \
    '  --modules-repository URL repository (or .tar.gz archive) the web installs modules from' \
    '                           (default https://github.com/PYMEHackers/localSIEM-modules)' \
    '  --modules-ref REF        its branch or tag (default main)' \
    '' \
    'Modules are not installed here: install them from the web (Modules › Installable).' \
    'Colours only on a terminal; NO_COLOR or LOCALSIEM_COLOR=never turns them off.'
}

fAsLocalsiem() {
  # Alpine has no runuser: su with a shell, since localsiem has none.
  su -s /bin/sh localsiem -c "$*"
}

fIsCompleteCopy() {
  [ -f "$1/deploy/configure.py" ] && [ -f "$1/backend/server.py" ] && [ -f "$1/backend/collector.py" ] && [ -f "$1/frontend/index.html" ] && [ -f "$1/backend/requirements.txt" ]
}

fIsInstalled() {
  # Any trace of localSIEM on this server, also of an installation that
  # failed halfway: its folder, its services or its user (with the home of
  # localSIEM). --install needs none; --update and --reinstall need one.
  local vAccountHome
  if [ -e /opt/localsiem ] || [ -L /opt/localsiem ] || [ -f /etc/init.d/localsiem ] || [ -f /etc/init.d/localsiem-web ]; then
    return 0
  fi
  if getent passwd localsiem >/dev/null; then
    vAccountHome="$(getent passwd localsiem | cut -d: -f6)"
    if [ "$vAccountHome" = '/opt/localsiem' ] || [ "$vAccountHome" = '/opt/localsiem/' ]; then
      return 0
    fi
  fi
  return 1
}

fEnsurePackages() {
  # Only what is missing is installed; apk update runs only then. GNU tar:
  # the one of BusyBox would unpack the pax header of GitHub as a file. Their
  # output goes to the log only.
  local vPackage
  local aMissing=()
  for vPackage in "${aPackages[@]}"; do
    if ! apk info -e "$vPackage" >/dev/null 2>&1; then
      aMissing+=("$vPackage")
    fi
  done
  if [ "${#aMissing[@]}" -eq 0 ]; then
    fOk "Dependencies already installed: ${aPackages[*]}"
    return 0
  fi
  fInfo "Missing dependencies: ${aMissing[*]}"
  fRun 'Package indexes updated (apk update)' 'apk update failed' apk update || return 1
  fRun "Dependencies installed: ${aMissing[*]}" 'apk add failed' apk add "${aMissing[@]}" || return 1
}

fResolveRef() {
  # GitHub keeps what it serves of a branch in its cache for a few minutes
  # after a push, so a download right after it could bring the version
  # before. Its API (which is not cached) is asked for the commit of the
  # branch or tag, and the archive of that commit, which never changes, is
  # the one downloaded. Prints the commit; fails when the API does not
  # answer (without a token it allows 60 requests per hour from each IP
  # address).
  local pRef="$1"
  local vCommit
  if [[ "$pRef" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s\n' "$pRef"
    return 0
  fi
  vCommit="$(curl -fsS --retry 3 --connect-timeout 20 "${aNoCache[@]}" -H 'Accept: application/vnd.github.sha' "$cRepositoryApi/commits/$pRef" < /dev/null)" || return 1
  if [[ ! "$vCommit" =~ ^[0-9a-f]{40}$ ]]; then
    return 1
  fi
  printf '%s\n' "$vCommit"
}

fGetSource() {
  # The complete copy the installer runs from; piped (curl ... | bash, where
  # BASH_SOURCE is "main"), run alone, or with --ref or --source-url: the
  # archive of the repository, downloaded and unpacked in a temporary folder.
  local vScript="${BASH_SOURCE[0]:-}"
  local vCandidate
  local vUrl
  local vCommit
  local vEntry
  local aTop=()
  if [ -z "$vRef" ] && [ -z "$vSourceUrl" ] && [ -n "$vScript" ] && [ "$vScript" != 'main' ] && [ -f "$vScript" ]; then
    vCandidate="$(cd -- "$(dirname -- "$vScript")/.." && pwd -P)" || return 1
    if [ "$vAction" = 'reinstall' ] && [[ "$vCandidate/" == /opt/localsiem/* ]]; then
      # The installed copy goes with the rest of /opt/localsiem.
      fInfo "--reinstall deletes $vCandidate before installing, so it does not install from there: it downloads localSIEM."
    elif fIsCompleteCopy "$vCandidate"; then
      vSourcePath="$vCandidate"
      fOk "Installing localSIEM from $vSourcePath"
      return 0
    fi
  fi
  # What curl says when the GitHub API does not answer.
  fNewOutputFile || return 1
  if [ -n "$vSourceUrl" ]; then
    vUrl="$vSourceUrl"
  elif vCommit="$(fResolveRef "${vRef:-main}" 2>"$vOutputFile")"; then
    fOk "${vRef:-main} is the commit $vCommit of $cRepository"
    vUrl="$cRepository/archive/$vCommit.tar.gz"
  else
    fWarn "The GitHub API did not say which commit ${vRef:-main} is: downloading the archive of ${vRef:-main}, which GitHub may still serve from its cache for a few minutes after a change."
    fDetailFile "$vOutputFile"
    vUrl="$cRepository/archive/${vRef:-main}.tar.gz"
  fi
  vDownloadPath="$(mktemp -d /tmp/localsiem-install.XXXXXX)" || return 1
  fRun "Downloaded $vUrl" "Could not download $vUrl" curl -fsSL --retry 3 --connect-timeout 20 "${aNoCache[@]}" -o "$vDownloadPath/localSIEM.tar.gz" "$vUrl" || return 1
  mkdir "$vDownloadPath/source" || return 1
  fRun 'Archive unpacked' 'Could not unpack the archive' tar -C "$vDownloadPath/source" --no-same-owner -xzf "$vDownloadPath/localSIEM.tar.gz" || return 1
  # GitHub puts everything in one folder: localSIEM-<commit, branch or tag>/.
  for vEntry in "$vDownloadPath/source"/*; do
    if [ -e "$vEntry" ]; then
      aTop+=("$vEntry")
    fi
  done
  if [ "${#aTop[@]}" -eq 1 ] && [ -d "${aTop[0]}" ]; then
    vSourcePath="${aTop[0]}"
  else
    vSourcePath="$vDownloadPath/source"
  fi
  if ! fIsCompleteCopy "$vSourcePath"; then
    fFail "$vUrl is not a complete copy of localSIEM."
    return 1
  fi
}

fInstallPythonPackages() {
  # The dependencies of localSIEM in its virtual environment (umask 022, in
  # a subshell: the packages readable by localsiem).
  (umask 022 && TMPDIR="$vTemporaryPath" "$cVenv/bin/python" -m pip install --upgrade --no-cache-dir --disable-pip-version-check -r "$cDestination/backend/requirements.txt" < /dev/null)
}

fGrantLogAccess() {
  # localsiem reads the logs of the folders its installed modules declare
  # (read_paths of each module.json; /var/log/apache2 for the apache2
  # module), so the modules installed before an update keep their access.
  # Alpine creates the Apache logs root:wheel in a folder only wheel can
  # enter: localsiem reads them through ACLs, also the files of the next
  # rotations (default ACL). manage.py setup-modules does it, the same
  # command the web shows after installing a module; --no-restart: the
  # services are restarted below. Without modules there is nothing to do.
  PYTHONDONTWRITEBYTECODE=1 "$cVenv/bin/python" "$cDestination/backend/manage.py" setup-modules --no-restart < /dev/null 2>&1 | fIndent || return 1
}

fRemoveReadAccess() {
  # The read access manage.py setup-modules gave localsiem (ACLs and default
  # ACLs): the folders of the installed modules and /var/log/apache2, where
  # the apache2 module reads (a module uninstalled from the web keeps the
  # access it was given). Before the group is deleted: setfacl needs its
  # name.
  local vFolder
  local aFolders=(/var/log/apache2)
  if ! getent group localsiem >/dev/null || ! command -v setfacl >/dev/null; then
    return 0
  fi
  if [ -x "$cVenv/bin/python" ] && [ -f "$cDestination/backend/manage.py" ]; then
    while IFS= read -r vFolder; do
      if [ -n "$vFolder" ] && [ "$vFolder" != '/var/log/apache2' ]; then
        aFolders+=("$vFolder")
      fi
    done < <(PYTHONDONTWRITEBYTECODE=1 "$cVenv/bin/python" "$cDestination/backend/manage.py" read-paths < /dev/null 2>/dev/null || true)
  fi
  for vFolder in "${aFolders[@]}"; do
    if [ ! -d "$vFolder" ]; then
      continue
    fi
    vRemovedAny='yes'
    if setfacl -R -x g:localsiem,d:g:localsiem -- "$vFolder" 2>/dev/null; then
      fOk "Read access of localsiem removed from $vFolder"
    else
      fWarn "The read access of localsiem could not be removed from all of $vFolder (getfacl -R $vFolder shows it)."
    fi
  done
}

fRemoveApacheSetup() {
  # What --configure-apache of the apache2 module (up to its version 1.2.0;
  # the module no longer has it) added to Apache: its own
  # file (which says: remove this file to undo it; it also loaded
  # mod_unique_id and mod_logio). Apache is reloaded, never restarted, and
  # only if its configtest passes. localSIEM only reads the logs of Apache,
  # never changes nor deletes them: the localsiem_access.log that file made
  # Apache write stays, like modsec_audit.log.
  local vLog
  if [ -f /etc/apache2/conf.d/localsiem.conf ] || [ -L /etc/apache2/conf.d/localsiem.conf ]; then
    rm -f -- /etc/apache2/conf.d/localsiem.conf || return 1
    vRemovedAny='yes'
    fOk 'Apache configuration of localSIEM removed (/etc/apache2/conf.d/localsiem.conf)'
    if command -v httpd >/dev/null && rc-service --exists apache2 && rc-service apache2 status >/dev/null 2>&1; then
      if fRunToLog httpd -t; then
        if fRunToLog rc-service apache2 reload; then
          fOk 'Apache reloaded'
        else
          fWarn 'Apache could not be reloaded: rc-service apache2 reload.'
          fShowOutputTail
        fi
      else
        fWarn 'The Apache configtest fails, so Apache was not reloaded: httpd -t.'
        fShowOutputTail
      fi
    fi
  fi
  for vLog in /var/log/apache2/localsiem_access.log*; do
    if [ -f "$vLog" ]; then
      fInfo "$vLog stays: localSIEM never changes nor deletes a log of Apache (delete it by hand if you do not want it)."
    fi
  done
}

fRemoveCredentials() {
  # The blocks localSIEM appended to the credentials file (each one starts
  # with a line «localSIEM ...»). What other applications wrote there stays;
  # a file left empty is deleted.
  local vMessage
  if [ ! -f "$cCredentials" ] || [ -L "$cCredentials" ]; then
    return 0
  fi
  if ! command -v python3 >/dev/null; then
    fWarn "Without python3, $cCredentials was not cleaned: remove the localSIEM entries by hand."
    return 0
  fi
  vMessage="$(python3 -I -c '
import re
import sys
from pathlib import Path
vPath = Path(sys.argv[1])
lBlocks = [vBlock.strip("\n") for vBlock in re.split(r"\n[ \t]*\n", vPath.read_text(encoding="utf-8")) if vBlock.strip()]
lKept = [vBlock for vBlock in lBlocks if not vBlock.lstrip().startswith("localSIEM ")]
if lKept:
  with open(vPath, "r+", encoding="utf-8") as vHandle:
    vHandle.seek(0)
    vHandle.write("\n" + "\n\n".join(lKept) + "\n")
    vHandle.truncate()
  print(f"{vPath}: the localSIEM entries were removed; the entries of other applications stay.")
else:
  vPath.unlink()
  print(f"{vPath} removed.")
' "$cCredentials" < /dev/null)" || return 1
  vRemovedAny='yes'
  fOk "$vMessage"
}

fConfirmRemoval() {
  # --uninstall and --reinstall delete localSIEM with all its data: what goes
  # is shown and, without --yes, the administrator types yes on the terminal
  # (never on the standard input, which is this script with curl ... | bash).
  # Sets vConfirmed; cancelling is not an error. Before the log is open.
  local pAction="$1"
  local vAnswer=''
  local vQuestion='Type yes to delete it: '
  vConfirmed=''
  printf '\n%s %s\n' "${vYellow}${vBold}!${vReset}" "${vBold}This deletes localSIEM from this server, with all its data:${vReset}"
  printf '    %s %s\n' \
    "${vDim}·${vReset}" 'its services' \
    "${vDim}·${vReset}" '/opt/localsiem: code, settings, accounts, database with every event and alert, certificates, modules' \
    "${vDim}·${vReset}" 'the user localsiem' \
    "${vDim}·${vReset}" 'the read access to the logs it was given' \
    "${vDim}·${vReset}" 'the Apache configuration of --configure-apache' \
    "${vDim}·${vReset}" "the localSIEM entries of $cCredentials"
  printf '  %s\n' 'It cannot be undone.'
  if [ "$pAction" = 'reinstall' ]; then
    printf '  %s\n' \
      'Then it installs localSIEM again from zero, with new passwords. The options of the' \
      'current installation are not kept: give them with --reinstall (--allow-from, --soc-token...).'
    vQuestion='Type yes to delete it and install it again: '
  fi
  if [ -z "$vYes" ]; then
    printf '\n%s' "${vBold}${vQuestion}${vReset}"
    if ! read -r vAnswer 2>/dev/null < /dev/tty; then
      printf '\n' >&2
      fError "There is no terminal to ask on: run it again with --$pAction --yes."
      return 1
    fi
    if [ "$vAnswer" != 'yes' ]; then
      printf '%s %s\n' "${vDim}·${vReset}" 'Cancelled: nothing was deleted.'
      return 0
    fi
  fi
  vConfirmed='yes'
}

fRemoveInstallation() {
  # Everything of localSIEM on this server, with all its data (--uninstall,
  # and --reinstall before it installs again). Every step looks at what is
  # there first, so it can be run again. The packages the installer added
  # stay: other services of the server may use them.
  local vAccountHome
  local vFile
  local vLink
  local vPath
  local vService
  for vService in localsiem-web localsiem; do
    if [ -f "/etc/init.d/$vService" ]; then
      if rc-service "$vService" status >/dev/null 2>&1; then
        fRun '' "Could not stop $vService" rc-service "$vService" stop || return 1
      fi
      rc-update del "$vService" default >/dev/null 2>&1 || true
      for vLink in /etc/runlevels/*/"$vService"; do
        if [ -L "$vLink" ]; then
          rm -f -- "$vLink" || return 1
        fi
      done
      rm -f -- "/etc/init.d/$vService" || return 1
      vRemovedAny='yes'
      fOk "Service $vService stopped and removed"
    fi
  done
  # Nothing of localsiem may keep running: deluser refuses a user with
  # processes.
  if getent passwd localsiem >/dev/null && pgrep -u localsiem >/dev/null; then
    pkill -u localsiem || true
    sleep 2
    if pgrep -u localsiem >/dev/null; then
      pkill -9 -u localsiem || true
      sleep 1
    fi
    vRemovedAny='yes'
    fOk 'Processes of the user localsiem stopped'
  fi
  fRemoveReadAccess || return 1
  fRemoveApacheSetup || return 1
  for vFile in /etc/logrotate.d/localsiem /etc/letsencrypt/renewal-hooks/deploy/localsiem.sh /etc/letsencrypt/renewal-hooks/deploy/.localsiem.sh.tmp; do
    if [ -e "$vFile" ] || [ -L "$vFile" ]; then
      rm -f -- "$vFile" || return 1
      vRemovedAny='yes'
      fOk "$vFile removed"
    fi
  done
  if getent passwd localsiem >/dev/null; then
    vAccountHome="$(getent passwd localsiem | cut -d: -f6)" || return 1
    if [ "$vAccountHome" = '/opt/localsiem' ] || [ "$vAccountHome" = '/opt/localsiem/' ]; then
      fRun 'User localsiem removed' 'Could not remove the user localsiem' deluser localsiem || return 1
      vRemovedAny='yes'
    else
      fWarn "The user localsiem has the home $vAccountHome: it is not the one of localSIEM and it stays."
    fi
  fi
  if getent group localsiem >/dev/null && ! getent passwd localsiem >/dev/null; then
    fRun 'Group localsiem removed' 'Could not remove the group localsiem' delgroup localsiem || return 1
    vRemovedAny='yes'
  fi
  if [ -d /opt/localsiem ] && [ ! -L /opt/localsiem ]; then
    rm -rf -- /opt/localsiem || return 1
    vRemovedAny='yes'
    fOk '/opt/localsiem removed'
  fi
  # Copies left by earlier runs; the one this run downloaded (--reinstall)
  # stays until it is installed.
  for vPath in /tmp/localsiem-install.*; do
    if [ -d "$vPath" ] && [ "$vPath" != "$vDownloadPath" ]; then
      rm -rf -- "$vPath" || return 1
    fi
  done
  fRemoveCredentials || return 1
}

fUninstall() {
  # --uninstall: localSIEM leaves this server with all its data.
  fConfirmRemoval 'uninstall' || return 1
  if [ -z "$vConfirmed" ]; then
    return 0
  fi
  touch "$cInstallLog" || return 1
  chown root:root "$cInstallLog" || return 1
  chmod 600 "$cInstallLog" || return 1
  fStartLog
  vStepTotal=2
  fShowHeader 'Uninstallation' || return 1
  fStep 'Checking the system'
  if [ ! -f /etc/alpine-release ] || [ ! -d /run/openrc ]; then
    fFail 'Alpine Linux with OpenRC is required.'
    return 1
  fi
  fOk "Alpine Linux $(cat /etc/alpine-release) with OpenRC"
  fStep 'Deleting localSIEM with all its data'
  fRemoveInstallation || return 1
  if [ -z "$vRemovedAny" ]; then
    fInfo 'Nothing of localSIEM was found on this server.'
  fi
  printf '\n%s %s\n' "${vGreen}✓${vReset}" "${vBold}localSIEM uninstalled${vReset}"
  fRule
  fField 'Kept' "$cInstallLog (with this record)"
  fField '' 'the packages the installer added (other services may use them)'
  fShowTimestamp 'Finished' || return 1
  printf '\n%s\n' 'To install it again, run this installer with --install.'
}

fShowNextSteps() {
  # What the administrator does next: localSIEM installs no module by itself.
  local pAddress="$1"
  local vNumber=0
  local vText
  local aSteps=()
  if [ "$vAction" != 'update' ]; then
    aSteps+=("Sign in at $pAddress as admin, with the password in $cCredentials (it must be changed at the first sign-in).")
  fi
  aSteps+=('localSIEM is ready for its modules: install them from the web (Modules › Installable).')
  aSteps+=('After installing one, the web shows the command to run as root so that localSIEM can read its logs.')
  printf '\n%s\n' "${vBold}Next steps${vReset}"
  for vText in "${aSteps[@]}"; do
    vNumber=$((vNumber + 1))
    printf '  %s %s\n' "${vAccent}${vNumber}.${vReset}" "$vText"
  done
}

fMain() {
  local vArgument
  local vAccountHome
  local vAddress
  local vCheck
  local vOptional
  local vPort
  local vService
  local vState
  local vExpect=''
  local vTitle=''
  local vFinished=''
  local vSoc=''
  local aCopy=()
  # The options for configure.py: every argument but the action and --yes.
  local aArguments=()

  fInitStyle
  for vArgument in "$@"; do
    case "$vExpect" in
      ref)
        vRef="$vArgument"
        vExpect=''
        aArguments+=("$vArgument")
        continue
        ;;
      source-url)
        vSourceUrl="$vArgument"
        vExpect=''
        aArguments+=("$vArgument")
        continue
        ;;
    esac
    case "$vArgument" in
      --help|-h)
        fShowHelp
        return 0
        ;;
      --install|--update|--reinstall|--uninstall)
        if [ -n "$vAction" ] && [ "$vAction" != "${vArgument#--}" ]; then
          fError "Give only one action: --$vAction and $vArgument do not go together."
          return 1
        fi
        vAction="${vArgument#--}"
        continue
        ;;
      --yes)
        vYes='yes'
        continue
        ;;
      --ref)
        vExpect='ref'
        ;;
      --ref=*)
        vRef="${vArgument#--ref=}"
        ;;
      --source-url)
        vExpect='source-url'
        ;;
      --source-url=*)
        vSourceUrl="${vArgument#--source-url=}"
        ;;
      --port|--port=*)
        fError 'The localSIEM web always listens with HTTPS on port 10443: --port is not an option any more.'
        return 1
        ;;
      --configure-*)
        # The setup options of older modules (--configure-apache,
        # --configure-privesc) no longer exist: a module never changes the
        # server, and this installer installs the core only.
        fError "$vArgument does not exist: modules have no setup options (a module never changes anything outside /opt/localsiem)." \
          'Install the modules from the web (Modules › Installable); the web shows the command for root that lets localSIEM read their logs.'
        return 1
        ;;
      --modules-from|--modules-from=*)
        fError "$vArgument is not an option any more: modules are installed from the web only (Modules › Installable)."
        return 1
        ;;
    esac
    aArguments+=("$vArgument")
  done
  if [ -z "$vAction" ]; then
    fError 'Say what to do, with one action:' \
      '  --install     install localSIEM on a server that does not have it' \
      '  --update      update the installed localSIEM (it keeps everything)' \
      '  --reinstall   delete the installed localSIEM with all its data and install it again from zero' \
      '  --uninstall   delete localSIEM and all its data from this server' \
      '--help shows every option.'
    return 1
  fi
  if [ "$vAction" = 'uninstall' ] && [ "${#aArguments[@]}" -gt 0 ]; then
    fError '--uninstall goes alone (or with --yes): it takes no other option.'
    return 1
  fi
  if [ -n "$vYes" ] && [ "$vAction" != 'uninstall' ] && [ "$vAction" != 'reinstall' ]; then
    fError '--yes only goes with --reinstall or --uninstall.'
    return 1
  fi
  if [ -n "$vRef" ] && { [[ ! "$vRef" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || [[ "$vRef" == *..* ]]; }; then
    fError 'Invalid --ref (a branch or a tag).'
    return 1
  fi
  if [ "$(id -u)" -ne 0 ]; then
    fError 'Run this installer as root.'
    return 1
  fi
  umask 077
  if [ "$vAction" = 'uninstall' ]; then
    fUninstall || return 1
    return 0
  fi
  if [ "$vAction" = 'install' ] && fIsInstalled; then
    fError 'localSIEM is already installed on this server (/opt/localsiem, its services or its user), so --install stops. Use:' \
      '  --update      to update it, keeping its data, accounts, settings, modules and options' \
      '  --reinstall   to delete it with all its data and install it again from zero'
    return 1
  fi
  if [ "$vAction" != 'install' ] && ! fIsInstalled; then
    fError "localSIEM is not installed on this server, so there is nothing to $vAction: use --install."
    return 1
  fi
  case "$vAction" in
    install)
      vTitle='Installation'
      vFinished='Installation finished'
      vStepTotal=12
      ;;
    update)
      vTitle='Update'
      vFinished='Update finished'
      vStepTotal=12
      ;;
    reinstall)
      vTitle='Reinstallation'
      vFinished='Reinstallation finished'
      vStepTotal=13
      # Asked before anything changes; what is deleted, only once the new
      # copy is downloaded and its options are checked (below).
      fConfirmRemoval 'reinstall' || return 1
      if [ -z "$vConfirmed" ]; then
        return 0
      fi
      ;;
  esac
  touch "$cInstallLog" "$cCredentials" || return 1
  chown root:root "$cInstallLog" "$cCredentials" || return 1
  chmod 600 "$cInstallLog" "$cCredentials" || return 1
  # Nothing prints the SOC token, so it never reaches the installation log.
  fStartLog
  fShowHeader "$vTitle" || return 1

  fStep 'Checking the system'
  if [ ! -f /etc/alpine-release ] || [ ! -d /run/openrc ]; then
    fFail 'Alpine Linux with OpenRC and Python 3.13 or newer is required.'
    return 1
  fi
  fOk "Alpine Linux $(cat /etc/alpine-release) with OpenRC"
  fEnsurePackages || return 1
  if ! vCheck="$(python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 13) else "Python 3.13 or newer is required; use Alpine 3.24 or newer.")' 2>&1)"; then
    fFail "$vCheck"
    return 1
  fi
  fOk "Python $(python3 -c 'import platform; print(platform.python_version())')"

  fStep 'Getting localSIEM'
  fGetSource || return 1
  mkdir -p "$vSourcePath/_/temp" || return 1
  vTemporaryPath="$(mktemp -d "$vSourcePath/_/temp/install.XXXXXX")" || return 1

  fStep 'Checking the options'
  PYTHONDONTWRITEBYTECODE=1 python3 "$vSourcePath/deploy/configure.py" --check-arguments "${aArguments[@]}" 2>&1 | fIndent || return 1
  fOk 'Options checked'

  if [ "$vAction" = 'reinstall' ]; then
    # Only now, with the new copy downloaded and its options checked: a
    # failed download or a wrong option leaves the installation as it was.
    fStep 'Deleting the installed localSIEM with all its data'
    fRemoveInstallation || return 1
    # The credentials file goes when it only had localSIEM entries.
    touch "$cCredentials" || return 1
    chown root:root "$cCredentials" || return 1
    chmod 600 "$cCredentials" || return 1
    fOk 'Installed localSIEM deleted: installing it again from zero'
  fi

  fStep 'Preparing the user and the folders'
  if getent passwd localsiem >/dev/null; then
    vAccountHome="$(getent passwd localsiem | cut -d: -f6)" || return 1
    if [ "$vAccountHome" != '/opt/localsiem' ] && [ "$vAccountHome" != '/opt/localsiem/' ]; then
      fFail 'Existing user localsiem has a different home. Installation stopped.'
      return 1
    fi
    if [ "$(id -gn localsiem)" != 'localsiem' ]; then
      fFail 'Existing user localsiem must have primary group localsiem.'
      return 1
    fi
    fOk 'System user localsiem (existing)'
  else
    if ! getent group localsiem >/dev/null; then
      fRun '' 'Could not create the group localsiem' addgroup -S localsiem || return 1
    fi
    fRun 'System user localsiem created' 'Could not create the system user localsiem' adduser -S -D -H -h /opt/localsiem -s /sbin/nologin -G localsiem localsiem || return 1
  fi
  # modules/: the modules the web installs later (Modules › Installable);
  # an update keeps the ones already there.
  install -d -m 700 -o localsiem -g localsiem /opt/localsiem "$cDestination" /opt/localsiem/config /opt/localsiem/db /opt/localsiem/certificates /opt/localsiem/run /opt/localsiem/log /opt/localsiem/modules || return 1
  fOk 'Folders of /opt/localsiem ready'

  fStep 'Installing the code'
  # Files that only exist in a working copy (they are not published on
  # GitHub) are copied when they are there.
  aCopy=(backend frontend deploy README.md doc)
  for vOptional in AGENTS.md CLAUDE.md RulesForThisProjectOnly.md Rules .gitignore; do
    if [ -e "$vSourcePath/$vOptional" ]; then
      aCopy+=("$vOptional")
    fi
  done
  fRun '' 'Could not pack the copy of localSIEM' tar -C "$vSourcePath" -cf "$vTemporaryPath/source.tar" "${aCopy[@]}" || return 1
  if rc-service --exists localsiem-web && rc-service localsiem-web status >/dev/null 2>&1; then
    fRun 'Service localsiem-web stopped' 'Could not stop localsiem-web' rc-service localsiem-web stop || return 1
  fi
  if rc-service --exists localsiem && rc-service localsiem status >/dev/null 2>&1; then
    fRun 'Service localsiem stopped' 'Could not stop localsiem' rc-service localsiem stop || return 1
  fi
  # The code is replaced as a whole: files of older versions do not stay.
  rm -rf -- "$cDestination/backend" "$cDestination/frontend" || return 1
  fRun '' "Could not unpack the code into $cDestination" tar -C "$cDestination" -xf "$vTemporaryPath/source.tar" || return 1
  # requirements.txt moved to backend/: the copy of older versions goes.
  rm -f -- "$cDestination/requirements.txt" || return 1
  fOk "Code installed in $cDestination"

  fStep 'Preparing the Python environment'
  # Dependencies in a virtual environment of its own: pip never touches the
  # Python packages of the distribution that the client's services use.
  if [ ! -x "$cVenv/bin/python" ] || ! "$cVenv/bin/python" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 13) else 1)' 2>/dev/null; then
    rm -rf -- "$cVenv" || return 1
    fRun "Virtual environment created in $cVenv" "Could not create the virtual environment $cVenv" python3 -m venv "$cVenv" || return 1
  else
    fOk "Virtual environment $cVenv (existing)"
  fi
  fRun 'Python packages installed (backend/requirements.txt)' 'pip could not install backend/requirements.txt' fInstallPythonPackages || return 1

  fStep 'Configuring localSIEM'
  PYTHONDONTWRITEBYTECODE=1 "$cVenv/bin/python" "$cDestination/deploy/configure.py" "${aArguments[@]}" 2>&1 | fIndent || return 1

  fStep 'Read access to the logs of the modules'
  fGrantLogAccess || return 1

  fStep 'Starting the services'
  chown -R localsiem:localsiem /opt/localsiem || return 1
  chmod 700 "$cDestination/backend/server.py" "$cDestination/backend/collector.py" "$cDestination/backend/manage.py" "$cDestination/deploy/install-update-reinstall-debian.sh" "$cDestination/deploy/install-update-reinstall-alpine.sh" "$cDestination/deploy/configure.py" || return 1
  install -m 755 "$cDestination/deploy/localsiem.initd" /etc/init.d/localsiem || return 1
  install -m 755 "$cDestination/deploy/localsiem-web.initd" /etc/init.d/localsiem-web || return 1
  install -m 644 "$cDestination/deploy/localsiem.logrotate" /etc/logrotate.d/localsiem || return 1
  fRun '' 'Could not add localsiem to the default runlevel' rc-update add localsiem default || return 1
  fRun '' 'Could not add localsiem-web to the default runlevel' rc-update add localsiem-web default || return 1
  fOk 'Services installed and enabled at boot: localsiem, localsiem-web'
  fRun '' 'Could not restart localsiem' rc-service localsiem restart || return 1
  fRun '' 'Could not restart localsiem-web' rc-service localsiem-web restart || return 1
  sleep 5
  for vService in localsiem localsiem-web; do
    if vState="$(rc-service "$vService" status 2>&1)"; then
      fOk "$vService is started"
    else
      fFail "$vService is not started"
    fi
    printf '%s\n' "$vState" | fIndent '    ' "$vDim"
  done

  fStep 'Installed modules'
  fAsLocalsiem "LOCALSIEM_COLOR=$vColorMode PYTHONDONTWRITEBYTECODE=1 $cVenv/bin/python $cDestination/backend/manage.py modules" 2>&1 | fIndent || true

  fStep 'Doctor (as the localsiem user)'
  fAsLocalsiem "LOCALSIEM_COLOR=$vColorMode PYTHONDONTWRITEBYTECODE=1 $cVenv/bin/python $cDestination/backend/manage.py doctor" 2>&1 | fIndent || true

  fStep 'SOC'
  if [ -s /opt/localsiem/config/soc-token ]; then
    if fAsLocalsiem "LOCALSIEM_COLOR=$vColorMode PYTHONDONTWRITEBYTECODE=1 $cVenv/bin/python $cDestination/backend/manage.py soc-test" 2>&1 | fIndent; then
      vSoc="${vGreen}connected${vReset}: the SOC answered the first heartbeat"
    else
      fWarn 'The SOC did not accept the heartbeat. Check --soc-url, --soc-token and the network.'
      vSoc="${vYellow}not connected${vReset}: the SOC did not accept the heartbeat"
    fi
  else
    fInfo 'No SOC (it is optional): localSIEM works on its own and keeps its alerts as not sent.'
    fDetail 'To connect it to a SOC: --soc-token, or Administration › SOC; only the alerts after that are sent.'
    vSoc='none (optional): --soc-token or Administration › SOC'
  fi

  vPort="$(sed -n 's/^LOCALSIEM_INSTALL_PORT=//p' /opt/localsiem/config/install.env)"
  vAddress="https://$(sed -n 's/^LOCALSIEM_INSTALL_DOMAIN=//p' /opt/localsiem/config/install.env):$vPort"
  printf '\n%s %s\n' "${vGreen}✓${vReset}" "${vBold}$vFinished${vReset}"
  fRule
  fField 'Address' "$vAddress (the web, and the SIEM address for the SOC)"
  fField 'Credentials' "$cCredentials (mode 600)"
  fField 'Log' "$cInstallLog (mode 600)"
  fField 'SOC' "$vSoc"
  fShowTimestamp 'Finished' || return 1
  fShowNextSteps "$vAddress"
}

if ! fMain "$@"; then
  fShowFailure
  exit 1
fi
