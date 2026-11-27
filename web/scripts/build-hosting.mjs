// Builds the web client into the Hosting site, at /app/, for the Firebase
// project being deployed. Run by `firebase deploy` as the hosting predeploy
// step (backend/Firebase/firebase.json), which sets GCLOUD_PROJECT.
//
//   teacher-in-a-moment-staging → .env.staging
//   teacher-in-a-moment         → .env.prod, once that project has a Web app
//
// A project without a config gets no app: the build folder is removed, so a
// site deploy never ships another project's build (or the emulator one).

import { execSync } from "node:child_process";
import { existsSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const web = join(dirname(fileURLToPath(import.meta.url)), "..");
const out = join(web, "..", "backend", "Firebase", "public", "app");
const MODES = { "teacher-in-a-moment-staging": "staging", "teacher-in-a-moment": "prod" };

const project = process.env.GCLOUD_PROJECT ?? process.argv[2] ?? "";
const mode = MODES[project];

if (!mode || !existsSync(join(web, `.env.${mode}`))) {
  rmSync(out, { recursive: true, force: true });
  console.warn(`[web] no web config for project "${project}"; the site deploys without /app/`);
  process.exit(0);
}

if (!existsSync(join(web, "node_modules"))) execSync("npm ci", { cwd: web, stdio: "inherit" });
console.log(`[web] building /app/ for ${project} (mode ${mode})`);
execSync(`npx tsc -b && npx vite build --mode ${mode}`, { cwd: web, stdio: "inherit" });
