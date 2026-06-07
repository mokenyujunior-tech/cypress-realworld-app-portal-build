## Code Fixes in the Fork

I noticed three issues in the source code preventing the app from working in production. These changes were made in the fork only.

**Step 1:** Fixed the CORS configuration in `backend/app.ts`. The `corsOption` block had the origin hardcoded to `localhost`. So Any request from the Azure URL was blocked. The fix was pointing the app to the Azure URL, which is embedded in the environment variable `FRONTEND_URL`. The change is the in the red box above in the screenshot.

![Screenshot 2026-05-11 172541](Images/Screenshot%202026-05-11%20172541.png)

`FRONTEND_URL` is set differently per slot. Production reads its URL, staging reads its URL.

**Step 2:** Fixed the session secret in `backend/app.ts` which was hardcoded as `secret: "session secret"` to come from Key Vault. Change is in the red box below;

![Screenshot 2026-05-11 172541.png](Images/Screenshot%202026-05-11%20172541.png)

On Azure, `SESSION_SECRET` is resolved from Key Vault via the slot-specific setting.

**Step 3:** Fixed static file serving in `backend/app.ts`.

- Added the build folder immediately after the existing static line 120.
- Added the SPA fallback(a bridge between Express and React Router) before the `getBackendPort().then` block:

![SPA](Images/SPA.png)

---