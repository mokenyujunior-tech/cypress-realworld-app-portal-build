# PayFlow Full-Stack App Deployment on Azure

A production-grade Node.js + React application deployed to Azure with a three-stage automated pipeline, secrets management, and zero-downtime slot swaps.

---

## 1. Architecture

```
                        ┌─────────────────────────────────────────┐
                        │             GitHub Repository            │
                        │           (develop branch push)          │
                        └──────────────────┬──────────────────────┘
                                           │
                        ┌──────────────────▼──────────────────────┐
                        │         GitHub Actions Pipeline          │
                        │                                          │
                        │  Job 1: CI Quality Checks                │
                        │  ├── Type check · Lint · Unit Tests      │
                        │  ├── yarn build (Vite frontend)          │
                        │  ├── fix-prestart.js (Azure fix)         │
                        │  └── Upload artifact: payflow-build      │
                        │                                          │
                        │  Job 2: Deploy to Staging Slot           │
                        │  └── Download → Deploy (auto)            │
                        │                                          │
                        │  Job 3: Swap to Production               │
                        │  └── Manual Approval Gate → Deploy       │
                        └──────┬───────────────────┬──────────────┘
                               │                   │
               ┌───────────────▼───┐         ┌─────▼─────────────────┐
               │  Staging Slot     │         │  Production Slot       │
               │  App Service B1   │  swap   │  App Service B1        │
               │  (auto deploy)    │ ──────► │  (manual approval)     │
               └───────────────────┘         └────────────────────────┘
                        │                               │
               ┌────────▼────────┐           ┌──────────▼────────────┐
               │  Key Vault      │           │  Key Vault             │
               │  (Staging)      │           │  (Production)          │
               │  SESSION_SECRET │           │  SESSION_SECRET        │
               │  PAGE_SIZE      │           │  PAGE_SIZE             │
               └─────────────────┘           └───────────────────────┘
```

---

## 2. Tools Used

### Azure Services

- **Resource Group (rg-payflow):** Single resource group containing all PayFlow resources. Scoped this way so everything can be tracked, billed, and destroyed together.

- **Azure App Service Plan (Basic B1):** The compute tier running the application. B1 was chosen over Free (F1) specifically because deployment slots are not available on Free tier. B1 supports custom deployment slots — the foundation of the zero-downtime strategy.

- **Azure App Service — payflow-production:** The main App Service hosting both frontend and backend. The Express backend serves the React build as static files through the SPA fallback, meaning one App Service handles everything — no separate static hosting needed.

- **Deployment Slot — staging:** A mirror environment running inside the same App Service. Staging deploys automatically on every push. Production only receives code after manual approval. The slot swap is zero-downtime — Azure warms up the new version before routing any traffic.

- **Azure Key Vault (x2 — staging and production):** Stores `SESSION_SECRET` and `PAGINATION_PAGE_SIZE` as secrets. Neither value ever appears in code, environment files, or the GitHub repository. The App Service reads them at runtime via Key Vault references (`@Microsoft.KeyVault(SecretUri=...)`).

- **Managed Identity:** Grants each App Service slot its own identity in Microsoft Entra ID. This identity is assigned the Key Vault Secrets User role, which is what allows the App Service to read secrets without storing any credentials anywhere.

### CI/CD

- **GitHub Actions:** Three-job pipeline triggered on every push to the `develop` branch. One build artifact is created in Job 1 and reused by both Job 2 and Job 3 — staging and production always run the exact same compiled binary.

- **GitHub Environments (staging + production):** Each environment holds its own `AZURE_WEBAPP_PUBLISH_PROFILE` secret — the XML credential file downloaded from Azure that authenticates GitHub Actions to deploy to that specific slot.

### Application

- **PayFlow (cypress-realworld-app):** A full-stack financial transactions app. React frontend compiled with Vite. Express backend running on Node.js via ts-node. LowDB JSON file as the database. The app was originally built for local development only — deploying it to Azure required solving several infrastructure and code problems that the original developers never anticipated.

---

## 3. The Problem This Project Solves

### Why This Project Exists

Most tutorials show you how to deploy a simple app where everything works the first time. This project was different from the start.

PayFlow was a real-world application handed over by a mentor with one instruction: deploy it to Azure. No deployment configuration existed. No production environment had ever been considered. The app had hardcoded `localhost` URLs in 36 places across 11 files, a startup sequence that depended on tools that break in Azure's runtime environment, and no secrets management of any kind.

The goal was to take a developer's local-only application and transform it into a professionally deployed, production-grade cloud application — with a real CI/CD pipeline, proper secrets management, zero-downtime deployments, and environment separation between staging and production.

### What This Deployment Delivers

- **Zero-downtime deployments** — staging warms up before production ever receives traffic. The old production code stays in the staging slot and can be swapped back instantly if something is wrong.

- **Secrets never in code** — `SESSION_SECRET` and `PAGINATION_PAGE_SIZE` live exclusively in Azure Key Vault. The application reads them through Managed Identity at runtime without any credentials stored anywhere.

- **Human approval before production** — the pipeline pauses after staging and waits for a reviewer to approve before anything touches production. Automation handles the work. A human makes the final call.

- **One build, two deployments** — the frontend is compiled exactly once in Job 1. The same artifact deploys to staging and then to production. Staging and production are guaranteed to run identical code.

- **Environment separation** — staging and production each have their own Key Vault, their own secrets, their own publish profile. No configuration crosses the boundary accidentally.

---

## 4. Prerequisites

Before starting, you need:

- **An active Azure subscription** with permission to create Resource Groups, App Service Plans, App Services, Key Vaults, and Managed Identities

- **A GitHub account** with a fork of the PayFlow repository and permission to create Environments and Secrets under Settings

- **Azure CLI installed** — used to verify resources and diagnose issues during deployment

- **Node.js and Yarn installed locally** — to run `yarn dev` and verify the app works before deploying

- **Git Bash (on Windows)** — required to run the bash fix scripts locally

---

## 5. Problems Faced and Solutions

**`ncp: not found` on first deployment**
The `prestart` script called `ncp` which lives in `node_modules`. Azure's Oryx build system compresses `node_modules` into a `tar.gz` for faster cold starts. When the app started, the archive hadn't been extracted yet — `ncp` was unreachable.
**Solution:** Replaced `ncp` with native Node.js `fs.copyFileSync` via `fix-prestart.js`, which runs at build time inside GitHub Actions before the artifact is uploaded.

---

**`ts-node: not found` — broken symlink**
After fixing `ncp`, the backend tried to start using `node_modules/.bin/ts-node`. This is a symlink. When GitHub Actions zips the artifact and Azure extracts it, symlinks break — the pointer exists but points to nothing.
**Solution:** Called `node node_modules/ts-node/dist/bin.js` directly, bypassing the symlink entirely.

---

**`Still waiting...` infinite loop**
An early version of `startup.sh` had a `while` loop checking for `ts-node` to appear in `node_modules/.bin`. Since the symlink was always broken, the loop ran forever and the container locked up permanently.
**Solution:** Cleared the startup command in Azure Portal to break the deadlock.

---

**`cross-env: not found` and `nyc: not found`**
After bypassing the ts-node symlink, the start command still contained `cross-env` and `nyc` — both live in `node_modules` and both failed for the same reason as `ncp`.
**Solution:** Stripped both from the start command in `fix-prestart.js`.

---

**`Cannot find module 'tsconfig-paths/register'`**
The `-r tsconfig-paths/register` flag passed to ts-node tried to preload `tsconfig-paths` — another broken symlink.
**Solution:** Removed the flag. The backend doesn't use TypeScript path aliases so there was no functional impact.

---

**`import.meta.env.PROD` crashing the backend**
The URL fix script added `import.meta.env.PROD` to detect production in `portUtils.ts`. Vite understands `import.meta` — Node.js does not. The backend crashed immediately on startup.
**Solution:** Replaced with `process.env.NODE_ENV === "production"` which both runtimes understand.

---

**`ERR_CONNECTION_REFUSED` — localhost hardcoded in 36 places**
Even after the backend started, every API call from the frontend failed. All 9 machine files called `http://localhost:${backendPort}/endpoint`. On Azure there is no localhost.
**Solution:** Added `apiBaseUrl` to `portUtils.ts` and ran `fix-backend-urls.sh` to replace all 36 instances automatically.

---

**Key Vault references showing `Configured` but not `Resolved`**
The App Service showed the Key Vault references as saved but the app couldn't read the secrets.
**Solution:** The Managed Identity hadn't been granted the Key Vault Secrets User role yet. Assigning the role and waiting a few minutes for Azure to propagate it changed the status to Resolved.

---

## 7. Lessons Learned and Future Improvements

### Lessons Learned

- **`Configured` and `Resolved` are not the same thing in Azure Key Vault references.** Configured means the reference syntax is saved. Resolved means the App Service Managed Identity has permission to actually read the secret. Both must be true.

- **Vite bakes environment variables into the bundle at build time, not runtime.** Setting `VITE_BACKEND_PORT` in the Azure Portal after deployment does nothing. It must be set in the GitHub Actions build step before `yarn build` runs.

- **One build, two deployments.** Building the app twice — once for staging, once for production — is how subtle environment differences sneak into production undetected. The artifact should be built once and deployed everywhere.

- **Azure's Oryx compression breaks symlinks.** Tools called through `node_modules/.bin/` use symlinks that survive in local environments but break when the artifact is zipped and extracted on Azure. Always reference the actual JavaScript file directly.

- **The manual approval gate is not just a safety feature.** It is the moment a human takes responsibility for what is about to touch production. Clicking approve without thinking defeats its entire purpose.

### Future Improvements

- **Terraform** — provision all Azure resources (App Service, Key Vault, Managed Identity, RBAC assignments) as infrastructure as code so the entire environment can be recreated in minutes
- **Replace LowDB with Azure SQL or Cosmos DB** — the JSON file database works for demos but cannot scale, persist properly, or survive slot swaps with data integrity
- **Azure Monitor alerts** — set up alerts on HTTP 5xx error rates and response times so production issues are caught before users report them
- **Separate frontend and backend** — serve the React build from Azure Static Web Apps and keep only the API on App Service, which would reduce cost and improve frontend performance globally

---

*Built by MK (Mokenyu) · George Brown College · Cloud Computing & Systems Administration*
