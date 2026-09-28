# Maya iOS Starter

This folder is a native iPhone starter for **Maya**, the Marketing Director assistant (the `marketing-director` feature in the Angular app). It is intentionally separate from the Angular frontend. The backend stays the same.

Maya is unusual among the app's features in that her core interaction — the chat — is a single stateless HTTP call guarded by one shared static key, no per-user auth required:

- `POST /marketing-director/advice`

Everything the signed-in web experience adds on top of that is direct Firestore reads/writes (no extra backend endpoints):

- `users/{uid}` → `companyId` (tenant resolution)
- `tenants/{tenantId}/contacts/{uid}` (business context: company, mission, offer)
- `tenants/{tenantId}/employee-conversations` (+ `/messages`) (chat history)

## Scope decisions

This starter deliberately leaves out the **execution-actions system** — the part of `marketing-director-session.component.ts` that lets Maya's replies auto-create real documents, moves, surveys, response flows, and emails inside TODD when a tenant has paid workspace access:

- No `create_document` / `create_move` / `create_survey` / `create_response_flow` / `send_email` handling. `systemActions` in the advice response are decoded but never acted on.
- No paid-entitlement check (`GET /account/summary`). `accessMode` is always sent as `"free"` — the web app only ever sends `"suite"` once it has confirmed paid access, and this starter doesn't check for it yet, so it doesn't claim it.
- No "master marketing plan" persistence (`createMarketingPlan` / `generateDailyMarketingPlanFromPlan`) — that's part of the same paid-workspace flow.

What's in scope: **talk to Maya with no login at all (matches `marketing-director-public` today), and — once signed in — get replies personalized to your business plus a chat history that persists across launches.**

## Auth

Maya's chat works with zero sign-in, using a shared static API key (like `find-ios`). Signing in is optional and unlocks the personalized/persisted experience, the same way `pulse-ios` needs real sign-in for tenant-scoped survey data — except here `ChatView` never gates itself behind sign-in; `SignInView` is a sheet you can dismiss and keep chatting without.

`Services/AuthService.swift` mirrors `frontend/src/app/services/auth.service.ts`: sign in, then resolve the tenant id from `users/{uid}.companyId` (falling back to the uid itself), same as the web app's `resolveAssignedTenantId`.

Sign-in itself is **Sign in with Apple only** — no password, no email link — via the shared [`TODDAuthKit`](../TODDAuthKit) package, the same one every other TODD iOS app uses so this stays consistent instead of drifting per app. Confirmation is Face ID/Touch ID against the user's Apple ID.

Because Firebase silently restores a signed-in session on cold launch, `AuthService.sessionGate` (also from `TODDAuthKit`) tracks whether that restored session still needs a fresh biometric check. Until it clears, `ChatViewModel` keeps the conversation in its guest state (no personalization, no history restore) and `ChatView` shows an inline "Unlock to restore your TODD session" affordance instead of a blocking screen — Maya never stops working just because the lock hasn't cleared yet. A session just established by an interactive Sign in with Apple tap is trusted immediately, since Face ID already ran seconds ago as part of that prompt. See `../TODDAuthKit/README.md` for how the pieces fit together.

**One-time setup this repo can't do for you:** Sign In with Apple must be enabled on this app's App ID in the (paid) Apple Developer portal — `project.yml` requests the local capability, but the portal-side toggle is a separate account-level step.

This also means you need a `GoogleService-Info.plist` for a **new iOS app registration** in the `taliferrotech` Firebase project (bundle id `tech.taliferro.mayaios`, matching `project.yml`). Firebase console → Project settings → Add app → iOS → download the plist → drop it at `MayaIOS/GoogleService-Info.plist`. It is intentionally not checked in here.

## Recommended path

```bash
brew install xcodegen   # if you don't have it
cd ios/maya-ios
xcodegen generate
open MayaIOS.xcodeproj
```

Add `GoogleService-Info.plist` to the target before running.

## Required config

- `MAYA_API_BASE_URL` — set in `project.yml`, currently `https://api.taliferro.tech/api`.
- `MAYA_API_KEY` — the shared static key used by `environment.apiKey` / checked server-side as `TALIFERRO_TECH`. Set it locally (target build settings or an `.xcconfig` file), never commit the real value.
- `GoogleService-Info.plist` — required for Firebase Auth + Firestore, see above.

## Suggested first milestone (this starter)

1. Chat screen that works with no sign-in (starter prompts, composer, Maya's replies)
2. Optional sign-in (Sign in with Apple + biometric re-entry, see Auth above) that personalizes replies with the tenant's company name/description/mission/offer
3. Conversation history persisted to and restored from Firestore once signed in

## Suggested second milestone

1. Entitlement check (`GET /account/summary`) to know when a tenant has paid workspace access, and send `accessMode: "suite"` accordingly
2. Execution actions: `create_document`, `create_move`, `create_survey`, `create_response_flow`, `send_email` — each is a Firestore write or a call to an existing backend endpoint (`DocService`, `TaskService`, `SurveyApiService`, `ResponseFlowService`, `EmailService` on the web side), same shape as `pulse-ios`'s survey CRUD
3. Master marketing plan persistence (`createMarketingPlan` / `generateDailyMarketingPlanFromPlan`) so a saved plan survives across sessions the way it does on the web
4. "Preview saved plan in browser" link to `todd.taliferro.tech/document-editor/:id`

## Current source mapping

The web feature currently lives here:

- `frontend/src/app/features/marketing/pages/marketing-director-public/marketing-director-public.component.ts`
- `frontend/src/app/features/marketing/pages/marketing-director-session/marketing-director-session.component.ts`
- `frontend/src/app/features/marketing/services/public-marketing-director.service.ts`
- `frontend/src/app/features/marketing/services/marketing-employee.service.ts`
- `frontend/src/app/features/marketing/models/marketing-employee.models.ts`
- `frontend/src/app/services/auth.service.ts` (tenant resolution)
- `frontend/src/app/services/user.service.ts` (`getLoggedInContactInfo`)

Backend:

- `todd-backend/functions/openaiRoutes.js` (route registration)
- `todd-backend/functions/open-ai.js` (`generatePublicMarketingDirectorAdvice`)
