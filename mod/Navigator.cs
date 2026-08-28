using System;
using XRL;                       // The
using XRL.World;                 // Cell, GameObject, Zone
using XRL.World.Capabilities;    // AutoAct
using XRL.UI;                    // ObjectFinder — the nearby list Qud itself draws
using Qud.API;                   // EquipmentAPI.TwiddleObject
using ConsoleLib.Console;        // Keyboard.PushCommand

namespace RavesOfQud
{
    /// <summary>
    /// Qud's click-to-travel: walk the player to a cell in the current zone.
    ///
    /// LITERALLY QUD'S OWN CLICK HANDLER. `XRLCore`'s "AdventureMouseForceMove" case does exactly
    /// this and nothing else:
    ///
    ///     if (cell.PathDistanceTo(currentCell) != 1) {
    ///         PlayerAvoid.Clear();
    ///         AutoAct.Setting = "M" + cell.X + "," + cell.Y;   // the TARGET is in the setting
    ///     } else { ...single step in that direction... }
    ///
    /// The target rides in the setting string and AutoAct walks it; there is no Brain goal in it.
    /// This code used to push `Brain.PushGoal(new MoveTo(cell))` plus a bare "M", which also walks
    /// -- and walks at a THIRD of the speed, because a Brain goal re-runs the actor's AI every
    /// turn where AutoAct just takes its next path step. Measured over the same route: 4.2 steps/s
    /// through the goal, 12.3 steps/s for Qud's own click. That gap was mistaken for bridge
    /// overhead; the mod's whole per-turn publish is ~15ms of a 238ms step.
    ///
    /// THREADING — AND WHY NOT gameQueue. Mutating game state needs the turn thread, and the
    /// obvious channel is `GameManager.Instance.gameQueue.queueSingletonTask` (what
    /// InventoryExporter.Twiddle uses). It works, and it is WRONG HERE: that queue is drained by
    /// Unity's main loop, which stops while the window is in the background. Raves in front means
    /// Qud in the background, which is the normal case for every click the player makes — so the
    /// task simply never ran. Measured, with Qud unfocused: no log line at all for 8s, then the
    /// walk happening the moment Qud came forward. It never looked broken from outside, because a
    /// TCP write to a mod whose queue is parked still succeeds.
    ///
    /// So the target is PARKED here and applied from `BeginTakeActionEvent` (Bridge.TickAction ->
    /// Pump), which fires on the TURN thread and keeps firing unfocused. The kick that gets a turn
    /// started is `Keyboard.PushCommand`, the same carrier the arrow keys already use from this
    /// same socket thread — the one input path proven to reach a backgrounded Qud.
    /// </summary>
    public static class Navigator
    {
        private static void Log(string s) { try { Bridge.Server?.Log(s); } catch { } }

        // The parked target. Written from the socket thread, read + cleared on the turn thread;
        // an int pair behind a lock rather than a Cell, so nothing hands a game object across
        // threads. -1 = nothing pending.
        private static readonly object _lock = new object();
        private static int _wantX = -1, _wantY = -1;
        // The parked EDGE order: a cardinal, plus how many turns it may take before we give up on
        // it. Same threading story as _wantX/_wantY -- written from the socket thread, read and
        // cleared on the turn thread.
        private static string _edgeDir = null;
        private static bool _edgeWalking;
        private static int _edgeTurns;

        /// <summary>Ask for a walk to zone cell (x,y). Returns immediately: this only parks the
        /// target and wakes the turn loop. Whether a path exists is Qud's answer and it arrives
        /// later, on the turn thread, so it is logged rather than returned.</summary>
        public static bool MoveToCell(int x, int y)
        {
            lock (_lock) { _wantX = x; _wantY = y; }
            // Wake the parked input loop so a player action begins and Pump gets its turn thread.
            // Unfocused-safe: this is Qud's legacy console queue, which the turn thread drains
            // whatever Unity's main loop is doing.
            Keyboard.PushCommand("CmdWait", null);
            return true;
        }

        /// <summary>Walk to the zone's edge in `dir` and step across it.
        ///
        /// Daniel: "You need to be able to walk off-zone using the mouse."
        ///
        /// Raves draws the neighbouring zones, so clicking into one is the obvious way to ask to go
        /// there -- and it did nothing at all, because a click becomes `moveto` and Qud's travel
        /// (AutoAct "M x,y") only addresses cells in the CURRENT zone. The mod logged "cell 35,30
        /// is outside the zone" and stopped, which is correct for that command and useless as an
        /// answer to the gesture.
        ///
        /// TWO PHASES, because Qud's own edge walk is two things. `AutoAct.Setting = "G" + dir` is
        /// Qud's "move to edge" (what CmdMoveToEdge sets after its direction prompt), and it walks
        /// the player to the boundary and STOPS THERE -- TryFindEdgeStep paths to x=79 / y=0 and no
        /// further. Crossing is a further step in that direction, which is what Qud's own CmdMoveE
        /// does: `The.Player.Move("E")`, the same call the adjacent-step path above already makes.
        ///
        /// So the order is parked, the walk is started once, and every later turn asks the only
        /// question that matters: is the player standing on the edge yet? When they are, one Move
        /// takes them over and the order is done.
        ///
        /// IT GIVES UP. A blocked route, a wall along the whole boundary, an interruption that
        /// cancels the AutoAct -- any of these leave the player somewhere short of the edge, and an
        /// order that waited forever would cross the moment the player later wandered into the
        /// boundary row for their own reasons. EDGE_TURNS is a budget, not a timeout: it counts
        /// turns the player actually took.</summary>
        private const int EDGE_TURNS = 240;

        public static bool MoveToEdge(string dir)
        {
            if (dir != "N" && dir != "S" && dir != "E" && dir != "W")
            { Log("[nav] edge: not a cardinal: " + dir); return false; }
            lock (_lock) { _edgeDir = dir; _edgeWalking = false; _edgeTurns = 0; }
            Keyboard.PushCommand("CmdWait", null);
            return true;
        }

        /// TURN THREAD. The edge order's state machine — see MoveToEdge.
        private static void PumpEdge(GameObject player)
        {
            string dir;
            bool walking;
            lock (_lock)
            {
                if (_edgeDir == null) return;
                dir = _edgeDir;
                walking = _edgeWalking;
                if (++_edgeTurns > EDGE_TURNS)
                {
                    _edgeDir = null;
                    Log("[nav] edge " + dir + ": gave up after " + EDGE_TURNS + " turns");
                    return;
                }
            }
            try
            {
                Cell here = player?.CurrentCell;
                Zone z = player?.CurrentZone;
                if (here == null || z == null) return;
                // AT THE BOUNDARY? Then one step leaves the zone, and Move does the crossing the
                // same way Qud's own CmdMove* does.
                bool atEdge = (dir == "N" && here.Y == 0)
                    || (dir == "S" && here.Y == z.Height - 1)
                    || (dir == "W" && here.X == 0)
                    || (dir == "E" && here.X == z.Width - 1);
                if (atEdge)
                {
                    lock (_lock) { _edgeDir = null; }
                    AutoAct.Setting = null;   // the walk is over; do not let it re-path in the new zone
                    Log("[nav] edge " + dir + ": crossing from " + here.X + "," + here.Y);
                    player.Move(dir);
                    return;
                }
                if (!walking)
                {
                    lock (_lock) { _edgeWalking = true; }
                    The.Core.PlayerAvoid.Clear();
                    AutoAct.Setting = "G" + dir;      // Qud's own move-to-edge
                    Log("[nav] edge " + dir + ": walking from " + here.X + "," + here.Y);
                }
            }
            catch (Exception e) { Log("[nav] edge error: " + e.Message); }
        }

        /// <summary>Right-click a cell: Qud's own context interaction. Socket thread, no parking.
        ///
        /// HANDED STRAIGHT TO QUD, not reimplemented. `XRLCore`'s "AdventureMouseInteract" case takes
        /// the cell's highest render-layer object and either fires its
        /// `DefaultRightClickInventoryAction` or calls `Twiddle(MouseClick: true)` -- the interaction
        /// menu, which is a PopupMessage and therefore already mirrors into Raves. Reimplementing that
        /// here would mean re-deciding "which object" and re-raising the menu off the turn thread,
        /// which is the exact shape that made the item menu answer itself (docs/gotchas.md).
        ///
        /// Unfocused-safe for the reason PushCommand is: `Keyboard.PushCommand` IS
        /// `PushMouseEvent("Command:" + cmd)` -- one queue, one `KeyEvent.Set()`, and the turn thread
        /// wakes on it whatever Unity's main loop is doing. Qud's loop then runs the handler itself,
        /// on its own thread, in its own order.</summary>
        public static bool Interact(int x, int y)
        {
            Keyboard.PushMouseEvent("AdventureMouseInteract", x, y);
            Log("[nav] interact " + x + "," + y);
            return true;
        }

        /// <summary>Activate a row of the Nearby Objects panel: Qud's item menu for THAT object.
        ///
        /// `Qud.UI.NearbyItemsWindow.OnSelect` is two lines and this is both of them:
        ///
        ///     GameManager.Instance.gameQueue.queueSingletonTask("nearby items twiddle",
        ///         () => EquipmentAPI.TwiddleObject(data.go));
        ///
        /// Same queue, same singleton KEY (so a second click cannot stack a second menu), and the
        /// same reason it must be the gameQueue rather than a threadpool -- InventoryExporter.Twiddle
        /// carries the full account of what a twiddle off the turn thread does to itself.
        ///
        /// PLUS A WAKE, which Qud does not need and we do. That queue drains inside
        /// `Keyboard.getvk(..., pumpActions: true)` -- the turn thread's input WAIT -- so it is
        /// pumped when the thread wakes, and nothing about queueing a task wakes it. Qud's own
        /// caller is a click in a focused window, which arrives as input; ours arrives on a socket
        /// while the window is in the background, and the task then sat until something else woke
        /// the loop (measured on `moveto`: nothing for 8s, then everything the moment Qud came
        /// forward). `CmdNone` is the wake: `Keyboard.PushCommand` sets the same KeyEvent the
        /// thread is blocked on, and XRLCore's CmdNone case refreshes the sidebar and takes no
        /// turn. Queue FIRST, then wake, or the pump can run before there is anything to pump.
        ///
        /// The object is resolved from the finder's OWN list, not from the zone: the row exists
        /// because that object is in `ObjectFinder.instance.peekItems()`, so that is where its id
        /// means something. An id that has left the list is stale by definition -- the thing was
        /// picked up, killed or walked away -- and is refused rather than hunted for.</summary>
        public static bool TwiddleNearby(string id)
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.gameQueue == null) { Log("[nav] no gameQueue"); return false; }
            gm.gameQueue.queueSingletonTask("nearby items twiddle", () =>
            {
                try
                {
                    GameObject go = FindNearby(id);
                    if (go == null) { Log("[nav] nearby: no object with id " + id + " in the list"); return; }
                    Log("[nav] nearby twiddle " + go.DisplayNameOnlyStripped);
                    EquipmentAPI.TwiddleObject(go);
                }
                catch (Exception e) { Log("[nav] nearby twiddle error: " + e.Message); }
            });
            Keyboard.PushCommand("CmdNone", null);
            return true;
        }

        /// <summary>The object behind a nearby-list id, from the list itself. Null if it has left.</summary>
        private static GameObject FindNearby(string id)
        {
            if (string.IsNullOrEmpty(id)) return null;
            var finder = ObjectFinder.instance;
            if (finder == null) return null;
            foreach (var item in finder.peekItems())
            {
                GameObject go = item.go;
                if (go != null && go.ID == id) return go;
            }
            return null;
        }

        /// <summary>Apply a parked target. TURN THREAD ONLY — called from BeginTakeAction.</summary>
        public static void Pump(GameObject player)
        {
            PumpEdge(player);
            int x, y;
            lock (_lock)
            {
                if (_wantX < 0) return;
                x = _wantX; y = _wantY;
                _wantX = -1; _wantY = -1;
            }
            try
            {
                if (player == null) { Log("[nav] no player"); return; }
                Zone z = player.CurrentZone;
                if (z == null) { Log("[nav] no zone"); return; }
                if (x < 0 || y < 0 || x >= z.Width || y >= z.Height)
                { Log("[nav] cell " + x + "," + y + " is outside the zone"); return; }

                Cell target = z.GetCell(x, y);
                if (target == null) { Log("[nav] no cell at " + x + "," + y); return; }

                // Clicking where you already stand is a no-op, not a zero-length travel.
                Cell here = player.CurrentCell;
                if (here == null) { Log("[nav] player has no cell"); return; }
                if (here.X == x && here.Y == y)
                { Log("[nav] already on " + x + "," + y); return; }

                if (target.PathDistanceTo(here) == 1)
                {
                    // Adjacent: Qud takes one step rather than starting a travel, so we do too.
                    string dir = here.GetDirectionFromCell(target);
                    if (!string.IsNullOrEmpty(dir) && dir != "." && dir != "?") player.Move(dir);
                    Log("[nav] step " + dir + " to " + x + "," + y);
                    return;
                }
                // The avoid-list is cleared on a fresh travel order (Qud does this here): the cells
                // the player was steering around belonged to the LAST walk.
                The.Core.PlayerAvoid.Clear();
                AutoAct.Setting = "M" + x + "," + y;
                Log("[nav] moveto " + x + "," + y + " from " + here.X + "," + here.Y);
            }
            catch (Exception e) { Log("[nav] moveto error: " + e.Message); }
        }
    }
}
