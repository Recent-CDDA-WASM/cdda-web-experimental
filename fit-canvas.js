(function () {  
  function fit() {  
    var c = document.getElementById("canvas");  
    if (!c) return;  
    c.style.setProperty("position", "absolute", "important");  
    c.style.setProperty("top", "0", "important");  
    c.style.setProperty("left", "0", "important");  
    c.style.setProperty("width", "100vw", "important");  
    c.style.setProperty("height", "100vh", "important");  
    c.style.setProperty("object-fit", "contain", "important");  
  }  
  
  function attach() {  
    var c = document.getElementById("canvas");  
    if (!c) { setTimeout(attach, 200); return; }  
    fit();  
    // Re-apply whenever SDL/emscripten rewrites the canvas size or style.  
    new MutationObserver(fit).observe(c, {  
      attributes: true,  
      attributeFilter: ["style", "width", "height"]  
    });  
  }  
  
  window.addEventListener("load", attach);  
  window.addEventListener("resize", fit);  
})();
