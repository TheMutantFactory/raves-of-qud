using System;
using System.IO;
using System.Text;
using XRL.UI;

namespace RavesOfQud
{
    /// <summary>
    /// Export the CONTROL MAPPING data — categories, commands and the player's CURRENT
    /// keyboard bindings — to <c>bindings.json</c>, for Raves' Control Mapping screen.
    ///
    /// Mirrors KeybindsScreen.QueryKeybinds() verbatim: CategoriesInOrder →
    /// CommandsByCategory, the same per-command include condition, and
    /// CommandBindingManager.GetCommandBindings for QUD'S OWN formatted bind strings
    /// ("Shift+↑", "Control+Enter", …) — up to four per command. Data-only; re-run
    /// via the bridge "export" command so a rebind in Qud refreshes Raves.
    /// </summary>
    public static class BindingsExporter
    {
        public static void ReExport()
        {
            try { Export(); }
            catch (Exception e) { System.Console.WriteLine("[raves] bindings export failed: " + e.Message); }
        }

        private static string Root
        {
            get
            {
                string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                return Path.Combine(home, "Library", "Application Support", "RavesOfQud");
            }
        }

        /// <summary>
        /// The DEFAULT key names for a command, straight out of Qud's Commands.xml
        /// (&lt;keyboardBind Key="numpad1"/&gt;), as "numpad1" or "shift+leftArrow".
        ///
        /// WHY THIS EXISTS. GetCommandBindings returns Qud's DISPLAY strings, and those are
        /// lossy in exactly one place that matters: a numpad digit and a digit-row digit both
        /// print as "1". Qud tells them apart because they are different controls -- numpad 1
        /// moves southwest, digit-row 1 fires ability 1 -- but Raves, reading only the display
        /// string, had to guess, matched a bare digit against BOTH, and handed the digit row to
        /// whichever command the file listed first. That was CmdMoveSW, so every ability on the
        /// bar was unreachable and the number keys walked the player diagonally instead.
        /// Daniel: "The camera change keys are overriding the abilities. I'm trying to use
        /// flaming ray, but the Raves just tries to Chat with the Dawngliders."
        ///
        /// Defaults only, and deliberately: a REBOUND command's serialized paths live in the
        /// keymap, and a bind Raves cannot spell unambiguously is better left for the display
        /// string to handle as before than guessed at from a second, staler source.
        /// </summary>
        private static System.Collections.Generic.Dictionary<string, System.Collections.Generic.List<string>> _defaults;
        private static System.Collections.Generic.Dictionary<string, string> _layers;

        private static System.Collections.Generic.List<string> DefaultKeys(string id)
        {
            if (_defaults == null)
            {
                _defaults = new System.Collections.Generic.Dictionary<string, System.Collections.Generic.List<string>>();
                _layers = new System.Collections.Generic.Dictionary<string, string>();
                try
                {
                    var doc = new System.Xml.XmlDocument();
                    doc.Load(XRL.DataManager.FilePath("Commands.xml"));
                    foreach (System.Xml.XmlNode cmd in doc.SelectNodes("//command"))
                    {
                        string cid = cmd.Attributes?["ID"]?.Value;
                        if (string.IsNullOrEmpty(cid)) continue;
                        var keys = new System.Collections.Generic.List<string>();
                        foreach (System.Xml.XmlNode kb in cmd.SelectNodes("keyboardBind"))
                        {
                            string k = kb.Attributes?["Key"]?.Value;
                            if (string.IsNullOrEmpty(k)) continue;
                            string m = kb.Attributes?["Modifier"]?.Value;
                            keys.Add(string.IsNullOrEmpty(m) ? k : m + "+" + k);
                        }
                        _defaults[cid] = keys;
                        _layers[cid] = cmd.Attributes?["Layer"]?.Value ?? "";
                    }
                }
                catch (Exception e)
                {
                    System.Console.WriteLine("[raves] Commands.xml defaults unavailable: " + e.Message);
                }
            }
            System.Collections.Generic.List<string> outv;
            if (id != null && _defaults.TryGetValue(id, out outv) && outv != null) return outv;
            return new System.Collections.Generic.List<string>();
        }

        /// The Qud UI layer a command belongs to ("Adventure", "Targeting", "Menus", ...), from the
        /// same Commands.xml pass as DefaultKeys. "" when unknown.
        private static string DefaultLayer(string id)
        {
            DefaultKeys(id);          // ensures the tables are loaded
            string v;
            if (_layers != null && id != null && _layers.TryGetValue(id, out v)) return v ?? "";
            return "";
        }

        private static void Export()
        {
            if (CommandBindingManager.CategoriesInOrder == null) return;   // not initialized yet

            var j = new JsonWriter();
            j.BeginObject();
            j.Name("categories").BeginArray();
            foreach (string cat in CommandBindingManager.CategoriesInOrder)
            {
                j.BeginObject();
                j.Member("name", cat ?? "");
                j.Name("commands").BeginArray();
                System.Collections.Generic.List<GameCommand> cmds;
                if (CommandBindingManager.CommandsByCategory != null
                    && CommandBindingManager.CommandsByCategory.TryGetValue(cat, out cmds) && cmds != null)
                {
                    foreach (GameCommand c in cmds)
                    {
                        if (c == null) continue;
                        // the screen's own include condition (keyboard): Button-type
                        // commands except GamepadAlt — the add sits INSIDE the negated
                        // if in the decompile, easy to read backwards
                        if (!(c.Type == UnityEngine.InputSystem.InputActionType.Button && c.ID != "GamepadAlt"))
                            continue;
                        string b1, b2, b3, b4;
                        try
                        {
                            CommandBindingManager.GetCommandBindings(c.ID,
                                ControlManager.InputDeviceType.Keyboard, out b1, out b2, out b3, out b4);
                        }
                        catch { b1 = b2 = b3 = b4 = ""; }
                        j.BeginObject();
                        j.Member("id", c.ID ?? "").Member("display", c.DisplayText ?? "");
                        j.Member("b1", b1 ?? "").Member("b2", b2 ?? "")
                         .Member("b3", b3 ?? "").Member("b4", b4 ?? "");
                        // ...and the same binds spelled UNAMBIGUOUSLY. See DefaultKeys.
                        j.Name("keys").BeginArray();
                        foreach (string k in DefaultKeys(c.ID)) j.Value(k);
                        j.EndArray();
                        // ...and WHEN the bind applies. Qud's second discriminator: CmdAltFire1
                        // and CmdAbility1 both hold digit-row 1, and Qud tells them apart by layer
                        // -- Targeting only while the targeting UI is up, Adventure while walking
                        // around. Without this, disambiguating numpad from row just moves the
                        // collision one command along.
                        j.Member("layer", DefaultLayer(c.ID));
                        j.EndObject();
                    }
                }
                j.EndArray();
                j.EndObject();
            }
            j.EndArray();
            j.EndObject();

            Directory.CreateDirectory(Root);
            File.WriteAllText(Path.Combine(Root, "bindings.json"), j.ToString(), new UTF8Encoding(false));
        }
    }
}
