#!/usr/bin/env -S PYTHONDONTWRITEBYTECODE=1 python3

"""localSIEM administration from the command line (run by root or the installer).

  manage.py ensure-admin [--credentials FILE]   create the first administrator
  manage.py create-user USERNAME [--role admin|analyst] [--credentials FILE]
  manage.py reset-password USERNAME [--credentials FILE]
  manage.py reset-mfa USERNAME
  manage.py list-users
  manage.py doctor [--json]                    requirements of every enabled module, and of the ones off that have requirements
  manage.py modules                            installed modules, version, state and the requirements they lack
  manage.py read-paths                         folders the modules read
  manage.py soc-test                           send a heartbeat to the SOC

Modules are installed only from the web (Modules › Installable). What
needs root after that, the command the web shows:

  manage.py setup-modules [--no-restart]       read access for localsiem to the folders of the installed modules
                                               (ACLs; adm group on Debian) and a restart of localSIEM

A module never installs anything nor changes anything else on the server.

Generated passwords are printed and, with --credentials, appended to that
file (mode 600).

Results are marked ✓ (done, ok), ! (warning), ✗ (failure) and · (information),
in colour only on a terminal (backend/core/terminal.py: LOCALSIEM_COLOR=always
or never, NO_COLOR). read-paths and doctor --json print for programs: one
path per line and JSON, never with marks nor colours.
"""

import sys

if sys.version_info < (3, 13):
  raise SystemExit("Python 3.13 or newer is required.")

# Run as root, too: no __pycache__ owned by root in the code of localSIEM or
# in the modules, which localsiem replaces when it updates them.
sys.dont_write_bytecode = True

import argparse
import json
import os
import shlex
import subprocess
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from backend.core.config import cWebDatabaseFile, fLoadSettings, fReadSocToken
from backend.core.terminal import fColorMode, fDetail, fFailure, fInfo, fMark, fOk, fStyle, fTitle, fWarning, fWrite
from backend.core.timeutil import fNowStorage


def fAccounts():
  from backend.core.config import fGetSecret
  from backend.web.auth import Accounts
  from backend.web.webdb import WebDatabase
  vDatabase = WebDatabase(cWebDatabaseFile)
  vDatabase.mInitialize()
  return Accounts(vDatabase, fLoadSettings(), fGetSecret("LOCALSIEM_SECRET_KEY") or "x" * 32)


def fWriteCredentials(pPath: str, pLines: list[str]) -> None:
  if not pPath:
    return
  vDescriptor = os.open(pPath, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
  with os.fdopen(vDescriptor, "a", encoding="utf-8") as vFile:
    os.fchmod(vFile.fileno(), 0o600)
    vFile.write("\n" + "\n".join(pLines) + "\n")


def fCreateUser(pUsername: str, pRole: str, pCredentials: str) -> None:
  from backend.web.auth import fGeneratePassword
  vAccounts = fAccounts()
  vPassword = fGeneratePassword()
  vAccounts.mCreateUser(pUsername, pRole, vPassword)
  fOk(f"Account {pUsername} ({pRole}) created.")
  fWrite("  Password: " + fStyle(vPassword, "bold"))
  fWriteCredentials(pCredentials, [
    f"localSIEM web account — {fNowStorage()}",
    f"Username: {pUsername}",
    f"Role: {pRole}",
    f"Password: {vPassword}",
    "Two-step verification: set up at the first sign-in (authenticator app: «PYMEHackers localSIEM»)." if vAccounts.dSettings.get("mfa_enabled", False) else "Two-step verification: off (an administrator can turn it on in Administration › Settings)."
  ])


def fModules() -> tuple[dict, list[dict], list[dict], dict]:
  from backend.core.masking import fCreateMasker
  from backend.core.registry import fCreateModules
  dSettings = fLoadSettings()
  dModules, ldManifests, ldErrors = fCreateModules(dSettings, fCreateMasker(dSettings), None)
  return dModules, ldManifests, ldErrors, dSettings


def fReadPaths() -> list[str]:
  # Folders the installed modules read (read_paths of each module.json).
  from backend.core.registry import fListManifests
  sPaths = set()
  for dManifest in fListManifests()[0]:
    for vPath in dManifest.get("read_paths", []) or []:
      vText = str(vPath)
      if vText.startswith("/") and "\n" not in vText and ".." not in vText:
        sPaths.add(vText)
  return sorted(sPaths)


def fRunCommand(pCommand: list[str]) -> None:
  # A command of the system, as root; if it fails, manage.py stops.
  vResult = subprocess.run(pCommand, stdin=subprocess.DEVNULL)
  if vResult.returncode != 0:
    raise ValueError(f"{shlex.join(pCommand)} failed (exit status {vResult.returncode}).")


def fGrantReadAccess() -> None:
  # localsiem reads the logs of the folders its installed modules declare
  # (read_paths; /var/log/apache2 for the apache2 module). On Debian through
  # the adm group (Debian creates them root:adm 640) and, for files created
  # with another group, through ACLs; on Alpine (root:wheel, in a folder only
  # wheel can enter) through ACLs only. The ACLs also cover the files of the
  # next rotations (default ACL). Without modules there is nothing to do. The
  # installers do it at every update (fGrantLogAccess), so the modules keep
  # their access.
  lFolders = fReadPaths()
  if not lFolders:
    fInfo("No installed module declares folders to read.")
    return
  vAlpine = Path("/etc/alpine-release").exists()
  if not vAlpine:
    fRunCommand(["usermod", "-aG", "adm", "localsiem"])
  for vFolder in lFolders:
    if not os.path.isdir(vFolder):
      fInfo(f"{vFolder} does not exist (yet): nothing to do there.")
      continue
    try:
      vAcl = subprocess.run(["setfacl", "-m", "g:localsiem:rx", vFolder], stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    except OSError:
      vAcl = False
    if not vAcl:
      if vAlpine:
        fWarning(f"The file system of {vFolder} does not support ACLs: give localsiem read access to the logs of {vFolder} by hand.")
      else:
        fWarning(f"The file system of {vFolder} does not support ACLs: localsiem reads through the adm group only.")
      continue
    fRunCommand(["setfacl", "-d", "-m", "g:localsiem:r", vFolder])
    for vFile in sorted(Path(vFolder).iterdir()):
      if vFile.is_file() and not vFile.name.startswith("."):
        fRunCommand(["setfacl", "-m", "g:localsiem:r", str(vFile)])
    fOk(f"localsiem can read {vFolder}.")


def fRestartServices() -> None:
  # Both services, as the installers do: the collector reads with the new
  # permissions (the groups of a running process do not change).
  if Path("/etc/alpine-release").exists():
    fRunCommand(["rc-service", "localsiem", "restart"])
    fRunCommand(["rc-service", "localsiem-web", "restart"])
  else:
    fRunCommand(["systemctl", "restart", "localsiem.service"])
    fRunCommand(["systemctl", "restart", "localsiem-web.service"])


def fDoctorAsLocalsiem() -> None:
  # The doctor as the localsiem user: what it can read now. It prints where
  # this process prints, so it takes the same decision about colours.
  lCommand = ["env", "LOCALSIEM_COLOR=" + fColorMode(), sys.executable, str(Path(__file__).resolve()), "doctor"]
  if Path("/etc/alpine-release").exists():
    # Alpine has no runuser: su with a shell, since localsiem has none.
    lCommand = ["su", "-s", "/bin/sh", "localsiem", "-c", shlex.join(lCommand)]
  else:
    lCommand = ["runuser", "-u", "localsiem", "--"] + lCommand
  subprocess.run(lCommand, stdin=subprocess.DEVNULL)


def fMain(pArguments: list[str]) -> None:
  vParser = argparse.ArgumentParser(description="localSIEM administration.")
  vSubparsers = vParser.add_subparsers(dest="vCommand", required=True)
  vSub = vSubparsers.add_parser("ensure-admin")
  vSub.add_argument("--credentials", default="")
  vSub = vSubparsers.add_parser("create-user")
  vSub.add_argument("username")
  vSub.add_argument("--role", default="analyst", choices=["admin", "analyst"])
  vSub.add_argument("--credentials", default="")
  vSub = vSubparsers.add_parser("reset-password")
  vSub.add_argument("username")
  vSub.add_argument("--credentials", default="")
  vSub = vSubparsers.add_parser("reset-mfa")
  vSub.add_argument("username")
  vSubparsers.add_parser("list-users")
  vSub = vSubparsers.add_parser("doctor")
  vSub.add_argument("--json", action="store_true")
  vSubparsers.add_parser("modules")
  vSubparsers.add_parser("read-paths")
  vSubparsers.add_parser("soc-test")
  vSub = vSubparsers.add_parser("setup-modules")
  vSub.add_argument("--no-restart", action="store_true")
  vArguments, lExtra = vParser.parse_known_args(pArguments)
  if lExtra:
    # The setup options of older modules (--configure-apache,
    # --configure-privesc) no longer exist: a module never changes the server.
    vParser.error("unrecognized arguments: " + " ".join(lExtra) + " (modules have no setup options: setup-modules only gives read access)")

  if vArguments.vCommand == "ensure-admin":
    vAccounts = fAccounts()
    if vAccounts.mUserCount() == 0:
      fCreateUser("admin", "admin", vArguments.credentials)
    else:
      fInfo("Accounts already exist; nothing created.")
    return
  if vArguments.vCommand == "create-user":
    fCreateUser(vArguments.username, vArguments.role, vArguments.credentials)
    return
  if vArguments.vCommand == "reset-password":
    from backend.web.auth import fGeneratePassword
    vAccounts = fAccounts()
    dUser = vAccounts.mGetUserByName(vArguments.username)
    if dUser is None:
      raise ValueError(f"Unknown account: {vArguments.username}")
    vPassword = fGeneratePassword()
    vAccounts.mSetPassword(dUser["id"], vPassword, True)
    fOk(f"New password of {dUser['username']} (it must be changed at the next sign-in).")
    fWrite("  Password: " + fStyle(vPassword, "bold"))
    fWriteCredentials(vArguments.credentials, [f"localSIEM password reset — {fNowStorage()}", f"Username: {dUser['username']}", f"Password: {vPassword}"])
    return
  if vArguments.vCommand == "reset-mfa":
    vAccounts = fAccounts()
    dUser = vAccounts.mGetUserByName(vArguments.username)
    if dUser is None:
      raise ValueError(f"Unknown account: {vArguments.username}")
    vAccounts.mResetTotp(dUser["id"])
    fOk(f"Two-step verification of {dUser['username']} reset: it is set up again at the next sign-in.")
    return
  if vArguments.vCommand == "list-users":
    vMfaEnabled = bool(fLoadSettings().get("mfa_enabled", False))
    ldUsers = fAccounts().mListUsers()
    if ldUsers:
      fWrite(fStyle(f"{'USERNAME':<24} {'ROLE':<8} {'STATE':<9} TWO-STEP", "dim"))
    else:
      fInfo("No accounts.")
    for dUser in ldUsers:
      vState = f"{'active' if dUser['is_active'] else 'disabled':<9}"
      vState = fStyle(vState, "green") if dUser["is_active"] else fStyle(vState, "dim")
      fWrite(f"{dUser['username']:<24} {dUser['role']:<8} {vState} 2FA {('on' if dUser['totp_enabled_at'] else 'pending') if vMfaEnabled else 'off'}")
    return
  if vArguments.vCommand == "doctor":
    from backend.core.registry import fCheckRequirements
    dModules, _, ldErrors, _ = fModules()
    dReport = {}
    for vName, vModule in dModules.items():
      if not vModule.mEnabled():
        # A module that is off has no doctor; its requirements say whether it
        # can be turned on (installing it never installs what it watches).
        ldRequirements = fCheckRequirements(vModule)["checks"]
        if ldRequirements:
          dReport[vName] = {"enabled": False, "requirements": ldRequirements}
        continue
      ldSources = vModule.mDiscover()
      dReport[vName] = {"enabled": True, "sources": ldSources, "skipped": vModule.mSkipped(), "checks": vModule.mDoctor()}
    if vArguments.json:
      print(json.dumps({"modules": dReport, "errors": ldErrors}, indent=2, ensure_ascii=False))
      return
    def fPrintChecks(ldChecks: list[dict]) -> None:
      # ✓ ok, ! warning, ✗ error, · info; the detail dimmed below, and the
      # fix of what is not ok below it.
      for dCheck in ldChecks:
        fMark(dCheck.get("status"), dCheck.get("title", ""), 2)
        if dCheck.get("detail"):
          fDetail(dCheck["detail"], 4)
        if dCheck.get("fix") and dCheck.get("status") != "ok":
          for vLine in dCheck["fix"].splitlines():
            fWrite(f"      {vLine}")

    for dError in ldErrors:
      fFailure(f"Module {dError['id']} not loaded: {dError['error']}")
    if not dModules:
      fInfo("No modules installed in /opt/localsiem/modules: localSIEM reads no logs yet. Install them from the web (Modules › Installable).")
    # A blank line between the module reports and what is printed above them.
    vPrinted = bool(ldErrors) or not dModules
    for vName, dModuleReport in dReport.items():
      if vPrinted:
        fWrite()
      vPrinted = True
      if not dModuleReport["enabled"]:
        fTitle(f"localSIEM doctor — module {vName} (off): what it needs before it can be turned on")
        fPrintChecks(dModuleReport["requirements"])
        continue
      fTitle(f"localSIEM doctor — module {vName}")
      fPrintChecks(dModuleReport["checks"])
      if dModuleReport["sources"]:
        fWrite("  " + fStyle("Sources", "bold"))
      for dSource in dModuleReport["sources"]:
        fWrite(f"    {dSource['kind']:<7} {dSource['path']}" + (fStyle(f"  (vhost {dSource['vhost']})", "dim") if dSource.get("vhost") else ""))
    return
  if vArguments.vCommand == "modules":
    from backend.core.registry import fCheckRequirements
    dModules, ldManifests, ldErrors, _ = fModules()
    if not ldManifests and not ldErrors:
      fInfo("No modules installed: localSIEM reads no logs yet. Install them from the web (Modules › Installable).")
      return
    dStateStyles = {"enabled": ["green"], "disabled": [], "not loaded": ["red"], "error": ["red"]}
    fWrite(fStyle(f"{'MODULE':<16} {'VERSION':<10} {'STATE':<10} FOLDER", "dim"))
    for dManifest in ldManifests:
      vModule = dModules.get(dManifest["id"])
      vState = "not loaded" if vModule is None else ("enabled" if vModule.mEnabled() else "disabled")
      vStateText = fStyle(f"{vState:<10}", *dStateStyles[vState])
      fWrite(f"{dManifest['id']:<16} {dManifest.get('version', ''):<10} {vStateText} {dManifest['path']}")
      # What the server lacks for it: off, it cannot be turned on until then.
      if vModule is not None:
        ldMissing = [dCheck for dCheck in fCheckRequirements(vModule)["checks"] if dCheck.get("status") == "error"]
        if ldMissing:
          fWarning("requirements missing: " + "; ".join(str(dCheck.get("title") or dCheck.get("id") or "") for dCheck in ldMissing), 17)
    for dError in ldErrors:
      vStateText = fStyle(f"{'error':<10}", *dStateStyles["error"])
      fWrite(f"{dError['id']:<16} {'':<10} {vStateText} {dError['error']}")
    return
  if vArguments.vCommand == "read-paths":
    for vPath in fReadPaths():
      print(vPath)
    return
  if vArguments.vCommand == "soc-test":
    from backend.core.soc import SocClient, SocError
    dSettings = fLoadSettings()
    vToken = fReadSocToken()
    if not vToken:
      raise ValueError("No SOC token configured (/opt/localsiem/config/soc-token).")
    try:
      SocClient(dSettings["soc_url"], vToken, dSettings.get("soc_ca_file", "")).mHeartbeat()
      fOk(f"The SOC ({dSettings['soc_url']}) accepted the heartbeat.")
    except SocError as vError:
      raise ValueError(f"The SOC answered HTTP {vError.vStatus} {vError.vCode}") from None
    return
  if vArguments.vCommand == "setup-modules":
    # What the web asks root to run after installing a module, and after
    # Reconfigure finds its requirements; the installers run it with
    # --no-restart. Idempotent.
    if os.geteuid() != 0:
      raise ValueError("setup-modules changes the permissions of the logs of other services and restarts localSIEM: run it as root.")
    fGrantReadAccess()
    if vArguments.no_restart:
      return
    fRestartServices()
    fOk("localSIEM restarted (services localsiem and localsiem-web).")
    fWrite()
    fTitle("localSIEM doctor (as the localsiem user)")
    fDoctorAsLocalsiem()
    return


if __name__ == "__main__":
  try:
    fMain(sys.argv[1:])
  except (OSError, ValueError) as vError:
    fFailure(f"Error: {vError}", pError=True)
    raise SystemExit(1) from vError
