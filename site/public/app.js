// Load the Godot Web demo on request (the engine is ~40 MB), with gamepad access.
const loadButton = document.querySelector("[data-load-demo]");
const demoStage = document.querySelector("[data-demo-stage]");

loadButton?.addEventListener("click", () => {
  const frame = document.createElement("iframe");
  frame.src = "/demo/";
  frame.title = "godot-controllers web demo";
  frame.allow = "fullscreen; gamepad; clipboard-write";
  loadButton.remove();
  demoStage.append(frame);
  frame.focus();
});
