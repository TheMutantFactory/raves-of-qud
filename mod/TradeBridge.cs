using System;
using System.Collections.Generic;
using Qud.UI;               // TradeScreen, TradeLineData
using XRL;                  // GameManager, The
using XRL.UI;               // TradeUI, TradeEntry
using XRL.World;            // GameObject

namespace RavesOfQud
{
    /// <summary>
    /// Mirrors Qud's TRADE SCREEN — the two-column buy/sell board — to Raves, and applies the
    /// viewer's selections back.
    ///
    /// Daniel: "We need to implement the trading menu. There's a dromad in joppa if you need a
    /// quick way of finding someone."
    ///
    /// THREADING is the popup story again: TradeScreen is a SingletonWindowBase whose show() parks
    /// the turn thread on a Task, while the UI thread keeps drawing it and draining uiQueue. So the
    /// mirror lives on PopupBridge's watcher, like every other screen that blocks a turn.
    ///
    /// WHAT IS SENT. Qud has already done the hard part: `listItems[side]` is the screen's own
    /// rendered row list -- items, category headers, their collapse state and indentation, in
    /// display order -- so Raves mirrors THAT rather than re-deriving a layout from the raw
    /// inventories. Two side effects of taking Qud's list: the sort mode and the category grouping
    /// are Qud's, and a change either of us makes shows up in both.
    ///
    /// PRICES come from TradeUI.GetValue/FormatPrice with the screen's own CostMultiple, which is
    /// what the trader's ego and your Ego actually settle on. Totals and the weight columns are
    /// read after UpdateTotals, and the difference is TradeUI.CalculateTrade -- the same number the
    /// Offer button acts on, so what Raves prints and what Qud charges cannot drift apart.
    ///
    /// SELECTION IS AN INDEX, not an object. NumberSelected is indexed by ObjectIndex[go] within
    /// ObjectSide[go], so that pair IS the row's identity on both sides of the wire and no game
    /// object crosses a thread.
    /// </summary>
    public static class TradeBridge
    {
        private static bool _active;
        private static string _sig = "";
        private static volatile bool _resend;

        public static void Resend() { _resend = true; }

        private static void Log(string s) { try { Bridge.Server?.Log(s); } catch { } }

        private static TradeScreen Screen
        {
            get
            {
                try
                {
                    var s = SingletonWindowBase<TradeScreen>.instance;
                    return (s != null && s.Visible) ? s : null;
                }
                catch { return null; }
            }
        }

        /// UI THREAD. Publish the board whenever it changes.
        public static void Poll(BridgeServer server)
        {
            try
            {
                if (server == null || server.ClientCount == 0) return;
                var sc = Screen;
                bool on = sc != null;
                bool resend = _resend;
                _resend = false;
                if (!on)
                {
                    if (_active || resend)
                    {
                        _active = false;
                        _sig = "";
                        var jc = new JsonWriter();
                        jc.BeginObject().Member("type", Protocol.TypeTrade).Member("active", false).EndObject();
                        try { server.Publish(Protocol.Frame(jc.ToString())); } catch { }
                    }
                    return;
                }

                // Totals are recomputed by the screen itself on every change; ask for them rather
                // than adding them up here, or Raves' arithmetic becomes a second opinion.
                try { TradeUI.UpdateTotals(sc.Totals, sc.Weight, sc.tradeEntries, TradeScreen.NumberSelected); }
                catch { }

                var j = new JsonWriter();
                j.BeginObject().Member("type", Protocol.TypeTrade).Member("active", true);
                j.Member("trader", TradeScreen.Trader?.DisplayName ?? "");
                // Qud's right-hand column is headed with the PLAYER'S NAME, not "You" -- it is a
                // board with two named parties on it.
                j.Member("you", The.Player?.DisplayName ?? "");
                j.Member("verb", TradeScreen.TradeScreenVerb ?? "trade");
                j.Member("mult", TradeScreen.CostMultiple.ToString("0.###"));
                int diff = 0;
                try { diff = TradeUI.CalculateTrade(sc.Totals[0], sc.Totals[1]); } catch { }
                j.Member("difference", diff);
                j.Member("drams", The.Player?.GetFreeDrams() ?? 0);
                // BOTH PURSES. Qud shows the TRADER's free drams on the left of the totals band and
                // yours on the right; only yours was being drawn.
                j.Member("traderPurse", "{{W|$" + (TradeScreen.Trader?.GetFreeDrams() ?? 0) + "}}");
                try
                {
                    // ...and the weight is what you will carry AFTER the trade, water included:
                    // carried + theirs - yours - the water this costs. Sending the CURRENT weight,
                    // as this did, prints a number that never moves while you shop.
                    int carried = The.Player.GetCarriedWeight();
                    int maxc = The.Player.GetMaxCarriedWeight();
                    // Water's per-dram weight WITHOUT LiquidVolume.GetLiquid, whose only overload
                    // takes a ReadOnlySpan<char> that this mod's reference assemblies cannot
                    // resolve. LiquidWater does not override BaseLiquid.Weight, so constructing one
                    // reads the same 0.25 Qud multiplies by.
                    int water = (int)(new XRL.Liquids.LiquidWater().Weight
                        * (double)TradeUI.CalculateTrade(sc.Totals[0], sc.Totals[1]));
                    int after = Math.Max(0, carried + sc.Weight[0] - sc.Weight[1] - water);
                    string tone = (after > maxc) ? "R" : "K";   // Qud reddens an overweight figure
                    j.Member("playerPurse", "{{W|$" + (The.Player?.GetFreeDrams() ?? 0) + "}} | {{"
                        + tone + "|" + after + "/" + maxc + " lbs.}}");
                }
                catch { j.Member("playerPurse", ""); }
                // THE OFFER HOTKEY MARKER, which is what the cell under "TRADE" actually is:
                //     hotkeyText.SetText("{{W|[" + getCommandInputFormatted("CmdTradeOffer") + "]}}")
                // Static, and it names the key. Daniel: "The [0] stays at 0. It does not
                // increment/decrement. It's a hotkey marker." It had been drawn as the trade's
                // DIFFERENCE, which reads as [0] whenever the books balance -- and an O is a zero
                // at a glance in this font, so it looked like a number that was simply stuck.
                try
                {
                    j.Member("offerKey", "{{W|[" + ControlManager.getCommandInputFormatted("CmdTradeOffer") + "]}}");
                }
                catch { j.Member("offerKey", "{{W|[O]}}"); }
                // WHERE THE TILES LIVE, on this frame rather than only on the snapshot. A trade
                // parks the turn thread, so a viewer that attaches DURING one never sees a snapshot
                // and has no tiles directory to draw the board's icons from -- measured exactly
                // that way: every row rendered with an empty icon column.
                j.Member("tilesDir", TileExporter.Dir);
                WriteFilters(j, sc);
                j.Name("sides").BeginArray();
                for (int side = 0; side < 2; side++)
                {
                    j.BeginObject();
                    j.Member("trader", side == 0);
                    j.Member("total", (int)Math.Round(sc.Totals[side]));
                    // QUD'S OWN STRING, markup and all, rather than a number for Raves to format.
                    // UpdateTotals composes these and every part was guessed wrong before: the
                    // totals DO carry CostMultiple (unlike the per-row prices), they are {{B|}}
                    // blue, and the arrow points the way the goods travel.
                    j.Member("totalText", side == 0
                        ? "{{B|" + TradeUI.FormatPrice(sc.Totals[side], TradeScreen.CostMultiple) + " drams \u2192}}"
                        : "{{B|\u2190 " + TradeUI.FormatPrice(sc.Totals[side], TradeScreen.CostMultiple) + " drams}}");
                    j.Member("weight", sc.Weight[side]);
                    j.Name("rows").BeginArray();
                    WriteRows(j, sc, side);
                    j.EndArray();
                    j.EndObject();
                }
                j.EndArray();
                j.EndObject();

                string body = j.ToString();
                // The signature IS the payload: this screen changes only when someone acts on it,
                // and a per-frame diff of the whole board is cheaper than deciding which of a dozen
                // fields counts as a change.
                if (_active && body == _sig && !resend) return;
                _active = true;
                _sig = body;
                try { server.Publish(Protocol.Frame(body)); } catch { }
            }
            catch (Exception e) { Log("[trade] poll failed: " + e.Message); }
        }

        /// The category strip, built the way TradeScreen builds the list it hands filterBar:
        /// "*All" first, then each distinct GO.GetInventoryCategory() across BOTH sides in
        /// first-appearance order. Rebuilding it here from the same source keeps the strip in step
        /// with the board even though the bar itself is a Unity widget we do not read.
        ///
        /// Each cell carries whether it is ON -- enabledCategories is Qud's own list, where "*All"
        /// is a real entry and the resting state -- and an ICON, which stands in with the first item
        /// of that category the way the inventory screen's strip does. Qud draws a fixed per-category
        /// sprite there; those have not been extracted, and this is the same recorded deviation.
        private static void WriteFilters(JsonWriter j, TradeScreen sc)
        {
            j.Name("filters").BeginArray();
            try
            {
                var order = new List<string> { "*All" };
                var icon = new Dictionary<string, GameObject>();
                if (sc.tradeEntries != null)
                {
                    foreach (var list in sc.tradeEntries)
                    {
                        if (list == null) continue;
                        foreach (var e in list)
                        {
                            if (e?.GO == null) continue;
                            string c = e.GO.GetInventoryCategory();
                            if (string.IsNullOrEmpty(c)) continue;
                            if (!order.Contains(c)) { order.Add(c); icon[c] = e.GO; }
                        }
                    }
                }
                var on = sc.filterBar?.enabledCategories;
                foreach (string c in order)
                {
                    j.BeginObject();
                    j.Member("cat", c);
                    j.Member("on", on != null && on.Contains(c));
                    GameObject go;
                    if (icon.TryGetValue(c, out go) && go != null)
                    {
                        try { InventoryExporter.WriteTile(j, go, "Trade"); } catch { }
                    }
                    j.EndObject();
                }
            }
            catch (Exception e) { Log("[trade] filters failed: " + e.Message); }
            j.EndArray();
        }

        private static void WriteRows(JsonWriter j, TradeScreen sc, int side)
        {
            List<TradeLineData> rows = (sc.listItems != null && side < sc.listItems.Length) ? sc.listItems[side] : null;
            if (rows == null) return;
            foreach (var r in rows)
            {
                if (r == null) continue;
                j.BeginObject();
                j.Member("kind", r.type.ToString());
                j.Member("indent", r.indent);
                if (r.type == TradeLineDataType.Category)
                {
                    j.Member("name", r.category ?? "");
                    j.Member("count", r.numberInCategory);
                    j.Member("collapsed", r.collapsed);
                    j.EndObject();
                    continue;
                }
                GameObject go = r.go;
                if (go == null) { j.Member("name", ""); j.EndObject(); continue; }
                j.Member("name", go.DisplayName ?? "");
                j.Member("count", go.Count);
                j.Member("selected", r.numberSelected);
                j.Member("category", r.category ?? "");
                // The row's identity for a selection command — see the class note.
                int idx = -1;
                try { if (sc.ObjectIndex.ContainsKey(go)) idx = sc.ObjectIndex[go]; } catch { }
                j.Member("idx", idx);
                // EXACTLY WHAT THE ROW SHOWS. TradeLine.setData formats
                //     $"{TradeUI.GetValue(go, traderInventory):0.00}"
                // with NO cost multiple -- the multiple belongs to the details line at the bottom,
                // which this board does not draw. Sending FormatPrice(value, CostMultiple) agreed
                // only while the multiple happened to be 1.
                try { j.Member("price", TradeUI.GetValue(go, r.traderInventory).ToString("0.00")); }
                catch { j.Member("price", ""); }
                try { j.Member("currency", go.IsCurrency); } catch { }
                try { j.Member("weight", go.Weight); } catch { }
                try { InventoryExporter.WriteTile(j, go, "Trade"); } catch { }
                j.EndObject();
            }
        }

        /// Apply the viewer's action. Queued on the uiQueue: every one of these touches the live
        /// screen, and the screen belongs to the UI thread.
        public static void Answer(string what, int side, int idx, int n, string cat)
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.uiQueue == null) return;
            gm.uiQueue.queueTask(() =>
            {
                try
                {
                    var sc = Screen;
                    if (sc == null) { Log("[trade] no screen for " + what); return; }
                    if (what == "offer")
                    {
                        sc.HandleMenuOption(TradeScreen.OFFER_TRADE);
                        return;
                    }
                    if (what == "cancel")
                    {
                        // Cancel(), NOT Hide(). Hide() takes the board off the screen and leaves the
                        // TURN THREAD PARKED on menucomplete: Qud stayed in ModernTrade with nothing
                        // drawn, which is worse than not closing at all. Cancel() is the method the
                        // screen's own CancelButton is wired to -- it hides AND completes the task
                        // with OfferStatus.CLOSE, which is the half that lets the game go on.
                        sc.Cancel();
                        return;
                    }
                    if (what == "filter")
                    {
                        // Qud's own toggle, with Qud's own rules: selecting a category adds it and
                        // drops "*All"; selecting it again removes it; emptying the list puts
                        // "*All" back. filtersUpdated then rebuilds the board, so the strip and the
                        // rows cannot disagree.
                        if (sc.filterBar == null || string.IsNullOrEmpty(cat)) return;
                        sc.filterBar.CategorySelected(cat);
                        return;
                    }
                    if (what == "category")
                    {
                        // The collapse flag is Qud's OWN per-side dictionary, and UpdateViewFromData
                        // rebuilds listItems out of it (isCollapsed decides which items are emitted
                        // at all). So flipping it here folds the category away in BOTH views, and
                        // Raves never has to keep a second idea of what is open.
                        if (sc.categoryCollapsed == null || side < 0 || side > 1
                            || string.IsNullOrEmpty(cat)) return;
                        sc.categoryCollapsed[side][cat] = !sc.isCollapsed(side, cat);
                        sc.UpdateViewFromData();
                        return;
                    }
                    if (what == "select")
                    {
                        if (sc.tradeEntries == null || side < 0 || side > 1) return;
                        var list = sc.tradeEntries[side];
                        if (list == null || idx < 0 || idx >= list.Count) return;
                        GameObject go = list[idx]?.GO;
                        if (go == null) { Log("[trade] row " + side + "/" + idx + " has no object"); return; }
                        // setHowManySelected is async because selling something IMPORTANT raises a
                        // confirm first -- which is a safety net worth keeping, and one that already
                        // mirrors into Raves as a popup. Start it and let it run; the board's next
                        // poll publishes whatever it settled on.
                        var _ = sc.setHowManySelected(go, n);
                        sc.UpdateViewFromData();
                        return;
                    }
                }
                catch (Exception e) { Log("[trade] " + what + " failed: " + e.Message); }
            }, 0);
        }
    }
}
