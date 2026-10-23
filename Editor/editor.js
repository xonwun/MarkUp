import {Slice} from 'prosemirror-model';
import {EditorState, Plugin, TextSelection} from 'prosemirror-state';
import {EditorView, Decoration, DecorationSet} from 'prosemirror-view';
import {history, undo, redo} from 'prosemirror-history';
import {keymap} from 'prosemirror-keymap';
import {baseKeymap} from 'prosemirror-commands';
import {parse, serialize, layout, outline} from './model.js';
let language = 'en';
let source = false, composing = false, cachedText, cachedLayout;
const send = (type, data={}) => window.webkit?.messageHandlers.editor.postMessage({type,...data});
let outlineTimer;
function publishOutline() {
  clearTimeout(outlineTimer);
  if (!composing) send('outline', {headings: outline(serialize(view.state.doc))});
}
function scheduleOutline() {
  clearTimeout(outlineTimer);
  outlineTimer = setTimeout(publishOutline, 120);
}
const lineStart=(doc,index)=>{let pos=0;for(let i=0;i<index;i++)pos+=doc.child(i).nodeSize;return pos;};
const hash=text=>{let h=0;for(let i=0;i<text.length;i++)h=Math.imul(31,h)+text.charCodeAt(i)|0;return (h>>>0).toString(36);};
const dark=window.matchMedia?.('(prefers-color-scheme: dark)');
const diagrams=new Map(), renderedDiagrams=new Set();
// Mermaid is large, so its prebuilt bundle loads only when a document contains a diagram.
let mermaidLoader;
const loadMermaid=()=>mermaidLoader??=new Promise((resolve,reject)=>{
  const script=document.createElement('script');
  script.src='mermaid.js';
  script.onload=()=>window.mermaid?resolve(window.mermaid):reject(new Error('Mermaid did not load.'));
  script.onerror=()=>{mermaidLoader=null;reject(new Error('Mermaid could not be loaded.'));};
  document.head.append(script);
});
async function renderDiagram(source) {
  const theme=dark?.matches?'dark':'neutral', key=theme+hash(source);
  if(!diagrams.has(key)) diagrams.set(key,(async()=>{
    const mermaid=await loadMermaid();
    mermaid.initialize({startOnLoad:false,securityLevel:'strict',theme,fontFamily:'-apple-system, BlinkMacSystemFont, sans-serif'});
    return (await mermaid.render('diagram-'+key,source)).svg;
  })());
  return diagrams.get(key);
}
dark?.addEventListener?.('change',()=>view.dispatch(view.state.tr));
// Rendered blocks stand in for their source lines; clicking one moves the cursor into that source.
function blockWidget(info,start) {
  return (view,getPos)=>{
    const el=document.createElement('div');
    el.className=`block-widget ${info.block.kind}-widget`;
    el.contentEditable='false';
    const reveal=line=>{
      if(composing||getPos()==null) return;
      view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc,lineStart(view.state.doc,line)+1)).scrollIntoView());
      view.focus();
    };
    if(info.block.kind==='table') {
      const scroller=document.createElement('div');
      scroller.className='table-scroll';
      scroller.innerHTML=info.block.html;
      el.append(scroller);
      el.addEventListener('mousedown',event=>{
        event.preventDefault();
        const rows=[...el.querySelectorAll('tr')], row=rows.indexOf(event.target.closest('tr'));
        reveal(start+(row>0?row+1:0));
      });
    } else {
      el.classList.add('pending');
      el.textContent=language==='en'?'Rendering diagram…':'正在渲染图表…';
      // Only a diagram rendering for the first time fades in; cached ones reappear as the cursor moves without it.
      const fresh=!renderedDiagrams.has(info.block.source);
      renderDiagram(info.block.source).then(svg=>{renderedDiagrams.add(info.block.source);el.classList.remove('pending');if(fresh)el.classList.add('entering');el.innerHTML=svg;},error=>{
        el.classList.replace('pending','failed');
        el.textContent=(language==='en'?'Diagram error: ':'图表错误：')+(error?.message||String(error)).split('\n')[0];
      });
      el.addEventListener('mousedown',event=>{event.preventDefault();reveal(start+1);});
    }
    el.addEventListener('click',event=>event.preventDefault());
    return el;
  };
}
function decorations(state) {
  if(source) return DecorationSet.empty;
  const text=serialize(state.doc);
  if(text!==cachedText) {cachedText=text;cachedLayout=layout(text);}
  const items=[]; let index=0;
  const active=state.selection.$head.index(0);
  state.doc.forEach((node,pos)=>{
    const info=cachedLayout[index], editing=info.group ? active>=info.group[0]&&active<info.group[1] : active===index;
    const folded=!editing&&cachedLayout[info.group?.[0]]?.block;
    const cls=['line',...info.classes,editing?'active':''];
    if(info.classes.includes('fence')&&!editing) cls.push('folded-fence');
    if(folded) cls.push('folded-block');
    if(info.block&&!editing) {
      const content=info.block.html??info.block.source, theme=dark?.matches?'dark':'light';
      items.push(Decoration.widget(pos,blockWidget(info,index),{side:-1,key:`${info.block.kind}-${index}-${theme}-${hash(content)}`,ignoreSelection:true,stopEvent:()=>true}));
    }
    items.push(Decoration.node(pos,pos+node.nodeSize,{class:cls.join(' '), 'data-marker':info.marker || ''}));
    for(const [a,b] of info.syntax) if(b>a) items.push(Decoration.inline(pos+1+a,pos+1+b,{class:editing?'syntax':'syntax hidden-syntax'}));
    for(const [a,b,c] of info.spans) if(b>a) items.push(Decoration.inline(pos+1+a,pos+1+b,{class:c}));
    index++;
  });
  return DecorationSet.create(state.doc,items);
}
// Native caret movement skips hidden lines, so step into a rendered block explicitly.
const intoBlock=dir=>(state,dispatch,view)=>{
  if(composing||!state.selection.empty||!view?.endOfTextblock(dir<0?'up':'down')) return false;
  const next=state.selection.$head.index(0)+dir, info=cachedLayout?.[next];
  if(source||!info?.group||!cachedLayout[info.group[0]].block) return false;
  dispatch(state.tr.setSelection(TextSelection.create(state.doc,lineStart(state.doc,next)+1)).scrollIntoView());
  return true;
};
function wrap(marker, close=marker) {
  const {from,to}=view.state.selection;
  const selected=view.state.doc.textBetween(from,to,'\n');
  const tr=view.state.tr.insertText(marker+selected+close,from,to);
  tr.setSelection(TextSelection.create(tr.doc,from+marker.length,from+marker.length+selected.length));
  view.dispatch(tr); view.focus(); return true;
}
function enter(state,dispatch) {
  if(composing) return false;
  const {$from,empty}=state.selection;
  const match=/^(\s*(?:>\s*)?)([-+*]|\d+[.)])\s+/.exec($from.parent.textContent);
  if(!match||!empty) return false;
  if($from.parent.textContent.trim()===match[0].trim()) {dispatch(state.tr.delete($from.start(),$from.end()));return true;}
  const marker=/^\d/.test(match[2]) ? `${parseInt(match[2])+1}.` : match[2];
  dispatch(state.tr.split($from.pos).insertText(`${match[1]}${marker} `));return true;
}
const view=new EditorView(document.querySelector('#editor'),{
  state:EditorState.create({doc:parse(''),plugins:[history(),keymap({'Mod-z':undo,'Shift-Mod-z':redo,'Mod-b':()=>wrap('**'),'Mod-i':()=>wrap('*'),'Mod-k':()=>wrap('[','](https://)'),'Mod-`':()=>wrap('`'),'Enter':enter,'ArrowUp':intoBlock(-1),'ArrowDown':intoBlock(1)}),keymap(baseKeymap),new Plugin({state:{init:(_,state)=>decorations(state),apply:(tr,value,oldState,state)=>composing?value.map(tr.mapping,tr.doc):decorations(state)},props:{decorations(state){return this.getState(state)}}})]}),
  attributes:{'aria-label':'Markdown editor','role':'textbox','aria-multiline':'true',spellcheck:'false'},
  dispatchTransaction(tr) {view.updateState(view.state.apply(tr));if(tr.docChanged) {send('change',{text:serialize(view.state.doc)});scheduleOutline();}send('selection',{line:view.state.selection.$head.index(0)+1});},
  handlePaste(view,event) {
    const text=event.clipboardData?.getData('text/plain');if(text==null)return false;
    view.dispatch(view.state.tr.replaceSelection(new Slice(parse(text).content,1,1)).scrollIntoView());return true;
  },
  clipboardTextSerializer: slice => slice.content.content.map(n=>n.textContent).join('\n'),
  handleDOMEvents:{compositionstart(){composing=true;send('composition',{active:true});return false;},compositionend(){composing=false;setTimeout(()=>{view.dispatch(view.state.tr);send('composition',{active:false});publishOutline();},0);return false;}}
});
window.markup={
  layout(value){if(composing || !['compact','reading'].includes(value))return false;document.documentElement.dataset.layout=value;return true;},
  language(value){language=value==='zh-Hans'?'zh-Hans':'en';document.documentElement.lang=language;view.setProps({attributes:{...view.props.attributes,'aria-label':language==='en'?'Markdown editor':'Markdown 编辑区'}});},
  load(text){view.updateState(EditorState.create({doc:parse(text),plugins:view.state.plugins}));publishOutline();view.focus();},
  outline(){return outline(serialize(view.state.doc));},
  goToHeading(line){
    if(composing || !Number.isInteger(line) || !outline(serialize(view.state.doc)).some(h=>h.line===line)) return false;
    let pos=0;
    for(let i=0;i<line-1;i++) pos+=view.state.doc.child(i).nodeSize;
    const text=view.state.doc.child(line-1).textContent;
    const prefix=/^\s*(?:>\s*)*(?:#{1,6}\s+)?/.exec(text)[0].length;
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc,pos+1+prefix)).scrollIntoView());
    view.focus();
    view.nodeDOM(pos)?.scrollIntoView?.({block:'start',behavior:'auto'});
    return true;
  },
  snapshot(){if(composing)throw new Error(language==='en'?'Finish the current input before continuing.':'请先完成当前输入，再执行此操作。');return serialize(view.state.doc);},
  mode(value){if(composing)return false;source=value;document.body.classList.toggle('source',source);view.dispatch(view.state.tr);view.focus();return true;},
  command(name){if(composing)return; if(name==='undo')undo(view.state,view.dispatch);if(name==='redo')redo(view.state,view.dispatch);if(name==='bold')wrap('**');if(name==='italic')wrap('*');},
  find(query,backward=false){if(!query)return false;const text=serialize(view.state.doc);const offset=view.state.selection.from-view.state.selection.$from.index(0)-1;let at=backward?text.lastIndexOf(query,Math.max(0,offset-1)):text.indexOf(query,offset+1);if(at<0)at=backward?text.lastIndexOf(query):text.indexOf(query);if(at<0)return false;const pos=n=>n+1+text.slice(0,n).split('\n').length-1;view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc,pos(at),pos(at+query.length))).scrollIntoView());view.focus();return true;}
};
send('ready');
