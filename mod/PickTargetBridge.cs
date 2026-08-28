using System;
using XRL;                  // GameManager
using ConsoleLib.Console;   // Keyboard.PushMouseEvent — the picker reads Qud's own event queue

namespace RavesOfQud
{
    /// <summary>
    /// Mirrors Qud's TARGET PICKER — the cursor it puts up for a ray, a burst, a thrown rock or a
    /// direction — to Raves, and drives it from the viewer's mouse.
    ///
    /// Daniel: "I'm trying to use flaming ray, but the Raves just tries to Chat with the
    /// Dawngliders." Once the ability fired, Qud sat in PickTarget waiting for a target and RAVES
    /// SHOWED NOTHING: no cursor, no prompt, and — because the picker spins on the turn thread —
    /// no snapshots either, so the viewer looked frozen while the game waited. A click went through
    /// Raves' ordinary verb table, which knows nothing about targeting, and chatted at a hostile.
    ///
    /// THREADING, and why this lives on the uiQueue watcher. PickTarget.ShowPicker is a LOOP ON THE
    /// TURN THREAD: RenderMapToBuffer, DrawBuffer, kbhit, repeat. It never returns to publish a
    /// snapshot, so nothing on the snapshot channel can carry this. The UI thread keeps drawing and
    /// keeps draining uiQueue throughout — the same fact PopupBridge is built on — so detection and
    /// injection both go there.
    ///
    /// THE PICKER'S INPUT CONTRACT, read off the decompiled ShowPicker rather than guessed:
    ///   PointerOver(x,y)  moves the cursor   — but the FIRST one is deliberately swallowed
    ///                                          (`if (PointerOver && !flag3)`, then `flag3 = false`),
    ///                                          so Qud does not snap the cursor to a stale pointer
    ///                                          the moment the picker opens. We therefore send it
    ///                                          TWICE; one PointerOver would land the shot on
    ///                                          whatever cell Qud started on.
    ///   LeftClick         confirms at the CURSOR — it does not carry a cell of its own, which is
    ///                                          why the move has to happen first and separately.
    ///   RightClick        aborts.
    /// The direction picker (PickDirection) reads the same events, which is how the `walk` command
    /// already drives it.
    /// </summary>
    public static class PickTargetBridge
    {
        private static bool _active;
        private static string _sig = "";
        private static volatile bool _resend;

        /// A client just connected — re-announce a picker that is already up.
        public static void Resend() { _resend = true; }

        private static void Log(string s) { try { Bridge.Server?.Log(s); } catch { } }

        /// UI THREAD. Publish the picker's state when it changes.
        public static void Poll(BridgeServer server)
        {
            try
            {
                if (server == null || server.ClientCount == 0) return;
                var w = Qud.UI.PickTargetWindow.instance;
                bool on = w != null && w.Visible;
                string mode = Qud.UI.PickTargetWindow.currentMode.ToString();
                string text = Qud.UI.PickTargetWindow.currentText ?? "";
                // The prompt is the ONE thing that says what is being aimed — "Flaming Ray |
                // Space-select | unlock (F1)" — so a change in it is a change worth sending even
                // while the picker stays up.
                string sig = on ? (mode + "|" + text) : "";
                bool resend = _resend;
                _resend = false;
                if (on == _active && sig == _sig && !resend) return;
                _active = on;
                _sig = sig;

                var j = new JsonWriter();
                j.BeginObject().Member("type", Protocol.TypePickTarget).Member("active", on);
                if (on)
                {
                    j.Member("mode", mode).Member("text", text);
                    // Where the shot comes FROM, so Raves can draw the line without guessing which
                    // object is the player this frame.
                    var c = The.Player?.CurrentCell;
                    if (c != null) j.Member("px", c.X).Member("py", c.Y);
                }
                j.EndObject();
                try { server.Publish(Protocol.Frame(j.ToString())); } catch { }
            }
            catch { }
        }

        /// Point the picker at a cell and take the shot, or call it off.
        ///
        /// Queued on the uiQueue rather than run here: the caller is the bridge's own reader thread,
        /// and Keyboard's event queue is fed from Unity's side.
        public static void Answer(int x, int y, bool cancel)
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.uiQueue == null) return;
            gm.uiQueue.queueTask(() =>
            {
                try
                {
                    if (cancel)
                    {
                        Keyboard.PushMouseEvent("RightClick", x, y);
                        return;
                    }
                    // Twice, then confirm — see the input contract above.
                    Keyboard.PushMouseEvent("PointerOver", x, y);
                    Keyboard.PushMouseEvent("PointerOver", x, y);
                    Keyboard.PushMouseEvent("LeftClick", x, y);
                }
                catch (Exception e) { Log("picktarget answer failed: " + e.Message); }
            }, 0);
        }
    }
}
