# PayFlow — Full-Stack App Deployment on Azure

Azure App Service · GitHub Actions CI/CD · Azure Key Vault · Deployment Slots · Zero-Downtime Deployment

*A production-grade Node.js + React application deployed to Azure with a three-stage automated pipeline, secrets management, and zero-downtime slot swaps.*

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

## 5. Deployment Steps

### Step 1 — Create Azure Resources

In the Azure Portal, create the following inside a single Resource Group (`rg-payflow`):

1. **App Service Plan** — Basic B1, Linux, Canada Central
2. **App Service** — name: `payflow-production`, publish: Code, runtime: Node 18 LTS
3. **Deployment Slot** — name: `staging` (created under the App Service → Deployment slots)
4. **Key Vault (staging)** — name: `kv-payflow-staging`
5. **Key Vault (production)** — name: `kv-payflow-prod`

### Step 2 — Enable Managed Identity

For both the production App Service and the staging slot:

1. Go to **Identity** → System assigned → toggle **On** → Save
2. Copy the Object ID that appears

### Step 3 — Add Secrets to Key Vault

In each Key Vault → **Objects → Secrets → + Generate/Import**:

| Name | Value |
|---|---|
| `SESSION-SECRET` | A strong random string (minimum 32 characters) |
| `PAGINATION-PAGE-SIZE` | `10` |

### Step 4 — Grant Key Vault Access

In each Key Vault → **Access control (IAM) → + Add role assignment**:

- Role: **Key Vault Secrets User**
- Assign access to: **Managed Identity**
- Select the App Service or staging slot's Managed Identity

### Step 5 — Configure Environment Variables in App Service

For the **production** App Service and **staging** slot, add these under **Environment Variables**:

| Name | Value | Slot Setting |
|---|---|---|
| `NODE_ENV` | `production` | No |
| `PORT` | `8080` | No |
| `FRONTEND_URL` | Your Azure App Service URL | ✓ Yes |
| `VITE_BACKEND_PORT` | `3001` | No |
| `SESSION_SECRET` | `@Microsoft.KeyVault(SecretUri=https://your-kv.vault.azure.net/secrets/SESSION-SECRET/)` | ✓ Yes |
| `PAGINATION_PAGE_SIZE` | `@Microsoft.KeyVault(SecretUri=https://your-kv.vault.azure.net/secrets/PAGINATION-PAGE-SIZE/)` | No |

Verify both Key Vault references show a green **✓ Key vault** badge with **Resolved** status before continuing. **Configured** and **Resolved** are not the same thing — Configured means the reference is saved, Resolved means Azure can actually read the secret.

### Step 6 — Fix the Startup Script

The app uses `ncp` and `ts-node` in its startup sequence. Both break on Azure due to Oryx compression — `node_modules` is packed into a `tar.gz` at deployment time and symlinks break on extraction. Create `scripts/fix-prestart.js` in the root of the repository:

```javascript
const fs = require('fs');
const path = require('path');

const pkgPath = path.join(__dirname, '..', 'package.json');
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));

// Replace ncp with native fs.copyFileSync
pkg.scripts.prestart = pkg.scripts.prestart
  .replace(
    /ncp scripts\/mock-aws-exports\.js src\/aws-exports\.js && ncp scripts\/mock-aws-exports-es5\.js aws-exports-es5\.js/,
    'node -e "const fs=require(\'fs\'); fs.copyFileSync(\'./data/database-seed.json\',\'./data/database.json\');"'
  );

// Replace broken ts-node symlink with direct path
pkg.scripts.start = pkg.scripts.start
  .replace('cross-env NODE_ENV=development concurrently yarn:start:react yarn:start:api', '')
  .replace('nyc --silent ts-node -P tsconfig.tsnode.json -r tsconfig-paths/register backend/app.ts',
    'node node_modules/ts-node/dist/bin.js -P tsconfig.tsnode.json backend/app.ts');

fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2));
console.log('prestart fixed for Azure');
```

### Step 7 — Fix Hardcoded localhost URLs

The frontend calls `http://localhost:${backendPort}` in 36 places across 9 machine files. Run the fix script:

```bash
bash fix-backend-urls.sh
```

This adds `apiBaseUrl` to `src/utils/portUtils.ts`:

```typescript
export const apiBaseUrl: string =
  process.env.NODE_ENV === "production"
    ? ""
    : `http://localhost:${backendPort}`;
```

And replaces every `` `http://localhost:${backendPort}/... `` with `` `${apiBaseUrl}/... `` across all machine files.

### Step 8 — Fix CORS

In `backend/app.ts`, update the CORS configuration:

```typescript
const corsOption = {
  origin: process.env.FRONTEND_URL || `http://localhost:${frontendPort}`,
  credentials: true,
};
```

### Step 9 — Add SPA Fallback

In `backend/app.ts`, add the SPA fallback before the `getBackendPort().then` block:

```typescript
const apiPaths = ['/graphql','/users','/contacts','/bankAccounts',
  '/transactions','/likes','/comments','/notifications',
  '/bankTransfers','/testData'];

app.get('*', (req, res) => {
  const isApiRoute = apiPaths.some(p => req.path.startsWith(p));
  if (!isApiRoute) {
    res.sendFile(join(__dirname, '../build/index.html'));
  }
});
```

Without this, refreshing any page on Azure returns a 404. The SPA fallback catches all non-API routes and returns `index.html`, letting React Router render the correct page.

### Step 10 — Configure GitHub Environments

In your GitHub repository → **Settings → Environments**:

**Staging environment:**
- Name: `staging`
- No protection rules
- Secret: `AZURE_WEBAPP_PUBLISH_PROFILE` → paste contents of staging slot publish profile XML

**Production environment:**
- Name: `production`
- Protection rules: **Required reviewers** → add your GitHub username
- Secret: `AZURE_WEBAPP_PUBLISH_PROFILE` → paste contents of production publish profile XML

Download publish profiles from: Azure Portal → App Service → Deployment slots → select slot → **Get publish profile**

### Step 11 — Add the Pipeline

Create `.github/workflows/deploy.yml` in your repository with the three-job pipeline. Push to the `develop` branch to trigger the first deployment.

---

## 6. Problems Faced and Solutions

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
