#!/usr/bin/env python3
"""Qud lifecycle — quit / start / load, so the recompile-and-resume loop is one command.

The mod only compiles at app startup, so iterating on it means: quit Qud, (redeploy),
start Qud, load the save, keep testing. This automates that. Also handy for humans.

  qud.py status                 # running? window up? bridge (in-game)?
  qud.py quit                   # graceful quit -> terminate -> force
  qud.py start                  # launch via Steam, wait for the window
  qud.py load                   # from the main menu, resume the latest save (presses C, then Return)
  qud.py load <save name>       # load THAT save through the bridge's loadsave (no keypresses, no focus)
  qud.py restart                # quit + start + load — the full loop

Platform specifics (launch/quit/process/input/paths) come from plat.py (per-OS backend).
`load` needs input permission (macOS Accessibility; see desktop.py check). Detection: the
mod's bridge server (port 48710) only listens once a game is loaded, so bridge-up == in-game.
"""
import os
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plat

PORT = 48710              # bridge; open only when in-game


def running():
    return bool(plat.list_pids())


def window_up():
    try:
        plat.bounds("Qud")
        return True
    except Exception:
        return False


def bridge_up(timeout=0.5):
    try:
        socket.create_connection(("127.0.0.1", PORT), timeout=timeout).close()
        return True
    except OSError:
        return False


def _wait(cond, timeout, step=1.0):
    end = time.time() + timeout
    while time.time() < end:
        if cond():
            return True
        time.sleep(step)
    return False


def status():
    return {"running": running(), "window": window_up(), "in_game(bridge)": bridge_up()}


def quit_qud(grace=15):
    if not running():
        return "not running"
    plat.quit_graceful("Qud")                       # lets Qud autosave
    if _wait(lambda: not running(), grace):
        return "quit (graceful)"
    plat.kill_pids(plat.list_pids(), force=False)   # terminate
    if _wait(lambda: not running(), 6):
        return "quit (terminate)"
    plat.kill_pids(plat.list_pids(), force=True)    # force
    _wait(lambda: not running(), 4)
    return "quit (force)" if not running() else "FAILED to quit"


def start(wait_window=120):
    if running():
        return "already running"
    plat.launch_game()
    if _wait(window_up, wait_window):
        time.sleep(6)   # let the main menu finish rendering
        return "started (window up, at menu)"
    return "FAILED: no window within %ds" % wait_window


def in_game(timeout=20):
    """True once the bridge publishes a snapshot with a zone: the listener is up PRE-GAME
    on current builds (StartupHook), so bridge_up() alone no longer means in-game."""
    try:
        import control
        b = control.Bridge(timeout=5)
        try:
            b.send("wait")
            snap = b.read_frame("snapshot", timeout=timeout)
            return bool(snap and snap.get("zone", {}).get("id"))
        finally:
            b.close()
    except (OSError, ValueError):
        return False


def load_save(name, wait_ingame=150):
    """Load a save BY NAME through the bridge's `loadsave` (Qud's own picker flow, no
    keypresses, no focus): the first-party path, and the one a bake or a rig should use."""
    import control
    import saves
    s = saves.find_save(name)
    if s is None:
        return "FAILED: no save named %r (saves.py list)" % name
    if not _wait(bridge_up, 120):
        return "FAILED: no bridge listener (mod not loaded?)"
    if in_game(timeout=8):
        return "already in-game"
    b = control.Bridge(timeout=10)
    try:
        b.send("loadsave", id=s["guid"])
    finally:
        b.close()
    if _wait(lambda: in_game(timeout=8), wait_ingame, step=0.5):
        return "loaded %s (in-game)" % s["name"]
    return "FAILED: %s not in-game within %ds" % (s["name"], wait_ingame)


def load(wait_ingame=150):
    # Main-menu load: press "C" (the Continue shortcut, position independent) which opens
    # the save picker with the most-recent save PRE-SELECTED, then "Return" to load it.
    if not plat.check():
        return "FAILED: load needs input permission (%s)" % plat.PERM_HINT
    if in_game(timeout=5):
        return "already in-game"
    plat.activate("Qud"); time.sleep(1.5)
    plat.key("c"); time.sleep(1.8)
    plat.key("Return")
    if _wait(bridge_up, wait_ingame):
        time.sleep(2)
        return "loaded (in-game)"
    return "FAILED: not in-game within %ds (menu may have changed)" % wait_ingame


def restart():
    print("quit:", quit_qud()); time.sleep(2)
    print("start:", start()); time.sleep(2)
    print("load:", load())


def main(argv):
    if not argv:
        sys.exit(__doc__)
    cmd = argv[0]
    if cmd == "status":
        import json; print(json.dumps(status()))
    elif cmd == "quit":
        print(quit_qud())
    elif cmd == "start":
        print(start())
    elif cmd == "load":
        print(load_save(argv[1]) if len(argv) > 1 else load())
    elif cmd == "restart":
        restart()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
