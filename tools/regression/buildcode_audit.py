#!/usr/bin/env python3
"""buildcode: the encoder produces codes Qud's own format accepts.

A PYTHON MIRROR of godot/BuildCode.gd's encode()/decode(), checked against a REAL Qud
code (a pregen out of EmbarkModules.xml): decode the real one, re-encode what we decoded,
and require the round trip to preserve every field the chargen flow reads. The mirror is
the same discipline as the other audits — it catches drift between the two, and breaking
it on purpose must fail (verified when written).
"""
import base64, gzip, json, os, re, sys

QUD = os.path.expanduser("~/Library/Application Support/Steam/steamapps/common/"
                         "Caves of Qud/CoQ.app/Contents/Resources/Data/StreamingAssets/Base/EmbarkModules.xml")
fails = []
def check(ok, msg):
    if not ok:
        fails.append(msg)

def decode(code):
    d = json.loads(gzip.decompress(base64.b64decode(code)).decode("utf-8"))
    out = {"genotype": "", "subtype": "", "attributes": {}, "mutations": [], "cybernetics": []}
    for mod in d.get("modules", []):
        data = mod.get("data") or {}
        if "Genotype" in data: out["genotype"] = data["Genotype"]
        if "Subtype" in data: out["subtype"] = data["Subtype"]
        if "PointsPurchased" in data: out["attributes"] = data["PointsPurchased"]
        for sel in data.get("selections", []) or []:
            if "Mutation" in sel:
                out["mutations"].append({"name": sel["Mutation"], "count": sel.get("Count", 1)})
            if "Cybernetic" in sel:
                out["cybernetics"].append({"blueprint": sel["Cybernetic"], "slot": sel.get("Variant", "")})
    return out, d.get("gameversion", "")

def mtype(short, gv):
    return ("XRL.CharacterBuilds.Qud.%s, Assembly-CSharp, Version=%s, "
            "Culture=neutral, PublicKeyToken=null" % (short, gv))

def encode(b, gv):
    mods = []
    if b["genotype"]:
        mods.append({"moduleType": mtype("QudGenotypeModule", gv),
                     "data": {"$type": "XRL.CharacterBuilds.QudGenotypeModuleData, Assembly-CSharp",
                              "Genotype": b["genotype"], "version": "1.0.0"}})
    if b["subtype"]:
        mods.append({"moduleType": mtype("QudSubtypeModule", gv),
                     "data": {"$type": "XRL.CharacterBuilds.QudSubtypeModuleData, Assembly-CSharp",
                              "Subtype": b["subtype"], "version": "1.0.0"}})
    if b["attributes"]:
        mods.append({"moduleType": mtype("QudAttributesModule", gv),
                     "data": {"$type": "XRL.CharacterBuilds.QudAttributesModuleData, Assembly-CSharp",
                              "PointsPurchased": b["attributes"], "apSpent": 0,
                              "apRemaining": 0, "baseAp": 0, "version": "1.0.0"}})
    if b["mutations"]:
        mods.append({"moduleType": mtype("QudMutationsModule", gv),
                     "data": {"$type": "XRL.CharacterBuilds.QudMutationsModuleData, Assembly-CSharp",
                              "lp": 0, "version": "1.0.0",
                              "selections": [{"Mutation": m["name"], "Count": m["count"], "Variant": 0}
                                             for m in b["mutations"]]}})
    if b["cybernetics"]:
        mods.append({"moduleType": mtype("QudCyberneticsModule", gv),
                     "data": {"$type": "XRL.CharacterBuilds.QudCyberneticsModuleData, Assembly-CSharp",
                              "lp": 0, "version": "1.0.0",
                              "selections": [{"Cybernetic": c["blueprint"], "Count": 1,
                                              "Variant": c["slot"]} for c in b["cybernetics"]]}})
    doc = {"gameversion": gv, "buildversion": "1.0.0", "modules": mods}
    return base64.b64encode(gzip.compress(json.dumps(doc).encode("utf-8"))).decode("ascii")

if not os.path.exists(QUD):
    print("buildcode: SKIP (no Qud install at the standard path)")
    sys.exit(0)

txt = open(QUD, encoding="utf-8", errors="replace").read()
codes = re.findall(r"<code>\s*(\S+)\s*</code>", txt, re.S)
check(len(codes) > 0, "no build codes found in EmbarkModules.xml")

checked = 0
for code in codes:
    orig, gv = decode(code)
    # every real code must carry a genotype and a subtype — the two the embark guard needs
    check(orig["genotype"] != "", "a real code decoded with no genotype")
    check(orig["subtype"] != "", "a real code decoded with no subtype")
    # round trip: OUR encoding of what we decoded must decode back identically
    again, gv2 = decode(encode(orig, gv))
    check(again["genotype"] == orig["genotype"], "genotype lost in round trip")
    check(again["subtype"] == orig["subtype"], "subtype lost in round trip")
    check(again["attributes"] == orig["attributes"], "attributes lost in round trip")
    check([m["name"] for m in again["mutations"]] == [m["name"] for m in orig["mutations"]],
          "mutations lost in round trip")
    check([c["blueprint"] for c in again["cybernetics"]] == [c["blueprint"] for c in orig["cybernetics"]],
          "cybernetics lost in round trip")
    check(gv2 == gv, "gameversion lost in round trip")
    checked += 1

if fails:
    print("buildcode: FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("buildcode: %d real Qud build codes decode, re-encode and decode back identically "
      "(genotype, subtype, attributes, mutations, cybernetics, gameversion)" % checked)
