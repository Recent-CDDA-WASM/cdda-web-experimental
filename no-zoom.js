(function () {  
  // Block browser page-zoom (Ctrl+wheel and Ctrl +/-/0).  
  window.addEventListener("wheel", function (e) {  
    if (e.ctrlKey) e.preventDefault();  
  }, { passive: false });  
  
  window.addEventListener("keydown", function (e) {  
    if ((e.ctrlKey || e.metaKey) &&  
        (e.key === "+" || e.key === "-" || e.key === "=" || e.key === "0")) {  
      e.preventDefault();  
    }  
  }, { passive: false });  
})();
