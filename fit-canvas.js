(function () {  
  function fit() {  
    var c = document.getElementById("canvas");  
    if (!c) return;  
    c.style.position = "absolute";  
    c.style.top = "0";  
    c.style.left = "0";  
    c.style.width = "100vw";  
    c.style.height = "100vh";  
    c.style.objectFit = "contain";  
  
    // On-screen readout so you can diagnose without DevTools.  
    var box = document.getElementById("__fitdbg");  
    if (!box) {  
      box = document.createElement("div");  
      box.id = "__fitdbg";  
      box.style.cssText =  
        "position:fixed;top:0;right:0;z-index:99999;" +  
        "background:black;color:lime;font:12px monospace;" +  
        "padding:2px 6px;pointer-events:none;";  
      document.body.appendChild(box);  
    }  
    box.textContent =  
      "canvas buffer " + c.width + "x" + c.height +  
      "  window " + window.innerWidth + "x" + window.innerHeight +  
      "  DPR " + window.devicePixelRatio;  
  }  
  
  // Re-apply whenever SDL rewrites the canvas attributes/style.  
  function watch() {  
    var c = document.getElementById("canvas");  
    if (!c) return false;  
    new MutationObserver(fit).observe(c, {  
      attributes: true,  
      attributeFilter: ["width", "height", "style"]  
    });  
    fit();  
    return true;  
  }  
  
  window.addEventListener("load", fit);  
  window.addEventListener("resize", fit);  
  
  // Keep trying until the canvas exists, then attach the observer.  
  var n = 0, t = setInterval(function () {  
    if (watch() || ++n > 120) clearInterval(t); // up to ~30s  
  }, 250);  
})();
