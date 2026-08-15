import WebKit
import AppKit
import Foundation

// 诊断2：加载 harness 后，尝试点击「设置」，观察设置面板（插件/模型等）是否出现。
let app = NSApplication.shared
let config = WKWebViewConfiguration()
let userContent = WKUserContentController()
let captureJS = """
(function(){
  window.__dshDiag = { errors: [], console: [] };
  window.onerror = function(msg, src, line, col, err) {
    window.__dshDiag.errors.push(String(msg) + ' @ ' + src + ':' + line + ':' + col);
    return false;
  };
  window.addEventListener('unhandledrejection', function(e) {
    window.__dshDiag.errors.push('unhandledrejection: ' + String(e.reason));
  });
  ['error','warn'].forEach(function(m){
    var orig = console[m];
    console[m] = function(){
      window.__dshDiag.console.push('['+m+'] ' + Array.prototype.map.call(arguments, function(a){
        try { return typeof a === 'object' ? JSON.stringify(a).slice(0,200) : String(a) } catch(e){ return String(a) }
      }).join(' ').slice(0,300));
      if (orig) orig.apply(console, arguments);
    };
  });
})();
"""
userContent.addUserScript(WKUserScript(source: captureJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
config.userContentController = userContent

let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1400, height: 900), configuration: config)

final class Nav: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish?() }
}
let nav = Nav()
webView.navigationDelegate = nav

func eval(_ js: String, _ cb: @escaping (String) -> Void) {
    webView.evaluateJavaScript(js) { r, e in
        cb(e != nil ? "EVAL ERROR: \(e!)" : (r as? String ?? String(describing: r)))
    }
}

func snapshot(_ label: String, _ cb: @escaping (String) -> Void) {
    eval("""
    (function(){
      var t = document.body ? document.body.innerText : '';
      var has = function(s){ return t.indexOf(s) >= 0 };
      return JSON.stringify({
        label: '\(label)',
        text: t.slice(0, 3000),
        hasNewSession: has('新会话'), hasSettings: has('设置'), hasPlugins: has('插件'), hasModel: has('模型'),
        hasStandardMode: has('标准模式'), hasCreate: has('创造'), hasDefaultModel: has('默认模型'),
        errors: (window.__dshDiag||{}).errors || [],
        console: ((window.__dshDiag||{}).console||[]).slice(-20)
      });
    })()
    """, cb)
}

func clickText(_ t: String, _ cb: @escaping (String) -> Void) {
    eval("""
    (function(){
      var target = '\(t)';
      var all = document.querySelectorAll('button, [role="button"], a, div, span');
      var best = null, bestDepth = -1;
      for (var i=0;i<all.length;i++){
        var e = all[i];
        var own = '';
        for (var j=0;j<e.childNodes.length;j++){
          if (e.childNodes[j].nodeType === 3) own += e.childNodes[j].nodeValue;
        }
        own = own.trim();
        if (own === target || own.indexOf(target) >= 0) {
          if (own.length > bestDepth) { best = e; bestDepth = own.length; }
        }
      }
      if (best) { best.click(); return 'clicked "' + target + '"'; }
      return 'NOT FOUND: ' + target;
    })()
    """, cb)
}

nav.onFinish = {
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        snapshot("before") { before in
            print("=== before ===\n" + before + "\n")
            clickText("设置") { clickResult in
                print("=== click 设置 ===\n" + clickResult + "\n")
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    snapshot("after-settings") { after in
                        print("=== after settings ===\n" + after + "\n")
                        exit(0)
                    }
                }
            }
        }
    }
}

webView.load(URLRequest(url: URL(string: "http://127.0.0.1:3080/")!))
app.run()
