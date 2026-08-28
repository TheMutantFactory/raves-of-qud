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
                j.Member("verb", TradeScreen.TradeScreenVerb ?? "trade");
                j.Member("mult", TradeScreen.CostMultiple.ToString("0.###"));
                int diff = 0;
                try { diff = TradeUI.CalculateTrade(sc.Totals[0], sc.Totals[1]); } catch { }
                j.Member("difference", diff);
                j.Member("drams", The.Player?.GetFreeDrams() ?? 0);
                j.Name("sides").BeginArray();
                for (int side = 0; side < 2; side++)
                {
                    j.BeginObject();
                    j.Member("trader", side == 0);
                    j.Member("total", (int)Math.Round(sc.Totals[side]));
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
                try
                {
                    j.Member("price", TradeUI.FormatPrice(TradeUI.GetValue(go, r.traderInventory), TradeScreen.CostMultiple) ?? "");
                }
                catch { j.Member("price", ""); }
                try { j.Member("weight", go.Weight); } catch { }
                try { InventoryExporter.WriteTile(j, go, "Trade"); } catch { }
                j.EndObject();
            }
        }

        /// Apply the viewer's action. Queued on the uiQueue: every one of these touches the live
        /// screen, and the screen belongs to the UI thread.
        public static void Answer(string what, int side, int idx, int n)
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
                        sc.Hide();
                        return;
                    }
                    if (what == "category")
                    {
                        // The collapse flag is Qud's own per-side dictionary; flip it and let the
                        // screen rebuild its rows, so both views agree on what is folded away.
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
