import {test} from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
const dom=new JSDOM('<main id="editor"></main>',{pretendToBeVisual:true});
for(const name of ['window','document','navigator','MutationObserver','HTMLElement','getComputedStyle']) Object.defineProperty(globalThis,name,{value:dom.window[name],configurable:true});
globalThis.innerHeight=900;globalThis.pageYOffset=0;
dom.window.Range.prototype.getClientRects=()=>[];
dom.window.Range.prototype.getBoundingClientRect=()=>({top:0,bottom:0,left:0,right:0});
await import('../../Editor/editor.js');
const api=window.markup;
test('mode changes preserve exact text and reveal source',()=>{
 const text='# 中文\n\n**加粗**\n\n1. 列表\n';api.load(text);assert.equal(api.snapshot(),text);
 assert.equal(api.mode(true),true);assert.equal(document.querySelectorAll('.hidden-syntax').length,0);assert.equal(api.snapshot(),text);
 api.mode(false);assert.ok(document.querySelectorAll('.hidden-syntax').length>0);assert.equal(api.snapshot(),text);
});
test('composition blocks snapshots and mode switching without dropping content',()=>{
 api.load('中文输入');const editor=document.querySelector('.ProseMirror');editor.dispatchEvent(new window.CompositionEvent('compositionstart',{bubbles:true}));
 assert.throws(()=>api.snapshot());assert.equal(api.mode(true),false);
 editor.dispatchEvent(new window.CompositionEvent('compositionend',{bubbles:true}));assert.equal(api.snapshot(),'中文输入');
});
test('search selects exact Chinese text and wraps',()=>{
 api.load('开头\n第二行中文\n结尾中文');assert.equal(api.find('中文'),true);assert.equal(api.find('中文'),true);assert.equal(api.find('中文'),true);assert.equal(api.find('没有'),false);
});
test('language switching updates accessibility without changing content or undo history',()=>{
 const text='中文内容 **bold**';api.load(text);api.language('en');
 assert.equal(document.documentElement.lang,'en');
 assert.equal(document.querySelector('.ProseMirror').getAttribute('aria-label'),'Markdown editor');
 api.command('bold');const edited=api.snapshot();api.language('zh-Hans');
 assert.equal(document.documentElement.lang,'zh-Hans');
 assert.equal(document.querySelector('.ProseMirror').getAttribute('aria-label'),'Markdown 编辑区');
 assert.equal(api.snapshot(),edited);api.command('undo');assert.equal(api.snapshot(),text);
 api.language('en');assert.equal(api.snapshot(),text);
});

test('outline jumps to the correct duplicate heading and preserves text and undo in both modes',()=>{
 const text='# Same\n\n正文\n\n## Same\n\n结尾\n';
 for(const source of [false,true]) {
  api.load(text);api.mode(source);
  assert.equal(api.goToHeading(5),true);
  const selection=window.getSelection();
  const row=selection.anchorNode.parentElement.closest('.ProseMirror > div');
  assert.equal(row,document.querySelector('.ProseMirror').children[4]);
  const before=document.createRange();before.setStart(row,0);before.setEnd(selection.anchorNode,selection.anchorOffset);
  assert.equal(before.toString(),'## ');
  assert.equal(api.snapshot(),text);
  api.command('bold');const edited=api.snapshot();
  api.goToHeading(1);assert.equal(api.snapshot(),edited);
  api.command('undo');assert.equal(api.snapshot(),text);
  assert.equal(api.goToHeading(3),false);assert.equal(api.goToHeading(999),false);
  assert.equal(api.goToHeading(1.5),false);
 }
 api.mode(false);
});
test('outline changes are published after editing and composition guards heading navigation',async()=>{
 const messages=[];window.webkit={messageHandlers:{editor:{postMessage:m=>messages.push(m)}}};
 api.load('# 中文\n\n## Section');api.goToHeading(4);
 assert.equal(messages.filter(m=>m.type==='outline').at(-1).headings.length,2);
 api.find('Section');api.command('bold');
 await new Promise(resolve=>setTimeout(resolve,150));
 assert.equal(messages.filter(m=>m.type==='outline').at(-1).headings[1].title,'Section');
 const editor=document.querySelector('.ProseMirror');
 editor.dispatchEvent(new window.CompositionEvent('compositionstart',{bubbles:true}));
 assert.equal(api.goToHeading(1),false);
 editor.dispatchEvent(new window.CompositionEvent('compositionend',{bubbles:true}));
 api.load('plain text');assert.deepEqual(api.outline(),[]);
 delete window.webkit;
});

test('layout switching preserves content, selection, source mode and undo history',()=>{
 const text='# Layout\n\n中文 **notes**\n';api.load(text);api.mode(true);api.find('notes');api.command('bold');
 const edited=api.snapshot(),selection=window.getSelection().toString(),editor=document.querySelector('.ProseMirror');
 for(const layout of ['reading','compact']) {
  assert.equal(api.layout(layout),true);assert.equal(document.documentElement.dataset.layout,layout);
  assert.equal(document.querySelector('.ProseMirror'),editor);assert.equal(api.snapshot(),edited);
  assert.equal(window.getSelection().toString(),selection);assert.ok(document.body.classList.contains('source'));
 }
 assert.equal(api.layout('unknown'),false);assert.equal(document.documentElement.dataset.layout,'compact');
 api.command('undo');assert.equal(api.snapshot(),text);
 editor.dispatchEvent(new window.CompositionEvent('compositionstart',{bubbles:true}));
 assert.equal(api.layout('reading'),false);assert.equal(document.documentElement.dataset.layout,'compact');
 editor.dispatchEvent(new window.CompositionEvent('compositionend',{bubbles:true}));api.mode(false);
});

test('tables render as a block outside the cursor and reveal exact source inside it',()=>{
 const text='Intro\n\n| Name | 数量 |\n| :--- | ---: |\n| **A** | 12 |\n| B | 3 |\n\nAfter';api.load(text);
 const table=document.querySelector('.table-widget table');
 assert.ok(table);assert.equal(table.querySelectorAll('tr').length,3);
 assert.equal(table.querySelector('strong').textContent,'A');
 assert.ok(table.querySelector('td.align-right'));assert.equal(table.querySelector('[style]'),null);
 assert.equal(document.querySelectorAll('.folded-block').length,4);assert.equal(api.snapshot(),text);
 assert.equal(api.find('B |'),true);
 assert.equal(document.querySelector('.table-widget'),null);assert.equal(document.querySelectorAll('.folded-block').length,0);
 assert.equal(document.querySelectorAll('.table.active').length,4);
 api.mode(true);assert.equal(document.querySelector('.table-widget'),null);api.mode(false);
 assert.equal(api.snapshot(),text);
});
test('mermaid fences render as a diagram block and keep their source',()=>{
 const text='Intro\n\n```mermaid\ngraph TD\n  A --> B\n```\n\n```js\nconst x = 1;\n```';api.load(text);
 assert.equal(document.querySelectorAll('.mermaid-widget').length,1);
 assert.equal(document.querySelectorAll('.folded-block').length,4);
 assert.equal(api.find('A -->'),true);assert.equal(document.querySelector('.mermaid-widget'),null);
 assert.equal(api.snapshot(),text);
});
