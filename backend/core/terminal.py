"""Terminal output of the command-line tools of localSIEM.

manage.py and deploy/configure.py print in the same sober style as the
installers: a result line starts with a mark (✓ done, ! warning, ✗ failure,
· information) and its details go below it, indented and dimmed.

Colours only on a terminal, decided once for each stream:

  LOCALSIEM_COLOR=always or never   decides. The installers set it: what they
                                    run writes to the pipe of their log, not
                                    to the terminal, and they write the log
                                    without colour codes.
  NO_COLOR (not empty), TERM=dumb   no colours.
  Otherwise                         colours when the stream is a terminal.

Only the standard library: deploy/configure.py imports it with the Python of
the system, before the virtual environment of localSIEM exists.
"""

import os
import sys

cColorVariable = "LOCALSIEM_COLOR"
dStyles = {"bold": "1", "dim": "2", "red": "31", "green": "32", "yellow": "33", "accent": "36"}
# The mark of each kind of line (the statuses of the doctor), its styles and
# the ASCII mark for a stream that cannot write the other one.
dMarks = {
  "ok": {"mark": "✓", "ascii": "+", "styles": ["green"]},
  "warning": {"mark": "!", "ascii": "!", "styles": ["yellow", "bold"]},
  "error": {"mark": "✗", "ascii": "x", "styles": ["red"]},
  "info": {"mark": "·", "ascii": "-", "styles": ["dim"]}
}
dDecisions = {}


def fStream(pError: bool = False):
  return sys.stderr if pError else sys.stdout


def fUseColor(pError: bool = False) -> bool:
  # Decided once for stdout and once for stderr.
  vName = "stderr" if pError else "stdout"
  if vName not in dDecisions:
    vMode = os.environ.get(cColorVariable, "").strip().lower()
    if vMode in ("always", "never"):
      vDecision = vMode == "always"
    elif os.environ.get("NO_COLOR") or os.environ.get("TERM", "") == "dumb":
      vDecision = False
    else:
      try:
        vDecision = fStream(pError).isatty()
      except (AttributeError, OSError, ValueError):
        vDecision = False
    dDecisions[vName] = vDecision
  return dDecisions[vName]


def fColorMode() -> str:
  # The LOCALSIEM_COLOR of a child process whose output goes where the
  # output of this one goes.
  return "always" if fUseColor() else "never"


def fStyle(pText: str, *pStyles: str, pError: bool = False) -> str:
  if not pText or not pStyles or not fUseColor(pError):
    return pText
  return "\033[" + ";".join(dStyles[vStyle] for vStyle in pStyles) + "m" + pText + "\033[0m"


def fWrite(pText: str = "", pError: bool = False) -> None:
  # Flushed at once, so the installers show it in order with what they print.
  print(pText, file=fStream(pError), flush=True)


def fCanWrite(pText: str, pError: bool = False) -> bool:
  vEncoding = getattr(fStream(pError), "encoding", None) or "utf-8"
  try:
    pText.encode(vEncoding)
  except (LookupError, UnicodeEncodeError):
    return False
  return True


def fMark(pStatus: str | None, pText: str, pIndent: int = 0, pError: bool = False) -> None:
  # One result line: pStatus is ok, warning, error or info; any other one
  # leaves the place of the mark empty.
  dMark = dMarks.get(pStatus or "")
  if dMark is None:
    vMark = " "
  else:
    vMark = dMark["mark"] if fCanWrite(dMark["mark"], pError) else dMark["ascii"]
    vMark = fStyle(vMark, *dMark["styles"], pError=pError)
  fWrite(" " * pIndent + vMark + " " + pText, pError)


def fOk(pText: str, pIndent: int = 0, pError: bool = False) -> None:
  fMark("ok", pText, pIndent, pError)


def fWarning(pText: str, pIndent: int = 0, pError: bool = False) -> None:
  fMark("warning", pText, pIndent, pError)


def fFailure(pText: str, pIndent: int = 0, pError: bool = False) -> None:
  fMark("error", pText, pIndent, pError)


def fInfo(pText: str, pIndent: int = 0, pError: bool = False) -> None:
  fMark("info", pText, pIndent, pError)


def fDetail(pText: str, pIndent: int = 2, pError: bool = False) -> None:
  # Secondary lines, dimmed, below the line they explain.
  for vLine in str(pText).splitlines() or [""]:
    fWrite(" " * pIndent + fStyle(vLine, "dim", pError=pError), pError)


def fTitle(pText: str, pIndent: int = 0, pError: bool = False) -> None:
  fWrite(" " * pIndent + fStyle(pText, "bold", pError=pError), pError)
