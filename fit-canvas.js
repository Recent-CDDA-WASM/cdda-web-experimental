(function () {  
  function fit() {  
    var c = document.getElementById("canvas");  
    if (!c) return;  
    c.style.position = "absolute";  
    c.style.top = "0";  
    c.style.left = "0";  
    c.style.width = "100vw";  
    c.style.height = "100vh";  
    // preserve aspect ratio; use "fill" instead if you want it stretched  
    c.style.objectFit = "contain";  
  }  
  window.addEventListener("load", fit);  
  window.addEventListener("resize", fit);  
  // canvas is created late by the wasm module, so keep re-applying briefly  
  var n = 0, t = setInterval(function () {  
    fit();  
    if (++n > 40) clearInterval(t); // ~10s at 250ms  
  }, 250);  
})();
