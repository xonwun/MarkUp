import AppKit
import WebKit

@MainActor
final class Smoke: NSObject, WKNavigationDelegate {
    let web: WKWebView = { let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); return WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: config) }()
    var completed = false
    var passed = false
    func run(_ path: String) {
        web.navigationDelegate = self
        let url = URL(fileURLWithPath: path)
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.callAsyncJavaScript("""
        return await (async () => {
          const text = '# 中文标题\\n\\n**粗体** 和 *斜体*\\n\\n1. 第一项\\n2. 第二项\\n\\n```swift\\nlet x = 1\\n```\\n';
          window.markup.load(text);
          if (window.markup.snapshot() !== text) throw Error('Load mismatch');
          for (const [layout, size, padding] of [['compact', '15px', '24px'], ['reading', '16px', '32px']]) {
            if (!window.markup.layout(layout)) throw Error('Layout switch failed');
            if (getComputedStyle(document.body).fontSize !== size) throw Error('Incorrect layout type size');
            if (getComputedStyle(document.querySelector('#editor')).paddingLeft !== padding) throw Error('Incorrect layout padding');
            if (getComputedStyle(document.querySelector('.ProseMirror')).outlineStyle !== 'none') throw Error('Document focus rectangle remains');
            const box = document.querySelector('#editor').getBoundingClientRect();
            const expectedLeft = layout === 'reading' ? (window.innerWidth - box.width) / 2 : 0;
            if (Math.abs(box.left - expectedLeft) > 1) throw Error('Incorrect document column alignment');
            if (getComputedStyle(document.querySelector('.ProseMirror')).textAlign !== 'start' && getComputedStyle(document.querySelector('.ProseMirror')).textAlign !== 'left') throw Error('Text must stay left-aligned');
            if (window.markup.snapshot() !== text) throw Error('Layout changed document');
          }
          const start = document.querySelector('.code-start'), end = document.querySelector('.code-end');
          if (getComputedStyle(start).borderTopLeftRadius !== '8px' || getComputedStyle(end).borderBottomRightRadius !== '8px') throw Error('Code-block corner mismatch');
          const middle = document.querySelector('.code:not(.code-start):not(.code-end)');
          if (getComputedStyle(middle).borderTopLeftRadius !== '0px') throw Error('Internal code line must stay flush');
          window.markup.mode(true);
          if (window.markup.snapshot() !== text) throw Error('Source mismatch');
          window.markup.mode(false);
          if (!window.markup.find('第二项')) throw Error('Search failed');
          window.markup.command('bold');
          window.markup.command('undo');
          if (window.markup.snapshot() !== text) throw Error('Undo mismatch');
          const headings = window.markup.outline();
          if (headings.length !== 1 || headings[0].title !== '中文标题') throw Error('Outline mismatch');
          if (!window.markup.goToHeading(1) || window.markup.goToHeading(9)) throw Error('Outline navigation mismatch');
          if (window.markup.snapshot() !== text) throw Error('Navigation changed content');
          const second = '# Finder open check\\n\\n中文路径、空格和 .markdown 扩展名。\\n';
          window.markup.load(second);
          if (window.markup.snapshot() !== second) throw Error('Second document mismatch');
          const table = 'Intro\\n\\n| Name | Count |\\n| --- | ---: |\\n| A | 1 |\\n\\n```mermaid\\ngraph TD\\n  A --> B\\n```\\n';
          window.markup.load(table);
          const grid = document.querySelector('.table-widget table');
          if (!grid || getComputedStyle(grid).borderTopLeftRadius !== '8px') throw Error('Table block missing');
          if (getComputedStyle(grid.querySelector('td.align-right')).textAlign !== 'right') throw Error('Table alignment lost');
          for (let i = 0; i < 200 && !document.querySelector('.mermaid-widget svg, .mermaid-widget.failed'); i++) await new Promise(r => setTimeout(r, 50));
          const diagram = document.querySelector('.mermaid-widget');
          if (!diagram?.querySelector('svg')) throw Error('Mermaid did not render: ' + diagram?.textContent);
          if (window.markup.snapshot() !== table) throw Error('Blocks changed document');
          return 'PASS: WKWebView load, source mode, search, format, undo, outline, heading navigation, tables, Mermaid, exact snapshot (corner-shape ' + (CSS.supports('corner-shape', 'squircle') ? 'supported' : 'unsupported') + ')';
        })()
        """, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .failure(let error): print("FAIL: \(error) \((error as NSError).userInfo)")
            case .success(let value): print(value ?? "Missing result"); self.passed = true
            }
            self.completed = true
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("FAIL: \(error) \((error as NSError).userInfo)"); completed = true
    }
}
let app = NSApplication.shared
let smoke = Smoke()
smoke.run(CommandLine.arguments[1])
let deadline = Date().addingTimeInterval(20)
while !smoke.completed && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
if !smoke.completed { print("FAIL: WKWebView timed out") }
exit(smoke.passed ? 0 : 1)
