// diffy-web frontend bootstrap: wizard mode vs. viewer mode.
import "./style.css";
import { api } from "./api.ts";
import { initMetrics } from "./metrics.ts";
import { Viewer, type ViewerOptions } from "./viewer.ts";
import { Wizard } from "./wizard.ts";

/** URL params double as the headless-test hooks of the native app:
 *  ?file=N ?change=N ?expand-all ?filter=q ?wrap=0|1 ?theme=light|dark */
function parseOptions(): ViewerOptions {
  const p = new URLSearchParams(location.search);
  const options: ViewerOptions = {};
  const theme = p.get("theme");
  if (theme === "light" || theme === "dark") {
    document.documentElement.dataset.theme = theme;
  }
  if (p.has("file")) {
    const n = Number.parseInt(p.get("file")!, 10);
    if (Number.isFinite(n)) options.file = n;
  }
  if (p.has("change")) {
    const n = Number.parseInt(p.get("change")!, 10);
    if (Number.isFinite(n)) options.change = n;
  }
  if (p.has("expand-all")) options.expandAll = true;
  if (p.has("filter")) options.filter = p.get("filter")!;
  if (p.has("wrap")) options.wrap = p.get("wrap") === "1" || p.get("wrap") === "true";
  return options;
}

async function main(): Promise<void> {
  initMetrics();
  const app = document.getElementById("app")!;
  const options = parseOptions();

  let state;
  try {
    state = await api.state();
  } catch (err) {
    app.innerHTML = `<div class="center-message"></div>`;
    (app.firstElementChild as HTMLElement).textContent =
      `Cannot reach the diffy server.\n${err instanceof Error ? err.message : err}`;
    return;
  }

  if (state.mode === "wizard") {
    const wizard = new Wizard((session) => {
      app.textContent = "";
      app.appendChild(new Viewer(session, options).root);
    });
    app.appendChild(wizard.root);
  } else {
    app.appendChild(new Viewer(state.session, options).root);
  }
}

void main();
