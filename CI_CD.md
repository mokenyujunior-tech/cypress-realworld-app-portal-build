# CI/CD Pipeline - [deploy.yml](.github/workflows/deploy.yml)

## Overview

The PayFlow CI/CD pipeline is built on GitHub Actions and triggered automatically on every push to the `develop` branch without [skip ci]. It consists of three sequential jobs; CI quality checks, staging deployment, and production deployment saving approximately 10 to 15 minutes of deployment time by caching Yarn's global download cache across runs and reusing a single immutable build artifact across both the staging and production deployment jobs eliminating redundant installs and rebuilds entirely, alongside secrets management and zero-downtime deployments.

## Job 1 — CI Quality Checks

Job 1 is the gate. If anything here fails, the pipeline stops completely. Nothing deploys.

### Steps

**1. Checkout code**
Pulls the latest code from the `develop` branch onto the GitHub Actions runner.

**2. Set up Node.js**
Uses `actions/setup-node@v4` with `node-version-file: '.node-version'`. Pins the exact Node version the repo specifies rather than a hardcoded version. Also sets `cache: 'yarn'` which caches Yarn's global download cache. On runs where dependencies have not changed, packages install from cache instead of the internet, saving approximately 1 to 3 minutes per run.

**3. Install dependencies**
```bash
PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true yarn
```
The `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true` flag skips downloading a 300MB Chrome binary that is only needed for Cypress E2E tests and not for deployment.

**4. Copy mock AWS exports**
```bash
yarn copy:mock:awsexports && yarn copy:mock:awsexportses5
```
The app uses Amazon Cognito as an optional authentication provider. The build step requires mock AWS export files to exist even when Cognito is not being used. This step copies those mock files into place before the build runs.

**5. Type check**
```bash
yarn types
```
Validates all TypeScript types across the codebase. Catches type errors before they reach production.

**6. Lint**
```bash
yarn lint
```
Runs ESLint and Prettier checks across all `.ts`, `.js`, `.tsx` files. Enforces consistent code style. Any formatting issue fails the pipeline.

**7. Unit tests**
```bash
yarn test:unit:ci
```
Runs all unit tests using Vitest. If any test fails, the pipeline stops and nothing deploys.

**8. Build frontend**
```bash
yarn build
```
Vite compiles the React TypeScript source code in `src/` into optimised static JavaScript, CSS, and HTML files inside the `build/` folder. `VITE_BACKEND_PORT=3001` is set here at **build time**. Vite inserts this value permanently into the compiled JavaScript bundle. 
This is a critical detail: `VITE_BACKEND_PORT` cannot be changed at runtime in Azure after the bundle is compiled.

**9. Fix prestart script for Azure**
```bash
node scripts/fix-prestart.js
```
This step rewrites `package.json` before the artifact is uploaded. It replaces two broken scripts:

- `prestart`: Replaces `ncp` (a third-party tool that breaks on Azure due to Oryx symlink issues) with Node.js's built-in `fs.copyFileSync` which requires nothing from `node_modules`
- `start`: Replaces the original `cross-env NODE_ENV=development concurrently yarn:start:react yarn:start:api` command with `node node_modules/ts-node/dist/bin.js -P tsconfig.tsnode.json backend/app.ts`, calling `ts-node`'s real JavaScript entrypoint directly, bypassing the broken `.bin` symlinks entirely

**10. Upload artifact**
```bash
actions/upload-artifact@v4
  name: payflow-build
  path: .
  retention-days: 1
```
Uploads the entire workspace, `build/`, `backend/`, `data/`, `node_modules/`, and the rewritten `package.json`, as a single immutable artifact named `payflow-build`. Both Job 2 and Job 3 download this exact artifact. Neither job rebuilds anything.

---

## Job 2 — Deploy to Staging Slot

Runs automatically after Job 1 passes. No human approval needed.

```yaml
needs: ci
environment:
  name: staging
```

The `needs: ci` dependency means Job 2 only starts when Job 1 completes successfully. The `environment: staging` maps to the GitHub Environment named `staging` which holds the `AZURE_WEBAPP_PUBLISH_PROFILE` secret, the XML credential file that authenticates GitHub Actions to deploy to the staging slot specifically.

### Steps

**1. Download artifact**
Downloads the `payflow-build` artifact uploaded by Job 1. This is the exact same compiled binary. Nothing is rebuilt.

**2. Deploy to Staging Slot**
```yaml
uses: azure/webapps-deploy@v3
with:
  app-name: payflow-production
  slot-name: staging
  publish-profile: ${{ secrets.AZURE_WEBAPP_PUBLISH_PROFILE }}
  package: .
```
The `slot-name: staging` parameter targets the staging deployment slot specifically and not the production slot. The `publish-profile` authenticates the deployment using the staging slot's credential file stored in GitHub Secrets.

---

## Job 3 — Deploy to Production

Only runs after Job 2 passes. **Pauses for manual approval** before deploying. Activated by configuring a Required Reviewer.

```yaml
needs: deploy-staging
environment:
  name: production
```

The `environment: production` maps to the GitHub Environment named `production` which has **Required Reviewers** configured. When Job 3 starts, the pipeline shows an orange **Review deployments** banner and waits. A reviewer must click Approve before anything deploys to production.

This is the manual gate. It exists to ensure a human verifies staging is working correctly before production receives the same code.

### Steps

**1. Download artifact**
Downloads the same `payflow-build` artifact. This is the same binary that was just tested and verified on staging.

**2. Deploy to Production**
```yaml
uses: azure/webapps-deploy@v3
with:
  app-name: payflow-production
  publish-profile: ${{ secrets.AZURE_WEBAPP_PUBLISH_PROFILE }}
  package: .
```
No `slot-name` parameter — this deploys directly to the production slot using the production publish profile from the `production` GitHub Environment secret.

---

## Phase 8: Verify Everything Works

**Step 1:** Pushed to `develop` and went to the GitHub Actions tab. Watched the CI Quality Checks job pass through all steps.Swap to Production showed the orange Review deployments banner.

![Screenshot 2026-05-13 153241](Images/Screenshot%202026-05-13%20153241.png)

**Step 2:** Before approving, opened the staging URL `https://payflow-production-staging.azurewebsites.net` and confirmed the PayFlow login page never loaded. Then I encountered my first error

![Screenshot 2026-05-13 154731](Images/Screenshot%202026-05-13%20154731.png)

---

## Problems Faced and Solutions

### Problems and Solutions

- **1. `ncp: not found` on first deployment:** The `prestart` script called `ncp` to copy mock AWS export files. Azure's Oryx build engine compresses `node_modules` into a `tar.gz` at deployment and extracts it at container startup. By the time the startup script ran, `ncp` was not accessible. Either it was excluded from the archive or not yet extracted.

![Screenshot 2026-05-13 160244](Images/Screenshot%202026-05-13%20160244.png)

**Solution:** Created `scripts/fix-prestart.js`, a script that runs in GitHub Actions Job 1 before the artifact is uploaded, replacing `ncp` with Node.js's built-in `fs.copyFileSync` which requires nothing from `node_modules`. 
Added the file to `.prettierignore` as well to prevent Prettierfrom breaking the string escaping during CI.

![Screenshot 2026-05-17 015415](Images/Screenshot%202026-05-17%20015415.png)

![Screenshot 2026-05-17 021218](Images/Screenshot%202026-05-17%20021218.png)

![Screenshot 2026-05-17 031301](Images/Screenshot%202026-05-17%20031301.png)

---

- **2. `cross-env: not found`:** After fixing `ncp`, the `prestart` script was replaced successfully but the `start` script still called `cross-env` to set `NODE_ENV=development` before starting the app. `cross-env` is a third-party package that lives in `node_modules/.bin`. The same symlink problem as `ncp`. Azure could not find it at startup.

![Screenshot 2026-05-17 123933](Images/Screenshot%202026-05-17%20123933.png)

**Solution:** Updated `fix-prestart.js` to rewrite the `start` script entirely, replacing the original command with a direct `ts-node` call to the backend, bypassing `cross-env`, `concurrently`, and the Vite development server entirely.

![Screenshot 2026-05-17 133321](Images/Screenshot%202026-05-17%20133321.png)

---

- **3. `ts-node: not found`:** After fixing `cross-env`, the start script called `ts-node` through `node_modules/.bin/ts-node`. That `.bin` entry is a shell script symlink. When GitHub Actions zips the artifact and Kudu extracts it, symlinks break.

![Screenshot 2026-05-17 180238](Images/Screenshot%202026-05-17%20180238.png)

**Solution:** Updated `fix-prestart.js` to call `ts-node` through its  real JavaScript file directly, bypassing the broken `.bin` symlink entirely. Then added `PORT=8080` as an App Service environment variables so the backend knew which port to listen on and `VITE_BACKEND_PORT=8080` as well so getBackendPort() reads to start Express. Azure's health check got a response, the app was marked healthy, and the backend loaded.

![Screenshot 2026-05-19 203235](Images/Screenshot%202026-05-19%20203235.png)

![Screenshot 2026-05-19 205357](Images/Screenshot%202026-05-19%20205357.png)

![Screenshot 2026-05-19 205600](Images/Screenshot%202026-05-19%20205600.png)

---

- **4. Root route blocking React from loading:** The Express backend had `app.get("/", res.send("Cypress Realworld App - backend"))` under backend/app.ts lines 98, 99, and 100 defined above the static file middleware, intercepting every browser request before React could load.

![Screenshot 2026-05-20 003200](Images/Screenshot%202026-05-20%20003200.png)

**Solution:** Deleted those three lines entirely. Requests to `/` now fall through to `express.static("../build")` which serves `index.html`.

![Screenshot 2026-05-20 004322](Images/Screenshot%202026-05-20%20004322.png)

![Screenshot 2026-05-20 004656](Images/Screenshot%202026-05-20%20004656.png)

---

- **5. `localhost:3001` hardcoded in 36 places across 9 machine files:** The React frontend compiled with `VITE_BACKEND_PORT=3001` baked permanently into the JavaScript bundle. Every API call went to `http://localhost:3001` and on Azure there is no localhost.

![Screenshot 2026-05-21 023122](Images/Screenshot%202026-05-21%20023122.png)

**Solution:** Manually editing 36 instances across 9 files was too risky. One missed instance or a typo would cause a silent bug in production. I created a bash script using sed, a command line tool that finds and replaces text in files, which did all 36 replacements across 9 files automatically, and the script added `apiBaseUrl` to `src/utils/portUtils.ts` returning `""` in production and `http://localhost:${backendPort}` in development. 

![Screenshot 2026-05-22 164738](Images/Screenshot%202026-05-22%20164738.png)

---

- **6. `import.meta.env.PROD` crashing the backend:** After running `bash fix-backend-urls.sh` and `yarn dev` the URL fix used `import.meta.env.PROD` to detect production in `portUtils.ts`. Vite understands `import.meta` but Node.js does not. The backend imports `portUtils.ts` and crashed immediately.

![Screenshot 2026-05-22 164800](Images/Screenshot%202026-05-22%20164800.png)

![Screenshot 2026-05-22 164810](Images/Screenshot%202026-05-22%20164810.png)

**Solution:** I replaced it with `process.env.NODE_ENV === "production"` which both runtimes understand.

![Screenshot 2026-05-22 164934](Images/Screenshot%202026-05-22%20164934.png)

---

- **7. Busy Ports:** After the previous fix, I encountered another minor error, where the server failed to start on a number of ports.

![Screenshot 2026-05-22 165210](Images/Screenshot%202026-05-22%20165210.png)

**Solution:** I checked all the ports that were rejected and what was running on them and shutdown all the services and then `yarn dev` succeeded.

![Screenshot 2026-05-22 170730](Images/Screenshot%202026-05-22%20170730.png)

![Screenshot 2026-05-22 171629](Images/Screenshot%202026-05-22%20171629.png)

---

**Step 3, Wrong time:** Clicked Review deployments on the Swap to Production job, checked the box next to production, and clicked Approve and deploy. Watched the swap complete.

---

- **8. 401 Unauthorized Error:** After inputting the right credentials, saw this error after using `ctrl + f12`

![Screenshot 2026-05-25 013715](Images/Screenshot%202026-05-25%20013715.png)

**Solution:** The error resolved after the correct code from my final pipeline, which included the `apiBaseUrl` fix replacing all 36 hardcoded `localhost` URLs across 9 machine files, and the `process.env.NODE_ENV` fix replacing the broken `import.meta.env.PROD` in `portUtils.ts`, had fully deployed and stabilized on Azure. The backend initialized correctly and login succeeded.

![Screenshot 2026-05-25 014810](Images/Screenshot%202026-05-25%20014810.png)

![Screenshot 2026-05-25 015051](Images/Screenshot%202026-05-25%20015051.png)

---

**Step 4:** Verified the full secrets chain on both slots:
- Clicked `SESSION-SECRET-PRODUCTION` and confirmed the value was hidden
- Checked `SESSION_SECRET` and it showed `@Microsoft.KeyVault(...)` with Status: Resolved
- Went to staging slot and checked `SESSION_SECRET` which showed `@Microsoft.KeyVault(...)` referencing `SESSION-SECRET-STAGING` with Status: Resolved
- Checked GitHub Actions logs across completed runs and no secret values appeared anywhere in the output