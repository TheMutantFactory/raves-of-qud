using System;
using UnityEngine;
using XRL;

namespace RavesOfQud
{
    /// <summary>
    /// Mirrors Qud's TUTORIAL GUIDE — the little box that walks a new player through the sunken
    /// caravanserai — to Raves, so a tutorial played through the viewer still gets told what to
    /// do. Without this Raves showed the tutorial's world and none of its instructions: the one
    /// lane where the text IS the game.
    ///
    /// Where the text lives: TutorialManager.Highlight() stores every guide message in the
    /// instance field lastText, and TutorialManager.IsActive / currentStep say whether a tutorial
    /// is running at all. That is the same field EmbarkDriver already reads once during the guided
    /// chargen (tutorial_tip.txt); this reads it for the whole run.
    ///
    /// Qud's own SENTINELS decide when there is no box: Highlight() hides its frame when the text
    /// contains "noframe", "no message" or "nohighlight" in angle brackets. We honour those three
    /// rather than inventing a rule, so the box appears and disappears exactly when Qud's does.
    ///
    /// Threading: polled from PopupBridge's uiQueue watcher, the ONLY pump still running while the
    /// turn thread is parked in a popup — and the tutorial talks across popups. Publishes
    /// {"type":"tutorial", "active":..., "text":..., "step":...} on change only.
    /// </summary>
    public static class TutorialBridge
    {
        private static string _sig = "";
        private static bool _resend;   // set on client-connect: re-announce the live step once

        private static void Log(string s) { try { Bridge.Server?.Log(s); } catch { } }

        public static void OnClientConnect() { _resend = true; }

        /// UI THREAD. Cheap: a static bool, then one field read on the manager.
        public static void Poll(BridgeServer server)
        {
            try
            {
                if (server == null || server.ClientCount == 0) return;

                string text = null;
                string button = null;
                if (TutorialManager.IsActive)
                {
                    // The manager is a scene object and its `instance` is private, so find it the
                    // same way EmbarkDriver does. FindObjectsOfTypeAll also returns INACTIVE
                    // objects, which matters: the guide hides itself between beats.
                    foreach (var tm in Resources.FindObjectsOfTypeAll<TutorialManager>())
                    {
                        if (tm == null) continue;
                        text = tm.lastText;
                        // The accept prompt ("[Space] Continue") only when Qud is actually WAITING
                        // on it. It is not decoration: without it the viewer cannot tell a step
                        // that is describing something from a step that wants a keypress.
                        try
                        {
                            if (tm.PopupAcceptButton != null && tm.PopupAcceptButton.activeInHierarchy
                                && tm.buttonText != null)
                                button = tm.buttonText.text;
                        }
                        catch { }
                        break;
                    }
                }

                bool active = !string.IsNullOrEmpty(text)
                    && text.IndexOf("<noframe>", StringComparison.Ordinal) < 0
                    && text.IndexOf("<no message>", StringComparison.Ordinal) < 0
                    && text.IndexOf("<nohighlight>", StringComparison.Ordinal) < 0;

                // The step joins the SIGNATURE, not the decoration: two consecutive beats can carry
                // the same sentence and the client should still be told the tutorial moved on.
                string step = "";
                try
                {
                    var cs = TutorialManager.currentStep;
                    if (cs != null) step = cs.GetType().Name + "#" + cs.step;
                }
                catch { }

                string sig = active ? (step + "|" + text + "|" + (button ?? "")) : "off";
                if (sig == _sig && !_resend) return;
                bool first = _sig.Length == 0 || _sig == "off";
                _sig = sig;
                _resend = false;

                var j = new JsonWriter();
                j.BeginObject().Member("type", Protocol.TypeTutorial).Member("active", active);
                if (active)
                {
                    j.Member("text", text).Member("step", step);
                    if (!string.IsNullOrEmpty(button)) j.Member("button", button);
                }
                j.EndObject();
                server.Publish(Protocol.Frame(j.ToString()));
                if (active && first) Log("[tutorial] mirroring guide steps to Raves");
            }
            catch (Exception e) { Log("tutorial poll: " + e.Message); }
        }
    }
}
