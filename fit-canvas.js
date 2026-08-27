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
  
  // Re-apply whenever SDL/emscripten overwrites the canvas style attr.  
  function watch() {  
    var c = document.getElementById("canvas");  
    if (!c) return false;  
    fit();  
    var mo = new MutationObserver(function () { fit(); });  
    mo.observe(c, { attributes: true, attributeFilter: ["style", "width", "height"] });  
    return true;  
  }  
  
  window.addEventListener("load", function () {  
    if (watch()) return;  
    // canvas is created late by the wasm module; poll until it exists.  
    var n = 0, t = setInterval(function () {  
      if (watch() || ++n > 80) clearInterval(t); // ~20s  
    }, 250);  
  });  
})();
