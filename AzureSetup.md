All steps below were performed through the Azure Portal, AzureCLI and GitHub unless stated otherwise. No Terraform used.

## Phase 0: Fork original Repo

Forked the original PayFlow repo on Github. `https://github.com/cypress-io/cypress-realworld-app`

---

## Phase 1: Create the Resource Group

One resource group holds everything. No separate resource groups needed.

**Step 1:** Created the Resource Group
- Resource group name: rg-payflow
- Region: Canada Central — NexPay is Toronto-based

---

## Phase 2: Create the Key Vault

**Step 1:** Created the Key vault

- Resource group: rg-payflow
- Key vault name: kv-payflow
- Region: Canada Central
- Pricing tier: Standard
- Permission model: Azure role-based access control (RBAC)

**Step 2:** Granted myself the Key Vault Officer Role

![Screenshot 2026-05-10 010328](Images/Screenshot%202026-05-10%20010328.png)

**Step 3:** Added three secrets in the Key Vault.

- **SESSION-SECRET-STAGING**
- **SESSION-SECRET-PRODUCTION**
- **PAGINATION-PAGE-SIZE**

![Screenshot 2026-05-11 013126](Images/Screenshot%202026-05-11%20013126.png)

The session secret in `backend/app.ts` is hardcoded as the string `session secret` and must be replaced with a Key Vault reference.

![Session secret](Images/Session%20secret.png)

---

## Phase 3: Create the App Service Plan and Web App

**Step 1:** Created App Service Plan and the Web App

- Resource group: rg-payflow
- Name: `payflow-production`
- Publish: Code
- Runtime stack: Node 20 LTS. The `package.json` engines field confirms `^20.0.0 || ^22.0.0` are both supported. Node 20 LTS is the current stable supported version in the portal
- Operating System: Linux
- Region: Canada Central
- Linux Plan: Created new — name `plan-payflow`, pricing plan Premium V3 P0v3. Chose it becuse it is the entry-level Premium tier and the minimum required to support deployment slots. Standard is legacy
- Continuous deployment: Disabled because GitHub Actions is configured manually in Phase 7
- Basic authentication: Enabled. Required to download the Publish Profile later

![Screenshot 2026-05-11 022634](Images/Screenshot%202026-05-11%20022634.png)

**Step 2:** Configured the startup command under Settings

```
yarn start
```

The README lists `start` as the script that starts the backend and frontend together. The `prestart` script runs automatically before it, copying `database-seed.json` to `database.json` to seed the database. One command handles both seeding and starting.

![start](Images/start.png)

![prestart](Images/prestart.png)

**Step 3:** Added three environment variables

- `NODE_ENV` = `production`. Without this the backend exposes the `/testData` route which allows anyone to wipe the database
- `WEBSITE_WEBDEPLOY_USE_SCM` = `true`. Required for Linux web apps before downloading the Publish Profile
- `FRONTEND_URL` = `payflow-production-bjescndqgahyhuc5.canadacentral-01.azurewebsites.net`. For the CORS fix to set the allowed browser origin

![Screenshot 2026-05-11 033646](Images/Screenshot%202026-05-11%20033646.png)

**Step 7:** Enabled System Assigned Managed Identity on the Production Web App. Then copied and saved the production slot's Object (principal) ID.

---

## Phase 4: Add the Staging Deployment Slot

**Step 1:** Created the Staging Deployment Slot

- Name: `staging`
- Clone settings from: `payflow-production`

![Screenshot 2026-05-11 033732.png](Images/Screenshot%202026-05-11%20033732.png)

**Step 2:** Configured the staging slot's own environment variables.

- `NODE_ENV` = `production`
- `WEBSITE_WEBDEPLOY_USE_SCM` = `true`
- `FRONTEND_URL` = `https://payflow-production-staging.azurewebsites.net`

![Screenshot 2026-05-11 033749](Images/Screenshot%202026-05-11%20033749.png)

**Step 3:** Enabled System Assigned Managed Identity on the staging slot. Then copied and saved the staging slot's Object (principal) ID.

---

## Phase 5: Grant Key Vault Access to Both Identities

**Step 1:** Granted the production Web App access to Key Vault. 

- Role: Key Vault Secrets User
- Members: `payflow-production` (The production slot)

**Step 2:** Granted the staging slot access to Key Vault.

- Same role
- Members: `payflow-production/staging`

![Screenshot 2026-05-11 170522](Images/Screenshot%202026-05-11%20170522.png)

**Step 3:** Connected the Key Vault secrets to the production Web App. Status must show resolved

- `SESSION_SECRET`
- `PAGINATION_PAGE_SIZE`

![Screenshot 2026-05-11 170555](Images/Screenshot%202026-05-11%20170555.png)

**Step 4:** Connected the Key Vault secrets to the staging slot.

- `SESSION_SECRET` = `@Microsoft.KeyVault(VaultName=kv-payflow;SecretName=SESSION-SECRET-STAGING)`. Checked **Deployment slot setting** checkbox. So that each environment keeps its own session secret permanently
- `PAGINATION_PAGE_SIZE` = `@Microsoft.KeyVault(VaultName=kv-payflow;SecretName=PAGINATION-PAGE-SIZE)`

![Screenshot 2026-05-11 170910](Images/Screenshot%202026-05-11%20170910.png)

---

## Phase 6: GitHub Environments and Actions Pipeline

**Step 1:** Downloaded two Publish Profiles, one for each slot.

![Screenshot 2026-05-11 175735](Images/Screenshot%202026-05-11%20175735.png)

**Step 2:** Created two GitHub Environments

- **staging**z: no protection rules, deploys automatically. Added secret `AZURE_WEBAPP_PUBLISH_PROFILE` with the full contents of `staging-slot-publish-profile.xml`
- **production**: Added my GitHub username as a required reviewer. This creates the manual approval gate. Added secret `AZURE_WEBAPP_PUBLISH_PROFILE` with the full contents of `production-slot-publish-profile.xml`

![Screenshot 2026-05-11 180829](Images/Screenshot%202026-05-11%20180829.png)

**Step 3:** Created a deployment file with the three-job pipeline. Check `.github/workflows/deploy.yml`
Also I deleted all original Cypress workflow files from `.github/workflows/`. They were test-only pipelines that caused noise and failures on every push.

![Screenshot 2026-05-11 231016](Images/Screenshot%202026-05-11%20231016.png)
![Screenshot 2026-05-11 234428](Images/Screenshot%202026-05-11%20234428.png)
![Screenshot 2026-05-12 004733](Images/Screenshot%202026-05-12%20004733.png)