using System;
using System.IO;
using UnityEngine;
using XRL;                  // The
using Genkit;               // Location2D (NOT XRL.World)
using XRL.World;            // ZoneManager

namespace RavesOfQud
{
    /// <summary>
    /// Exports the world-map panel that the Quests (and Journal) status screens draw beside their
    /// list, as a PNG plus the quest-giver PINS.
    ///
    /// WHY EXPORT THE TEXTURE RATHER THAN RE-RENDER IT: MapScrollerController.RefreshMap builds the
    /// map by walking all 80x25 cells of the "JoppaWorld" zone, rendering each through a RenderEvent
    /// and blitting its recoloured sprite into a 1280x600 texture (16x24 per cell). Reproducing that
    /// means reproducing Qud's whole world-map render — terrain sprite choice, per-cell colour,
    /// exploration state — and keeping it in step forever. The texture Qud already built is exact
    /// and free.
    ///
    /// The texture is private, but the Image it feeds is not: mapImage.sprite.texture IS it, and it
    /// is CPU-readable because RefreshMap constructs it with `new Texture2D(...)` rather than
    /// uploading an opaque GPU resource.
    ///
    /// PINS are recomputed the way QuestsStatusScreen.UpdateViewFromData does: one per distinct
    /// QuestGiverLocationZoneID, positioned by ZoneManager.GetWorldMapLocationForZoneID, titled with
    /// the location name and detailed with the quests there. Same source, same rule.
    /// </summary>
    public static class MapExporter
    {
        public const int CellW = 16;    // RefreshMap's per-cell blit size
        public const int CellH = 24;
        public const int MapW = 80;     // JoppaWorld is 80x25 world-map cells
        public const int MapH = 25;

        public static string Dir => Path.Combine(
            Directory.GetParent(TileExporter.Dir).FullName, "map");

        private static void Log(string s)
        {
            System.Console.WriteLine("[raves] map: " + s);
            try { Bridge.Server?.Log("map: " + s); } catch { }
        }

        /// <summary>UNITY MAIN THREAD, with a map-bearing screen live. Writes a PER-SCREEN PNG.
        ///
        /// NOT one shared file. The Quests and Journal screens own separate MapScrollerControllers
        /// and their textures genuinely DIFFER: RefreshMap dims every cell that isn't in `highlights`,
        /// Quests calls SetHighlights(the quest locations) so most of the world goes dark, and the
        /// Journal calls SetHighlights(null) so nothing dims. Sharing one file drew the Quests'
        /// dimmed map inside the Journal's panel — same world, wrong pixels.</summary>
        /// <param name="which">"quests" or "journal" — WHICH screen's controller to read. Do not
        /// pick by Visible: the status screens are tabs of one StatusScreensScreen, so the Quests
        /// instance still reports visible while the Journal tab is the one on show, and a
        /// first-visible-wins check wrote the Quests map twice and the Journal's never.</param>
        public static void ExportWorldMap(string which)
        {
            try
            {
                MapScrollerController mc = null;
                string dest = null;
                bool wantJournal = !string.IsNullOrEmpty(which)
                    && which.IndexOf("journal", StringComparison.OrdinalIgnoreCase) >= 0;
                // FIND BY COMPONENT, not by `.instance`. JournalStatusScreen's singleton field is
                // null here even though the screen exists — the probe already resolves these screens
                // by component search for the same reason. Falling back to `.instance` alone wrote
                // the Quests map twice and never the Journal's.
                if (wantJournal)
                {
                    dest = "journal_map.png";
                    try
                    {
                        var jrn = UnityEngine.Object.FindObjectOfType<Qud.UI.JournalStatusScreen>();
                        if (jrn != null) mc = jrn.mapController;
                    }
                    catch { }
                }
                else
                {
                    dest = "quests_map.png";
                    try
                    {
                        var quests = UnityEngine.Object.FindObjectOfType<Qud.UI.QuestsStatusScreen>();
                        if (quests != null) mc = quests.mapController;
                    }
                    catch { }
                }
                if (mc == null) { Log("no map controller for '" + which + "'"); return; }
                if (mc.mapImage == null || mc.mapImage.sprite == null)
                { Log("no map image yet — has the screen rendered?"); return; }
                var tex = mc.mapImage.sprite.texture;
                if (tex == null) { Log("map sprite has no texture"); return; }

                Directory.CreateDirectory(Dir);
                byte[] png;
                try { png = tex.EncodeToPNG(); }
                catch (Exception e) { Log("texture not readable: " + e.Message); return; }
                if (png == null || png.Length == 0) { Log("empty PNG"); return; }
                File.WriteAllBytes(Path.Combine(Dir, dest), png);
                Log(string.Format("wrote {0} ({1}x{2}, {3} bytes)", dest, tex.width, tex.height, png.Length));
            }
            catch (Exception e) { Log("failed: " + e); }
        }

        /// <summary>The PLAYER's world-map cell, as the default view centre.
        ///
        /// With nothing selected, Qud's map is not sitting at the map's middle — it shows the
        /// player's own region (Joppa's salt marsh for a Joppa start). Centring on the texture's
        /// centre instead put Raves several parasangs away looking at forest.</summary>
        public static string PlacesPath => System.IO.Path.Combine(
            Directory.GetParent(TileExporter.Dir).FullName, "places.json");

        /// <summary>
        /// PLACES THE PLAYER HAS ACTUALLY BEEN, which is a different list from the journal's.
        ///
        /// Qud files a map note when the game TELLS you about somewhere — gossip, a water ritual, a
        /// quest — so a character can have slept in Joppa and stood in Red Rock with neither in the
        /// journal. Daniel: "I'm at Red Rock, but for some reason, It's not discovered, and I can't
        /// add it as a beacon. Same with Joppa. I'd like to be able to return to Joppa by following
        /// the beacon."
        ///
        /// The game's own record is ZoneManager.VisitedTime, a zone id -> when. Its KEYS are the
        /// travel log; the parasang is in the id. Two earlier guesses were wrong and are worth
        /// naming: the world map's `explored` flag covers most of Qud whether you have been there or
        /// not, and the world-map CELLS' objects come back under blueprint names (TerrainHills,
        /// TerrainSixDayStilt) rather than display names. GetTerrainObjectForZone gives the same
        /// object the status bar names, so "Red Rock" comes out as Red Rock.
        /// </summary>
        public static void ExportPlaces()
        {
            try
            {
                var j = new JsonWriter();
                j.BeginObject();
                InventoryExporter.WritePalette(j);
                j.Name("places").BeginArray();
                var zm = The.Game?.ZoneManager;
                var seen = new System.Collections.Generic.HashSet<string>();
                if (zm != null)
                {
                    foreach (var id in zm.VisitedTime.Keys)
                    {
                        if (string.IsNullOrEmpty(id)) continue;
                        var parts = id.Split('.');
                        // "JoppaWorld.11.20.1.2.10" — world, parasang x/y, zone x/y, stratum. Named
                        // worlds with no parasang (the tutorial's, "NorthSheva") simply skip.
                        if (parts.Length < 3) continue;
                        if (!int.TryParse(parts[1], out int wx) || !int.TryParse(parts[2], out int wy)) continue;
                        string key = parts[0] + "." + wx + "." + wy;
                        if (!seen.Add(key)) continue;   // one row per PARASANG, not per zone under it
                        XRL.World.GameObject t = null;
                        try { t = ZoneManager.GetTerrainObjectForZone(wx, wy, parts[0]); } catch { }
                        if (t == null) continue;
                        j.BeginObject()
                            .Member("world", parts[0])
                            .Member("mx", wx).Member("my", wy)
                            .Member("name", t.DisplayNameOnly ?? "");
                        try
                        {
                            var r = t.GetPart<XRL.World.Parts.Render>();
                            if (r != null)
                            {
                                string tile = r.Tile ?? "";
                                if (tile.Length > 0) TileExporter.Ensure(tile);
                                j.Member("tile", tile)
                                 .Member("color", r.ColorString ?? "")
                                 .Member("tilecolor", r.TileColor ?? "")
                                 .Member("detail", r.DetailColor ?? "");
                            }
                        }
                        catch { }
                        j.EndObject();
                    }
                }
                j.EndArray();
                WritePlayerPos(j);
                j.EndObject();
                File.WriteAllText(PlacesPath, j.ToString());
            }
            catch (Exception e) { Log("places export: " + e.Message); }
        }

        public static void WritePlayerPos(JsonWriter j)
        {
            try
            {
                var p = The.Player;
                if (p == null) return;
                var z = p.CurrentZone;
                if (z == null) return;
                // A zone id carries its world-map parasang; ask the manager rather than parse it.
                Location2D loc = null;
                try { loc = ZoneManager.GetWorldMapLocationForZoneID(z.ZoneID); } catch { }
                if (loc == null) return;
                j.Name("player").BeginObject().Member("x", loc.X).Member("y", loc.Y).EndObject();
            }
            catch (Exception e) { Log("player pos: " + e.Message); }
        }

        /// <summary>Quest-giver pins, as UpdateViewFromData computes them. Safe off the UI thread —
        /// it only reads quest + zone data.</summary>
        public static void WritePins(JsonWriter j)
        {
            j.Name("pins").BeginArray();
            try
            {
                // ONE PIN PER ZONE, listing every quest there — UpdateViewFromData dedupes by
                // QuestGiverLocationZoneID and then builds `details` from ALL quests sharing that
                // location. Keeping only the first quest's name would silently hide the others
                // whenever two quest givers stand in the same place (which Joppa's two do).
                var order = new System.Collections.Generic.List<string>();
                var byZone = new System.Collections.Generic.Dictionary<string, System.Collections.Generic.List<XRL.World.Quest>>();
                foreach (var q in Qud.API.QuestsAPI.allQuests())
                {
                    if (q == null || q.Finished) continue;
                    string zid = q.QuestGiverLocationZoneID;
                    if (string.IsNullOrEmpty(zid)) continue;
                    if (!byZone.ContainsKey(zid))
                    {
                        byZone[zid] = new System.Collections.Generic.List<XRL.World.Quest>();
                        order.Add(zid);
                    }
                    byZone[zid].Add(q);
                }
                foreach (var zid in order)
                {
                    var list = byZone[zid];
                    Location2D loc = null;
                    try { loc = ZoneManager.GetWorldMapLocationForZoneID(zid); } catch { }
                    if (loc == null) loc = Location2D.Get(0, 0);
                    j.BeginObject()
                     .Member("x", loc.X).Member("y", loc.Y)
                     .Member("title", list[0].QuestGiverLocationName ?? "");
                    j.Name("quests").BeginArray();
                    foreach (var q in list)
                        j.Value(ConsoleLib.Console.ColorUtility.StripFormatting(q.DisplayName ?? ""));
                    j.EndArray();
                    j.EndObject();
                }
            }
            catch (Exception e) { Log("pins: " + e.Message); }
            j.EndArray();
        }
    }
}
