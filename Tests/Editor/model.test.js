import {test} from 'node:test';
import assert from 'node:assert/strict';
import {EditorState, TextSelection} from 'prosemirror-state';
import {Slice} from 'prosemirror-model';
import {history,undo,redo} from 'prosemirror-history';
import {parse,serialize,layout,outline} from '../../Editor/model.js';
const fixtures=['','你好，世界。\n\n# 标题\n','\uFEFF# 标题\r\n\r\n正文  \r\n','**粗体** *斜体* [链接](https://example.com) `code`','1. 第一项\n2. 第二项\n\n> 引用\n\n```swift\nlet 中文 = "好"\n```\n','未知语法 <tag>\n|表格|\n|---|\n![图片](a.png)'];
for(const value of fixtures) test(`lossless ${JSON.stringify(value).slice(0,50)}`,()=>assert.equal(serialize(parse(value)),value));
test('renders supported block and inline syntax',()=>{
 const rows=layout('# 标题\n\n**粗体** 和 *斜体* `code` [链接](https://example.com)\n\n1. 第一项\n\n> 引用\n\n```js\nlet x=1\n```');
 assert.ok(rows[0].classes.includes('h1'));assert.deepEqual(rows[2].spans.map(s=>s[2]).sort(),['bold','inline-code','italic','link']);assert.equal(rows[4].marker,'1.');assert.ok(rows[6].classes.includes('quote'));assert.ok(rows[9].classes.includes('code'));
});
test('multiline paste preserves Chinese, newlines and surrounding text',()=>{
 let state=EditorState.create({doc:parse('前后')});state=state.apply(state.tr.setSelection(TextSelection.create(state.doc,2)));
 state=state.apply(state.tr.replaceSelection(new Slice(parse('中文\n\n第二行').content,1,1)));
 assert.equal(serialize(state.doc),'前中文\n\n第二行后');
});
test('undo and redo preserve text exactly',()=>{
 let state=EditorState.create({doc:parse('原文\n'),plugins:[history()]});const dispatch=tr=>{state=state.apply(tr)};
 dispatch(state.tr.insertText('中文',1));assert.equal(serialize(state.doc),'中文原文\n');undo(state,dispatch);assert.equal(serialize(state.doc),'原文\n');redo(state,dispatch);assert.equal(serialize(state.doc),'中文原文\n');
});

test('outline extracts hierarchy, readable labels and distinct duplicate headings',()=>{
 const text='# **中文** [链接](https://example.com) `code`\r\n\r\n## 相同\r\n\r\n### 相同\r\n\r\n章节\r\n====\r\n\r\n> #### 引用\r\n';
 assert.deepEqual(outline(text),[
  {line:1,level:1,title:'中文 链接 code'},
  {line:3,level:2,title:'相同'},
  {line:5,level:3,title:'相同'},
  {line:7,level:1,title:'章节'},
  {line:10,level:4,title:'引用'}
 ]);
});
test('outline ignores heading-like code, escaped hashes and plain text',()=>{
 const text='# Real\n\n```md\n# fenced\n```\n\n    # indented\n\n\\# escaped\n\n#NoSpace\n\n###### \n';
 assert.deepEqual(outline(text),[{line:1,level:1,title:'Real'},{line:13,level:6,title:''}]);
 assert.deepEqual(outline('no headings'),[]);
});

test('code-block corners follow complete blocks, including empty and unclosed fences',()=>{
 for(const text of ['```js\na\nb\n```','```\n```','```\na','    a\n    b','    a']) {
  const rows=layout(text), code=rows.filter(row=>row.classes.includes('code'));
  assert.ok(code.length);
  assert.equal(code.filter(row=>row.classes.includes('code-start')).length,1);
  assert.equal(code.filter(row=>row.classes.includes('code-end')).length,1);
  assert.ok(code[0].classes.includes('code-start'));
  assert.ok(code.at(-1).classes.includes('code-end'));
 }
 const rows=layout('```\na\n```\n\n```\nb\n```');
 assert.equal(rows.filter(row=>row.classes.includes('code-start')).length,2);
 assert.equal(rows.filter(row=>row.classes.includes('code-end')).length,2);
 assert.deepEqual(rows[3].classes,[]);
});
