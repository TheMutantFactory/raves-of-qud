using System;
using Qud.UI;
using XRL;

namespace RavesOfQud
{
    /// <summary>
    /// Mirrors Qud's TOMBSTONE — the GameSummaryScreen shown when a character dies, abandons, or
    /// reaches an ending — to Raves, and hands its Exit back.
    ///
    /// This one is a DESYNC, not just a missing view. When a run ends, Qud parks on the summary
    /// while Raves' own heartbeat sees a game that is no longer live and returns to the title. The
    /// two windows then disagree about where the player is, and the summary has to be dismissed by
    /// hand in the other window before anything else works. (QudSync's resync already had a
    /// special case for exactly this; mirroring the screen is the fix that case was standing in
    /// for.)
    ///
    /// IS IT UP: `completionSource` is created in _ShowGameSummary and completed by Exit(), so a
    /// live, uncompleted source is the screen being shown. That beats testing the GameObject,
    /// which is also active while the window animates out.
    ///
    /// The text is read from the screen's own fields — Name and Details are public, and the cause
    /// of death is only kept in causeText, because _ShowGameSummary rewrites its `cause` local for
    /// the ending variants before setting the skin.
    /// </summary>
    public static class TombstoneBridge
    {
        private static string _sig = "";
        private static bool _resend;

        private static void Log(string s) { try { Bridge.Server?.Log(s); } catch { } }

        public static void OnClientConnect() { _resend = true; }

        private static GameSummaryScreen Live()
        {
            var s = SingletonWindowBase<GameSummaryScreen>.instance;
            if (s == null || s.completionSource == null) return null;
            return s.completionSource.Task.IsCompleted ? null : s;
        }

        /// UI THREAD, from PopupBridge's watcher — the summary parks the turn thread like every
        /// other end-of-run screen, so this is the only pump left.
        public static void Poll(BridgeServer server)
        {
            try
            {
                if (server == null || server.ClientCount == 0) return;
                var s = Live();
                string name = "", cause = "", details = "";
                if (s != null)
                {
                    name = s.Name ?? "";
                    details = s.Details ?? "";
                    try { if (s.causeText != null) cause = s.causeText.text ?? ""; } catch { }
                }
                string sig = s != null ? (name + "|" + cause + "|" + details.Length) : "off";
                if (sig == _sig && !_resend) return;
                _sig = sig;
                _resend = false;

                var j = new JsonWriter();
                j.BeginObject().Member("type", Protocol.TypeTombstone).Member("active", s != null);
                if (s != null)
                    j.Member("name", name).Member("cause", cause).Member("details", details);
                j.EndObject();
                server.Publish(Protocol.Frame(j.ToString()));
                if (s != null) Log("[tombstone] mirroring the game summary to Raves");
            }
            catch (Exception e) { Log("tombstone poll: " + e.Message); }
        }

        /// SOCKET THREAD. [F1] on the mirrored screen. Qud writes the file (into ITS documents
        /// folder, with its own naming) — Raves must not invent a second copy somewhere else.
        public static void RequestSave()
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.uiQueue == null) return;
            gm.uiQueue.queueTask(delegate
            {
                try
                {
                    var s = Live();
                    if (s != null) { s.SaveTombstone(); Log("[tombstone] save requested by Raves"); }
                }
                catch (Exception e) { Log("tombstone save: " + e.Message); }
            }, 0);
        }

        /// SOCKET THREAD. The viewer dismissed the tombstone; complete Qud's await so its own
        /// screen closes too and both windows leave together.
        public static void RequestExit()
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.uiQueue == null) return;
            gm.uiQueue.queueTask(delegate
            {
                try
                {
                    var s = Live();
                    if (s != null) { s.Exit(); Log("[tombstone] exit requested by Raves"); }
                }
                catch (Exception e) { Log("tombstone exit: " + e.Message); }
            }, 0);
        }
    }
}
