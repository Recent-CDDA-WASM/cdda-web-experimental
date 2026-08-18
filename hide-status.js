(function () {  
  function hide() {  
    var el = document.getElementById("loading-message");  
    if (el) el.style.display = "none";  
  }  
  // Primary: the stock upstream signal, in case it does fire.  
  window.addEventListener("menuready", hide);  
  // Fallbacks for this SDL3 build where menuready may never fire:  
  window.addEventListener("keydown", hide, { once: true });  
  window.addEventListener("mousedown", hide, { once: true });  
  // Safety net: if "Starting..." is still showing a while after load,  
  // the module is already running, so drop the stale overlay.  
  window.addEventListener("load", function () {  
    setTimeout(hide, 20000);  
  });  
})();
