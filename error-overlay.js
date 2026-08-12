(function () {  
  var visible = false;  
  
  function box() {  
    var d = document.getElementById("erroroverlay");  
    if (!d) {  
      d = document.createElement("div");  
      d.id = "erroroverlay";  
      d.style.cssText = "position:fixed;left:0;right:0;bottom:0;max-height:50%;overflow:auto;background:rgba(0,0,0,0.92);color:rgb(255,90,90);font:12px/1.4 monospace;white-space:pre-wrap;z-index:2147483646;padding:8px;border-top:2px solid rgb(255,90,90);display:none";  
      (document.body || document.documentElement).appendChild(d);  
    }  
    return d;  
  }  
  
  function btn() {  
    var b = document.getElementById("erroroverlaybtn");  
    if (!b) {  
      b = document.createElement("button");  
      b.id = "erroroverlaybtn";  
      b.textContent = ">_";  
      b.title = "Open/close error terminal";  
      b.style.cssText = "position:fixed;right:6px;bottom:6px;width:26px;height:26px;padding:0;font:12px monospace;background:rgba(0,0,0,0.85);color:rgb(255,90,90);border:1px solid rgb(255,90,90);border-radius:4px;z-index:2147483647;cursor:pointer;opacity:0.6";  
      b.onmouseenter = function () { b.style.opacity = "1"; };  
      b.onmouseleave = function () { b.style.opacity = "0.6"; };  
      b.onclick = function () {  
        visible = !visible;  
        box().style.display = visible ? "block" : "none";  
      };  
      (document.body || document.documentElement).appendChild(b);  
    }  
    return b;  
  }  
  
  function log(tag, msg) {  
    try { box().textContent += "[" + tag + "] " + msg + "\n"; } catch (e) {}  
  }  
  
  window.addEventListener("load", function () {  
    btn(); // make sure the toggle button exists once the page is up  
    log("STATUS", "crossOriginIsolated=" + self.crossOriginIsolated + "  SharedArrayBuffer=" + (typeof SharedArrayBuffer));  
  });  
  window.addEventListener("error", function (e) {  
    log("JS ERROR", (e.message || e.error) + " @ " + e.filename + ":" + e.lineno);  
    if (e.error && e.error.stack) log("STACK", e.error.stack);  
  });  
  window.addEventListener("unhandledrejection", function (e) {  
    var r = e.reason; log("PROMISE", (r && r.message) || r);  
    if (r && r.stack) log("STACK", r.stack);  
  });  
  var ce = console.error;  
  console.error = function () { log("ERR", Array.prototype.join.call(arguments, " ")); return ce.apply(console, arguments); };  
  var cw = console.warn;  
  console.warn = function () { log("WARN", Array.prototype.join.call(arguments, " ")); return cw.apply(console, arguments); };  
  var al = window.alert;  
  window.alert = function (m) { log("ALERT", m); };  
})();
