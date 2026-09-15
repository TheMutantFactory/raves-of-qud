using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using XRL;                       // The
using XRL.World;                 // Zone, Cell, GameObject, ZoneManager
using XRL.World.Parts;           // Render, Physics, LightSource

namespace RavesOfQud
{
    /// <summary>
    /// The world BAKE for 2Caves2Qud's overland mode (its docs/overland.md): build zones by id
    /// without moving the player, and write each as a COMPACT chunk file.
    ///
    /// WHY NOT THE SNAPSHOT: ZoneSnapshot serialises the ACTIVE zone for a viewer, ~800 KB a
    /// zone with per-turn state (visibility, minimap, the player's panels). A bake wants the
    /// static world for 18,000 zones: what stands where, what it looks like, what it does to a
    /// kart. So the chunk is a PALETTE of distinct objects (name, tile, colours, wall / solid /
    /// liquid / creature flags, light radius) and per cell: the painted ground's palette index,
    /// and the standing objects as [x, y, palette]. ~30 KB a zone.
    ///
    /// WHY GetZone AND NOT zonetp: `zonetp` makes the target the ACTIVE zone (autosave, the
    /// player moved, the old zone suspended). ZoneManager.GetZone builds a zone into the cache
    /// and leaves the player where they are. The zone is released afterwards (SuspendZone by
    /// reflection, so an API rename degrades to "kept in cache" rather than a compile failure).
    ///
    /// GROUND: Qud's painted ground lives in the Cell's Paint* fields (PaintTile, PaintTileColor,
    /// PaintColorString, PaintDetailColor, PaintRenderString), which the zone builders set. Read
    /// by reflection for the same reason; if absent, fall back to ZoneSnapshot.ResolveGround
    /// (Cell.Render), which only answers on an UNOCCUPIED cell.
    ///
    /// LIGHT: a zone that is not active has no light map (it is a render-frame artifact of the
    /// active zone), so no per-cell light is written. The palette carries `lightRadius` for a
    /// lit LightSource, and daylight is the clock's job on the other side.
    ///
    /// The command: {"name":"bake","zones":"JoppaWorld.11.22.1.1.10,..."} — a comma list; or
    /// {"name":"bake","wx":"11","wy":"22"} for one parasang's nine surface zones. Files land in
    /// <RavesOfQud>/chunks/<gameId>/<zoneId>.json, plus world.json (the game id and name) and
    /// the per-request "[bake]" log lines. A file's presence is the caller's confirmation.
    /// </summary>
    public static class BakeExporter
    {
        public static string Dir => Path.Combine(Directory.GetParent(TileExporter.Dir).FullName, "chunks");

        private static void Log(string s)
        {
            try { System.Console.WriteLine("[raves] bake: " + s); } catch { }
            try { Bridge.Server?.Log("[bake] " + s); } catch { }
        }

        public static void Run(Dictionary<string, string> f, GameObject player)
        {
            var ids = new List<string>();
            f.TryGetValue("zones", out string zones);
            if (!string.IsNullOrEmpty(zones))
            {
                foreach (var s in zones.Split(','))
                    if (s.Trim().Length > 0) ids.Add(s.Trim());
            }
            else
            {
                f.TryGetValue("wx", out string sx);
                f.TryGetValue("wy", out string sy);
                f.TryGetValue("z", out string sz);
                int wx = MapEditorDriver.ParseInt(sx), wy = MapEditorDriver.ParseInt(sy);
                int z = string.IsNullOrEmpty(sz) ? 10 : MapEditorDriver.ParseInt(sz);
                for (int zy = 0; zy < 3; zy++)
                    for (int zx = 0; zx < 3; zx++)
                        ids.Add("JoppaWorld." + wx + "." + wy + "." + zx + "." + zy + "." + z);
            }
            if (ids.Count == 0) { Log("nothing to bake"); return; }

            string gameId = The.Game != null ? (The.Game.GameID ?? "") : "";
            if (gameId.Length == 0) { Log("no game running"); return; }
            string dir = Path.Combine(Dir, gameId);
            Directory.CreateDirectory(dir);
            WriteWorldManifest(dir, gameId);

            foreach (string id in ids)
            {
                var sw = Stopwatch.StartNew();
                try
                {
                    string path = Path.Combine(dir, id + ".json");
                    Zone z = The.ZoneManager.GetZone(id);
                    if (z == null) { Log(id + " no zone"); continue; }
                    int objs = WriteChunk(z, path);
                    long bytes = new FileInfo(path).Length;
                    bool active = The.ActiveZone == z;
                    if (!active) Release(z);
                    Log(id + " ok " + sw.ElapsedMilliseconds + "ms " + bytes + "B objs=" + objs + (active ? " (active zone, kept)" : ""));
                }
                catch (Exception e)
                {
                    Log(id + " FAILED " + sw.ElapsedMilliseconds + "ms " + e.GetType().Name + ": " + e.Message);
                }
            }
        }

        private static void WriteWorldManifest(string dir, string gameId)
        {
            try
            {
                var j = new JsonWriter();
                j.BeginObject()
                    .Member("gameId", gameId)
                    .Member("world", "JoppaWorld")
                    .Member("build", Protocol.Build)
                    .Member("format", 1)
                    .Member("cellW", 80).Member("cellH", 25).Member("parasang", 3)
                    .Member("bakedAt", DateTime.UtcNow.ToString("o"));
                try { j.Member("player", The.Player != null ? (The.Player.DisplayNameOnlyDirect ?? "") : ""); } catch { }
                j.EndObject();
                File.WriteAllText(Path.Combine(dir, "world.json"), j.ToString());
            }
            catch (Exception e) { Log("manifest: " + e.Message); }
        }

        // --- the chunk ----------------------------------------------------------------

        private sealed class Palette
        {
            public readonly List<string[]> Entries = new List<string[]>();   // the JSON of each entry's key
            public readonly List<string> Json = new List<string>();
            private readonly Dictionary<string, int> _index = new Dictionary<string, int>();

            public int Add(string key, string json)
            {
                if (_index.TryGetValue(key, out int i)) return i;
                i = Json.Count;
                _index[key] = i;
                Json.Add(json);
                return i;
            }
        }

        private static string Entry(string name, string tile, string color, string tilecolor, string detail,
            bool wall, bool solid, bool liquid, bool creature, bool ground, int lightRadius, int layer)
        {
            var j = new JsonWriter();
            j.BeginObject()
                .Member("name", name ?? "")
                .Member("tile", tile ?? "")
                .Member("color", color ?? "")
                .Member("tilecolor", tilecolor ?? "")
                .Member("detail", detail ?? "")
                .Member("wall", wall)
                .Member("solid", solid)
                .Member("liquid", liquid)
                .Member("creature", creature)
                .Member("ground", ground)
                .Member("layer", layer);
            if (lightRadius > 0) j.Member("lightRadius", lightRadius);
            j.EndObject();
            return j.ToString();
        }

        /// Writes the chunk; returns the number of standing objects written.
        private static int WriteChunk(Zone z, string path)
        {
            int w = z.Width, h = z.Height;
            var pal = new Palette();
            var ground = new int[w * h];
            var objs = new List<int[]>();
            for (int i = 0; i < ground.Length; i++) ground[i] = -1;

            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    Cell c = z.GetCell(x, y);
                    if (c == null) continue;
                    int gi = GroundIndex(c, pal);
                    if (gi >= 0) ground[y * w + x] = gi;
                    var objects = c.GetObjects();
                    for (int oi = 0; oi < objects.Count; oi++)
                    {
                        GameObject go = objects[oi];
                        Render r = go.GetPart<Render>();
                        if (r == null || !r.Visible) continue;
                        bool painted;
                        string tile = ZoneSnapshot.ResolvedTile(go, r, out painted);
                        string glyph = ZoneSnapshot.ResolvedGlyph(r);
                        if (tile.Length == 0 && glyph.Length > 0) tile = "Text/" + (int)glyph[0] + ".bmp";
                        if (tile.Length == 0) continue;
                        Physics phys = go.GetPart<Physics>();
                        LightSource light = go.GetPart<LightSource>();
                        bool liquid = false;
                        try { liquid = go.LiquidVolume != null; } catch { }
                        int radius = 0;
                        try { if (light != null && light.Lit) radius = light.Radius; } catch { }
                        string name = go.Blueprint ?? "";
                        string color = r.ColorString ?? "", tilecolor = r.TileColor ?? "", detail = r.DetailColor ?? "";
                        string key = name + "|" + tile + "|" + color + "|" + tilecolor + "|" + detail + "|" + radius;
                        int pi = pal.Add(key, Entry(name, tile, color, tilecolor, detail,
                            go.IsWall(), phys != null && phys.Solid, liquid, go.IsCreature, false, radius, r.RenderLayer));
                        objs.Add(new[] { x, y, pi });
                    }
                }
            }

            var sb = new System.Text.StringBuilder(64 * 1024);
            sb.Append("{\"id\":").Append(Quote(z.ZoneID ?? ""))
              .Append(",\"wx\":").Append(z.wX).Append(",\"wy\":").Append(z.wY)
              .Append(",\"zx\":").Append(z.X).Append(",\"zy\":").Append(z.Y).Append(",\"z\":").Append(z.Z)
              .Append(",\"w\":").Append(w).Append(",\"h\":").Append(h);
            try { sb.Append(",\"name\":").Append(Quote(z.DisplayName ?? "")); } catch { }
            sb.Append(",\"palette\":[");
            for (int i = 0; i < pal.Json.Count; i++) { if (i > 0) sb.Append(','); sb.Append(pal.Json[i]); }
            sb.Append("],\"ground\":[");
            for (int i = 0; i < ground.Length; i++) { if (i > 0) sb.Append(','); sb.Append(ground[i]); }
            sb.Append("],\"objs\":[");
            for (int i = 0; i < objs.Count; i++)
            {
                if (i > 0) sb.Append(',');
                sb.Append('[').Append(objs[i][0]).Append(',').Append(objs[i][1]).Append(',').Append(objs[i][2]).Append(']');
            }
            sb.Append("],\"light\":[]}");
            string tmp = path + ".tmp";
            File.WriteAllText(tmp, sb.ToString());
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
            return objs.Count;
        }

        private static string Quote(string s)
        {
            var j = new JsonWriter();
            j.Value(s);
            return j.ToString();
        }

        // --- painted ground ------------------------------------------------------------

        /// The painted ground's palette index, -1 when the cell has no paint. Cell.PaintTile /
        /// PaintColorString / PaintDetailColor / PaintTileColor are public fields (decompiled
        /// 2026-09-15, game 2.0.4) — the same values Cell.Render composites under an
        /// unoccupied cell, but readable under an occupied one too.
        private static int GroundIndex(Cell c, Palette pal)
        {
            string tile = c.PaintTile ?? "";
            if (tile.Length == 0) return -1;
            string color = c.PaintColorString ?? "", tilecolor = c.PaintTileColor ?? "", detail = c.PaintDetailColor ?? "";
            string key = "[painted ground]|" + tile + "|" + color + "|" + tilecolor + "|" + detail + "|0";
            return pal.Add(key, Entry("[painted ground]", tile, color, tilecolor, detail, false, false, false, false, true, 0, 0));
        }

        // --- release ----------------------------------------------------------------

        private static MethodInfo _suspend;
        private static bool _suspendLooked;

        /// Let the zone go once written so a long bake does not hold 18,000 zones in memory.
        /// Qud's own name for "cache to disk and drop" is SuspendZone; found by reflection so a
        /// rename costs one log line, not the build.
        private static void Release(Zone z)
        {
            try
            {
                if (!_suspendLooked)
                {
                    _suspendLooked = true;
                    foreach (var m in typeof(ZoneManager).GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance))
                    {
                        if (m.Name != "SuspendZone") continue;
                        var ps = m.GetParameters();
                        if (ps.Length >= 1 && ps[0].ParameterType == typeof(Zone)) { _suspend = m; break; }
                    }
                    Log("release: " + (_suspend != null ? "ZoneManager.SuspendZone(" + _suspend.GetParameters().Length + " args)" : "no SuspendZone; zones stay cached"));
                }
                if (_suspend == null) return;
                var args = new object[_suspend.GetParameters().Length];
                args[0] = z;
                for (int i = 1; i < args.Length; i++)
                {
                    var p = _suspend.GetParameters()[i];
                    args[i] = p.HasDefaultValue ? p.DefaultValue : (p.ParameterType.IsValueType ? Activator.CreateInstance(p.ParameterType) : null);
                }
                _suspend.Invoke(The.ZoneManager, args);
            }
            catch (Exception e) { Log("release " + z.ZoneID + ": " + e.Message); }
        }
    }
}
