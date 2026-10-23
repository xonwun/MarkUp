import {Schema} from 'prosemirror-model';
import MarkdownIt from 'markdown-it';
export const schema = new Schema({nodes: {
  doc: {content: 'line+'},
  line: {content: 'text*', group: 'block', whitespace: 'pre', toDOM: () => ['div', {class: 'line'}, 0], parseDOM: [{tag: 'div'}]},
  text: {group: 'inline'}
}});
export function parse(text) { return schema.node('doc', null, text.split('\n').map(line => schema.node('line', null, line ? schema.text(line) : null))); }
export function serialize(doc) { const lines = []; doc.forEach(line => lines.push(line.textContent)); return lines.join('\n'); }
const md = new MarkdownIt({html: false, linkify: false});
// markdown-it aligns cells with style attributes, which the editor's CSP blocks.
const tableHTML = source => md.render(source).replace(/ style="text-align:(left|center|right)"/g, ' class="align-$1"');
export function layout(text) {
  const raw = text.split('\n');
  const lines = raw.map(() => ({classes: [], syntax: [], spans: []}));
  for (const token of md.parse(text, {})) {
    if (!token.map) continue;
    const [start, end] = token.map;
    if (token.type === 'heading_open') lines[start].classes.push(token.tag);
    // Top-level tables and Mermaid fences render as a block until the cursor enters them.
    if (token.type === 'table_open' && token.level === 0) {
      for(let i=start;i<end;i++) { lines[i].classes.push('table'); lines[i].group = [start, end]; }
      lines[start].block = {kind: 'table', html: tableHTML(raw.slice(start, end).join('\n'))};
    }
    if (token.type === 'fence' && token.level === 0 && token.info.trim().split(/\s+/)[0].toLowerCase() === 'mermaid') {
      lines[start].block = {kind: 'mermaid', source: token.content};
    }
    if (token.type === 'blockquote_open') for(let i=start;i<end;i++) lines[i].classes.push('quote');
    if (token.type === 'list_item_open') lines[start].classes.push('list');
    if (token.type === 'fence' || token.type === 'code_block') {
      for(let i=start;i<end;i++) { lines[i].classes.push('code'); lines[i].group = [start, end]; }
      lines[start].classes.push('code-start');
      lines[end-1].classes.push('code-end');
      if(token.type === 'fence') {
        lines[start].classes.push('fence');
        if (end > start+1 && /^\s*(`{3,}|~{3,})\s*\r?$/.test(raw[end-1])) lines[end-1].classes.push('fence');
      }
    }
  }
  raw.forEach((line,i) => {
    const out=lines[i];
    if(out.classes.includes('code')) return;
    const prefix = /^(\s*(?:>\s*)*(?:(?:#{1,6}|[-+*]|\d+[.)])\s+)?)/.exec(line)[0];
    if(prefix.trim()) out.syntax.push([0,prefix.length]);
    const listMarker = /^\s*(?:>\s*)*(\d+[.)]|[-+*])\s+/.exec(line);
    if (listMarker) out.marker = /^\d/.test(listMarker[1]) ? listMarker[1] : '•';
    const occupied=[];
    const patterns=[[/(`+)([^`]+?)\1/g,'inline-code'],[/\[([^\]]+)\]\(([^\s)]+)(?:\s+"[^"]*")?\)/g,'link'],[/(\*\*|__)(?=\S)(.+?\S|\S)\1/g,'bold'],[/(?<![\w*_])(\*|_)(?![*_])(?=\S)([^*_]+?)\1(?![*_\w])/g,'italic']];
    for(const [pattern, cls] of patterns) for(const m of line.matchAll(pattern)) {
      const a=m.index,b=a+m[0].length;
      if(a>0 && line[a-1]==='\\' || occupied.some(([x,y])=>a<y&&b>x)) continue;
      let left,right;
      if(cls==='link') {left=1;right=m[0].length-m[1].length-1;} else {left=m[1].length;right=left;}
      out.syntax.push([a,a+left],[b-right,b]); out.spans.push([a+left,b-right,cls]);
      if(cls==='inline-code'||cls==='link') occupied.push([a,b]);
    }
  });
  return lines;
}

export function outline(text) {
  const tokens = md.parse(text, {});
  return tokens.flatMap((token, index) => {
    if (token.type !== 'heading_open' || !token.map) return [];
    const inline = tokens[index + 1];
    const title = (inline?.children ?? []).map(child => {
      if (child.type === 'text' || child.type === 'code_inline') return child.content;
      if (child.type === 'softbreak' || child.type === 'hardbreak') return ' ';
      if (child.type === 'image') return child.content;
      return '';
    }).join('').trim();
    return [{line: token.map[0] + 1, level: Number(token.tag.slice(1)), title}];
  });
}
