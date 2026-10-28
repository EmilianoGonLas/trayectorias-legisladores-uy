// Un solo manejador de clics para todo lo "enlazable": nombres de personas y columnas del gráfico.
document.addEventListener("click", function (e) {
  var p = e.target.closest("[data-persona]");
  if (p) { e.preventDefault(); Shiny.setInputValue("abrir", +p.dataset.persona, { priority: "event" }); return; }
  var l = e.target.closest("[data-leg]");
  if (l) { Shiny.setInputValue("leg_click", +l.dataset.leg, { priority: "event" }); }
});
$(document).on("shiny:connected", function () {
  Shiny.addCustomMessageHandler("arriba", function (msg) { window.scrollTo({ top: 0, behavior: "smooth" }); });
});
