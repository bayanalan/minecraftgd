// Generates scripts/core/block_hardness.gd (block hardness + needs-correct-tool set) from Minecraft Wiki data.
// Run in a scratch folder holding: hardness_values.lua (wiki Module:Hardness values, e.g. via the fandom API
// action=query&prop=revisions&rvprop=content&titles=Module:Hardness_values), fandom_breaking.txt (the Breaking page
// wikitext), jarx/ (en_us.json + data/minecraft/tags/block from the local 26.3 jar; never committed).
// Usage: node gen_block_hardness.js <out .gd path>
const fs=require("fs");
const lang=JSON.parse(fs.readFileSync("jarx/assets/minecraft/lang/en_us.json","utf8"));
const H={}; for(const m of fs.readFileSync("hardness_values.lua","utf8").matchAll(/\[(?:'([^']+)'|"([^"]+)")\]\s*=\s*(-?[0-9.]+)/g)) H[m[1]||m[2]]=parseFloat(m[3]);
// rows: name -> [tool, tier]
const R={}; for(const m of fs.readFileSync("fandom_breaking.txt","utf8").matchAll(/\{\{breaking row\|([^}]*)\}\}/gi)){
  const a=m[1].split("|").filter(x=>!x.includes("=")); const nm=a[0].trim().toLowerCase(); R[nm]=[(a[1]||"").trim().toLowerCase(),(a[2]||"").trim().toLowerCase()]; }
// extra (current wiki, newer than the fandom data): hardness, [tool, tier]
const EXTRA={"shelf":2,"copper chest":3,"copper golem statue":3,"copper bars":5,"copper chain":5,"iron chain":5,"copper lantern":3.5,
 "copper torch":0,"copper wall torch":0,"dried ghast":0,"golden dandelion":0,"chalkboard":1.15,"sulfur":1.5,"potent sulfur":1.5,"sulfur spike":1.5,
 "cinnabar":1.5,"chiseled sulfur":1.5,"chiseled cinnabar":1.5,"polished sulfur":1.5,"polished cinnabar":1.5,"sulfur bricks":1.5,"cinnabar bricks":1.5,
 "cactus flower":0,"concrete slab":1.8,"concrete stairs":1.8,"wool slab":0.8,"wool stairs":0.8,"carrots":0,"potatoes":0,"wheat crops":0,"beetroots":0,"pitcher crop":0,"torchflower crop":0,"attached melon stem":0,"attached pumpkin stem":0,"melon stem":0,"pumpkin stem":0,"cave vines plant":0,"kelp plant":0,"twisting vines plant":0,"weeping vines plant":0,"tall seagrass":0,"sweet berry bush":0,"chipped anvil":5,"damaged anvil":5,"water cauldron":2,"lava cauldron":2,"powder snow cauldron":2,"mushroom stem":0.2,"wall torch":0,"bush":0,"short dry grass":0,"tall dry grass":0,"wildflowers":0,"leaf litter":0,"firefly bush":0,"test block":-1,"test instance block":-1};
for(const k in EXTRA) if(!(k in H)) H[k]=EXTRA[k];
const COL=["white","orange","magenta","light blue","yellow","lime","pink","gray","light gray","cyan","purple","blue","brown","green","red","black"];
const WOOD=["poplar","oak","spruce","birch","jungle","acacia","dark oak","mangrove","cherry","pale oak","bamboo","crimson","warped"];
const OX=["exposed ","weathered ","oxidized ","waxed exposed ","waxed weathered ","waxed oxidized ","waxed "];
function cands(n){
  const out=[n];
  for(const o of OX) if(n.startsWith(o)) out.push(n.slice(o.length));
  for(const c of COL) if(n.startsWith(c+" ")){ const r=n.slice(c.length+1); out.push(r,"dyed "+r,"stained "+r,"colored "+r, r+"s"); }
  for(const w of WOOD) if(n.startsWith(w+" ")){ let r=n.slice(w.length+1); out.push(r,"wooden "+r, r+"s");
     if(r==="stem"||r==="hyphae") out.push("log","wood"); }
  for(const w of WOOD) if(n.startsWith("stripped "+w+" ")){ const r=n.slice(("stripped "+w+" ").length); out.push("stripped "+r,"stripped log","stripped wood"); }
  if(n.startsWith("potted ")) out.push("flower pot");
  for(const suf of [" slab"," stairs"," wall"]) if(n.endsWith(suf)){ const b=n.slice(0,-suf.length); out.push(b,b+"s",b+" block"); }
  if(n.endsWith(" wall sign")) out.push(n.replace(" wall sign"," sign"),"sign");
  if(n.endsWith(" wall hanging sign")) out.push("hanging sign");
  if(n.endsWith(" wall banner")) out.push("banner");
  if(n.endsWith(" wall torch")) out.push(n.replace(" wall torch"," torch"));
  if(n.endsWith(" wall fan")) out.push(n.replace(" wall fan"," fan"));
  if(n.endsWith(" head")||n.endsWith(" skull")) out.push("head");
  if(n.endsWith(" candle")) out.push("candle","dyed candle");
  if(n.endsWith(" candle cake")||n==="cake with candle") out.push("cake");
  if(n.endsWith(" shulker box")) out.push("shulker box");
  if(n.endsWith(" bed")) out.push("bed");
  if(n.endsWith(" carpet")) out.push("carpet");
  if(n.endsWith(" leaves")) out.push("leaves");
  if(n.endsWith(" sapling")) out.push("sapling","saplings");
  if(n.endsWith(" tulip")) out.push("flowers","tulip");
  if(n.endsWith(" coral")) out.push("coral"); if(n.endsWith(" coral block")) out.push("coral block","dead coral block");
  if(n.endsWith(" coral fan")) out.push("coral fan");
  if(n.endsWith(" shelf")) out.push("shelf");
  if(n.endsWith(" copper chest")) out.push("copper chest");
  if(n.endsWith(" copper golem statue")) out.push("copper golem statue");
  if(n.endsWith(" froglight")) out.push("froglight");
  if(n.endsWith(" concrete powder")) out.push("concrete powder");
  return out;
}
function lookup(map,n){ for(const c of cands(n)){ if(c in map) return [map[c],c]; for(const c2 of cands(c)) if(c2 in map) return [map[c2],c2]; } return null; }
const ids=Object.keys(lang).filter(k=>/^block\.minecraft\.[a-z0-9_]+$/.test(k)).map(k=>k.slice(16));
const out={}, miss=[], tools={}, tmiss=[];
for(const id of ids){
  let n=lang["block.minecraft."+id].toLowerCase().replace(/’/g,"'");
  let r=lookup(H,n);
  if(!r && id.includes("_wall_")){ const id2=id.replace("_wall_","_"); const n2=(lang["block.minecraft."+id2]||"").toLowerCase(); r=n2?lookup(H,n2):null; }
  if(r) out[id]=r[0]; else miss.push(id+" ("+n+")");
  const t=lookup(R,n); if(t) tools[id]=t[0]; else tmiss.push(id);
}
fs.writeFileSync("hard_out.json",JSON.stringify({out,tools},null,0));
console.log("ids",ids.length,"hardness",Object.keys(out).length,"missing",miss.length); console.log(miss.join("\n"));
console.log("tool rows",Object.keys(tools).length,"missing",tmiss.length);
// ---- GDScript output
function tag(n){ const base="jarx/data/minecraft/tags/block/"; const j=JSON.parse(fs.readFileSync(base+n+".json","utf8")); const o=new Set(); for(let v of j.values){ if(typeof v!=="string") v=v.id; if(v.startsWith("#")) for(const x of tag(v.slice(11))) o.add(x); else o.add(v.replace("minecraft:","")); } return o; }
const pick=tag("mineable/pickaxe");
const need=new Set();
for(const id of Object.keys(out)){
  const t=tools[id];
  if(t){ if(["wood","stone","iron","diamond"].includes(t[1])) need.add(id); }
  else if(pick.has(id) && !id.includes("_button") && !id.includes("amethyst_bud")) need.add(id);
}
for(const id of ["snow","snow_block"]) need.add(id);
const fmt=v=>Number.isInteger(v)?v.toFixed(1):String(v);
let gd="## BlockHardness - Java block destroy time (hardness) and which blocks need the correct tool to drop anything, per block\n";
gd+="## id. Data: Minecraft Wiki \"Breaking\" (Module:Hardness values + the breaking rows' tool / tier columns; blocks newer than\n";
gd+="## that data from the current Breaking page), mapped to ids through the game's own English block names.\n";
gd+="## Regenerate: tools/gen_block_hardness.js. Blocks missing here keep BlockProperties' family rules.\nclass_name BlockHardness\n\n";
const ks=Object.keys(out).filter(k=>k!=="set_spawn").sort();
gd+="const HARDNESS := {\n"; let line="\t"; for(const k of ks){ const e=`"${k}": ${fmt(out[k])}, `; if(line.length+e.length>118){ gd+=line.trimEnd()+"\n"; line="\t"; } line+=e; } gd+=line.trimEnd()+"\n}\n\n";
gd+="const NEEDS_TOOL := {\n"; line="\t"; for(const k of [...need].sort()){ const e=`"${k}": true, `; if(line.length+e.length>118){ gd+=line.trimEnd()+"\n"; line="\t"; } line+=e; } gd+=line.trimEnd()+"\n}\n";
fs.writeFileSync(process.argv[2]||"block_hardness.gd",gd);
console.log("need",need.size);
