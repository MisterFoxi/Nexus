const fs = require('node:fs');
const path = require('node:path');
const factory = require('C:/Users/lcc/.vscode/extensions/jyaoma.lsl-lsp-3.9.5/server/src/parser/tailslide.js');
(async () => {
  const trees = {};
  const files = Object.fromEntries(['Workshop.lsl','Workshop_HUD.lsl','Workshop_Eval.lsl','Workshop_Output.lsl','Workshop_Storage.lsl'].map(name=>[name,path.join(__dirname,'..',name)]));
  files['Workshop_Eval.before.lsl']=path.join(__dirname,'fixtures','Workshop_Eval.before.lsl');
  const componentRoot=path.resolve(__dirname,'../../Component');
  files['Component.lsl']=fs.existsSync(path.join(__dirname,'..','Component.lsl'))
    ? path.join(__dirname,'..','Component.lsl')
    : fs.existsSync(path.join(componentRoot,'Component.lsl'))
      ? path.join(componentRoot,'Component.lsl') : 'C:/Users/lcc/Lsl dev/Nexus/Component/Component.lsl';
  let hudRoot=path.resolve(__dirname,'../../Hud');
  if(!fs.existsSync(hudRoot)) hudRoot='C:/Users/lcc/Lsl dev/Nexus/Hud';
  for(const name of ['MC_Workshop_Link.lsl','MC_Selected_Controller.lsl','MC_Transactions.lsl']) files[name]=path.join(hudRoot,name);
  for (const [name,filename] of Object.entries(files)) {
    const source = fs.readFileSync(filename,'utf8').replace(/^\uFEFF/,'');
    const logs=[];
    const m=await factory({noInitialRun:true,print:s=>logs.push(s),printErr:s=>logs.push(s)});
    m.FS.writeFile('/script.lsl',source);
    try { m.callMain(['--show-tree','/script.lsl']); }
    catch(e) { if(e.name!=='ExitStatus' && e.name!=='exit') throw e; }
    const errors=logs.filter(s=>s.includes('ERROR::'));
    if(errors.length) throw new Error(name+'\n'+errors.join('\n'));
    const output=logs.join('\n'),start=output.indexOf('Tree:\n');
    if(start<0) throw new Error('No AST: '+name);
    trees[name]=output.slice(start+6);
    console.log(name+': syntax/types OK ('+source.split('\n').length+' lines)');
  }
  fs.writeFileSync(path.join(__dirname,'lsl_asts.json'),JSON.stringify(trees));
})().catch(error=>{console.error(error);process.exitCode=1;});
