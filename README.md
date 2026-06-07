<div align="center">

# A Full-Stack App Deployment on Azure - PayFlow

[![CI](https://github.com/mokenyujunior-tech/cypress-realworld-app-portal-build/actions/workflows/deploy.yml/badge.svg?branch=develop)](https://github.com/mokenyujunior-tech/cypress-realworld-app-portal-build/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-22.x-brightgreen)](https://nodejs.org)
[![Azure](https://img.shields.io/badge/hosted%20on-Azure%20App%20Service-blue?logo=microsoft-azure)](https://azure.microsoft.com)

*A production-grade Node.js + React application deployed to Azure with a three-stage automated pipeline, secrets management, and zero-downtime slot swaps.*

</div>

---

## Overview

PayFlow is a full-stack peer-to-peer payment demo application originally built by Cypress.io for testing purposes. This project takes that application and deploys it to a production-grade cloud environment on Microsoft Azure, with a fully automated CI/CD pipeline saving approximately 10 to 15mins of deployment time [CI_CD](CI_CD.md), secrets management, and zero-downtime deployments.

- **Application:** Node.js + React (Express backend, Vite frontend, LowDB database)
- **Cloud provider:** Microsoft Azure
- **Hosting:** Azure App Service - Premium V3 P0v3, Linux
- **Pipeline:** GitHub Actions - 3 jobs, 2 environments
- **Known limitation:** The LowDB JSON database resets to seed data on every app restart. Seems to be designed for demo purposes

---

## Architecture

PayFlow uses a three-stage CI/CD pipeline built on GitHub Actions, deploying to Azure App Service with two deployment slots, staging and production, inside a single Premium V3 P0v3 plan on Linux in Canada Central.

Secrets are never stored in code or the pipeline. Both slots authenticate to Azure Key Vault through their own system-assigned Managed Identity, reading `SESSION_SECRET` and `PAGINATION_PAGE_SIZE` at runtime via Key Vault references which is then being served to the app.

[Architecture](Architecture.md)

---

### Azure Services

- **Resource Group (rg-payflow):** Single resource group containing all PayFlow resources. App Service Plan, App Service, Key Vault, and Managed Identities.

- **Azure App Service Plan (Premium v3 P0v3):** The compute tier running the application. Basic B1 was considered and ruled out becuse Basic does not support deployment slots. Standard is legacy. Premium v3 P0v3 is the current non-legacy entry-level tier that supports deployment slots, giving us zero-downtime swaps and instant rollback capability.

- **Azure App Service - Production Slot:** The main App Service hosting both the frontend and backend. The Express backend serves the Vite-compiled React build as static files through the SPA fallback, meaning one App Service handles everything on one port.

- **Deployment Slot - Staging:** A live mirror of the app running inside the same App Service. Staging deploys automatically on every push to `develop`. Production only receives code after a manual approval by the reuired reviewer. The slot swap is zero-downtime. The testing slot.

- **Azure Key Vault (kv-payflow):** One Key Vault containing three secrets shared across both slots, with slot-specific App Service settings controlling which secret each slot reads. `SESSION_SECRET` is marked as a deployment slot setting so it stays pinned to its slot during swaps and never crosses environments.

- **Managed Identity:** Each App Service slot has its own system-assigned Managed Identity in Microsoft Entra ID. Each identity is granted the Key Vault Secrets User role on the Key Vault, which allows the App Service to read secrets at runtime without any credentials stored anywhere.

### CI/CD

- **GitHub Actions:** Three-job pipeline triggered on every push to the `develop` branch.

- **GitHub Environments (staging + production):** Each environment holds its own `AZURE_WEBAPP_PUBLISH_PROFILE` secret containing the XML credential file downloaded from Azure that authenticates GitHub Actions to deploy to that specific slot.

### Application

- **PayFlow (cypress-realworld-app):** A full-stack peer-to-peer payment demo app. React + TypeScript frontend compiled with Vite. Express.js backend running via ts-node. LowDB JSON file as the database. Probably built for local development only. Deploying it to Azure required solving a chain of infrastructure and code problems.

---

## 4. Prerequisites

Before starting you need:

- **An active Azure subscription** with permission to create Resource Groups, App Service Plans, App Services, Key Vaults, and Managed Identities
- **A GitHub account** with a fork of the PayFlow repository and permission to create Environments and Secrets under Settings
- **Azure CLI installed** locally for verification and diagnostics
- **Node.js 22.x and Yarn Classic (v1) installed locally.** Run `npm install -g yarn` and confirm `yarn --version` shows `1.x.x`
- **Git Bash (on Windows),** required to run the bash fix scripts locally

---

## Project Structure

[README](README.md)                     # Project overview and architecture
[deploy](.github/workflows/deploy.yml)  # Three-job GitHub Actions CI/CD pipeline - The code
[Architecture](Architecture.md)         # Full architecture diagram
[Azure_Setup](Azure_Setup.md)           # Step by step Azure portal setup journal
[CI_CD](CI_CD.md)                       # Pipeline flow and all startup problems
[CODE_FIXES](CODE_FIXES.md)             # Code changes made for Azure production
[fix-prestart](scripts/fix-prestart.js) # Azure startup fix. Rewrites package.json before deploy
[fix-backend-urls](fix-backend-urls.sh) # Replaces 36 hardcoded localhost URLs across 9 files

---

## How to Contribute

Contributions are welcome. To get started:

1. Fork the repository
2. Create a new branch
3. Make your changes and commit: `git commit`
4. Push to your branch: `git push`
5. Open a Pull Request against the `develop` branch

**Guidelines:**
- Follow the existing code style. Run `npx prettier --write` before committing
- Keep pull requests focused on a single change
- Test your changes locally with `yarn dev` before submitting

For bug reports or feature requests, open an issue on GitHub with as much detail as possible.

---

© 2026 Mokenyu Kezong