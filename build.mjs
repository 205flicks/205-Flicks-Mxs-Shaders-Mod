// Locally authored build helper. Does not deploy to a game or execute the DLL.
// Requires Node.js, a Windows x64 host, and Zig 0.14.1's zig.exe path as argument.
import fs from 'node:fs';import path from 'node:path';import {spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url));
const zig=path.resolve(process.argv[2]||'zig.exe'),lib=path.join(path.dirname(zig),'lib');
const build=path.join(root,'build');fs.mkdirSync(build,{recursive:true});
function run(args){const r=spawnSync(zig,args,{cwd:root,encoding:'utf8',maxBuffer:16*1024*1024});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.status!==0)throw Error('Tool failed '+r.status);}
function exportsOf(file){const b=fs.readFileSync(file),pe=b.readUInt32LE(0x3c),o=pe+24,sections=[];if(b.readUInt16LE(o)!==0x20b)throw Error('Expected x64 PE');for(let i=0;i<b.readUInt16LE(pe+6);i++){const s=o+b.readUInt16LE(pe+20)+i*40;sections.push({va:b.readUInt32LE(s+12),sz:Math.max(b.readUInt32LE(s+8),b.readUInt32LE(s+16)),raw:b.readUInt32LE(s+20)});}const rva=v=>{const s=sections.find(s=>v>=s.va&&v<s.va+s.sz);if(!s)throw Error('RVA');return s.raw+v-s.va;};const e=rva(b.readUInt32LE(o+112)),names=rva(b.readUInt32LE(e+32)),out=[];for(let i=0;i<b.readUInt32LE(e+24);i++){const s=rva(b.readUInt32LE(names+i*4));out.push(b.toString('ascii',s,b.indexOf(0,s)));}return out;}
const libs=[];
for(const name of ['kernel32','user32','gdi32','ucrtbase']){
 const def=path.join(build,name+'.def'),out=path.join(build,name+'.lib');
 fs.writeFileSync(def,'LIBRARY '+name+'.dll\nEXPORTS\n'+exportsOf(path.join(process.env.SystemRoot||'C:/Windows','System32',name+'.dll')).join('\n')+'\n');
 run(['dlltool','-m','i386:x86-64','-d',def,'-l',out]);libs.push(out);
}
const objects=[];
const units=['proxy','hooks','log','pack','post','ui','mxsr_runtime'].map(n=>'src/'+n+'.c').concat(['generated/real_table.c','generated/default_pack.c']);
for(const f of units){const out=path.join(build,path.basename(f,'.c')+'.obj');run(['-cc1','-triple','x86_64-unknown-windows-gnu','-emit-obj','-O2','-std=c11','-fms-extensions','-fgnuc-version=4.2.1','-ferror-limit','10','-fno-builtin','-D__USE_MINGW_ANSI_STDIO=0','-D_CRT_SECURE_NO_WARNINGS','-Isrc','-isystem',path.join(lib,'include'),'-isystem',path.join(lib,'libc/include/any-windows-any'),f,'-o',out]);objects.push(out);}
for(const f of ['generated/stubs.S','generated/stack_probe.S']){const out=path.join(build,path.basename(f,'.S')+'.obj');run(['-cc1as','-triple','x86_64-unknown-windows-gnu','-filetype','obj',f,'-o',out]);objects.push(out);}
run(['lld-link','/dll','/entry:DllMain','/machine:x64','/nodefaultlib','/out:'+path.resolve(root,'opengl32.dll'),'/implib:'+path.join(build,'opengl32.lib'),'/def:generated/exports.def',...objects,...libs]);
console.log('Built DLL; not loaded, executed or installed.');

/* Builds the Windows opengl32.dll. */
