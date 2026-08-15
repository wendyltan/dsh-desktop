import WebKit
import AppKit
import Foundation

// 诊断：用 WKWebView 加载 harness 页面，抓取渲染文本、JS 错误、UA 等。
let app = NSApplication.shared
let config = WKWebViewConfiguration()
let userContent = WKUserContentController()
let captureJS = """
(function(){
  window.__dshDiag = { errors: [], console: [] };
  window.onerror = function(msg, src, line, col, err) {
    window.__dshDiag.errors.push(String(msg) + ' @ ' + src + ':' + line + ':' + col + (err && err.stack ? ' | ' + String(err.stack).slice(0,400) : ''));
    return false;
  };
  window.addEventListener('unhandledrejection', function(e) {
    var r = e.reason;
    window.__dshDiag.errors.push('unhandledrejection: ' + (r && r.message ? r.message : String(r)));
  });
  ['log','warn','error'].forEach(function(m){
    var orig = console[m];
    console[m] = function(){
      window.__dshDiag.console.push('['+m+'] ' + Array.prototype.map.call(arguments, function(a){
        try { return typeof a === 'object' ? JSON.stringify(a).slice(0,300) : String(a) } catch(e){ return String(a) }
      }).join(' '));
      if (orig) orig.apply(console, arguments);
    };
  });
})();
"""
userContent.addUserScript(WKUserScript(source: captureJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
config.userContentController = userContent

let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)

final class Nav: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish?() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("PROVISIONAL FAIL: \(error.localizedDescription)")
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("NAV FAIL: \(error.localizedDescription)")
        exit(1)
    }
}
let nav = Nav()
webView.navigationDelegate = nav

nav.onFinish = {
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
        webView.evaluateJavaScript("""
        (function(){
          var d = window.__dshDiag || {errors:[], console:[]};
          return JSON.stringify({
            ua: navigator.userAgent,
            title: document.title,
            boot: (typeof window.__DSH_BOOT__ !== 'undefined'),
            bootEntries: (typeof window.__DSH_BOOT__ !== 'undefined' && window.__DSH_BOOT__.entries) ? window.__DSH_BOOT__.entries.length : 0,
            text: document.body ? document.body.innerText.slice(0, 2500) : '',
            errors: d.errors.slice(0, 30),
            console: d.console.slice(-40)
          });
        })()
        """) { result, error in
            if let error = error { print("EVAL ERROR: \(error)") }
            else if let s = result as? String { print(s) }
            exit(0)
        }
    }
}

webView.load(URLRequest(url: URL(string: "http://127.0.0.1:3080/")!))
app.run()
