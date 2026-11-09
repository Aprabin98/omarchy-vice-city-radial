const fs=require('fs');
let src=fs.readFileSync(''+__dirname+'/../menu.js','utf8').replace('.pragma library','');
const M=new Function(src+';return {parseRaw,build,whenArgs,kids,opensChildren,leaves,scoreAll,pathLabel,resolve}')();
const raw=M.parseRaw(fs.readFileSync(process.env.OMARCHY_PATH+'/default/omarchy/omarchy-menu.jsonc','utf8'));
const ext=M.parseRaw(fs.readFileSync(process.env.OMARCHY_PATH+'/config/omarchy/extensions/omarchy-menu.jsonc','utf8'));
console.log('raw',Object.keys(raw).length,'ext',JSON.stringify(ext));
const m=M.build([raw,ext]);
const pass={}; M.whenArgs(m).forEach((v,i,a)=>{ if(i%2===0) pass[v]=true });
const roots=M.kids(m,'root',pass);
console.log('roots:',roots.map(r=>r.label+(M.opensChildren(m,r,pass)?'+':'')).join(', '));
for(const r of roots){const k=M.kids(m,r.id,pass);console.log(r.label,k.length,k.slice(0,4).map(x=>x.label).join('|'))}
const lv=M.leaves(m,pass);console.log('leaves',lv.length);
for(const q of ['theme','ins pack','wifi','lock','zzzz']){
 const r=lv.map(l=>({l,s:M.scoreAll(q,l.it.label,l.path,l.it.description+' '+l.it.aliases.join(' ')+' '+l.it.searchTerms.join(' '))})).filter(x=>x.s).sort((a,b)=>b.s-a.s).slice(0,3);
 console.log(q,'->',r.map(x=>x.l.path).join(' ; ')||'none');
}
// link/empty-menu checks
console.log('links:',Object.values(m.items).filter(i=>i.kind==='link').length,'providers:',Object.values(m.items).filter(i=>i.provider).map(i=>i.id).join(','));
