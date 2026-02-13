# OneDrive Agent with Microsoft Entra Agent ID

A **.NET 9** solution using **Microsoft Agent Framework (MAF)** with **Azure OpenAI** that helps users manage their OneDrive files using the **Microsoft Entra Agent ID On-Behalf-Of (OBO) flow** for secure user delegation.

**Architecture:**
- **.NET** (`OneDriveAgent/`): Bot + Agent runtime using MAF's `AIAgent` class with `AzureOpenAIClient`
- **Azure AI Services**: Hosts model deployments (gpt-4.1-mini)
- **Entra Agent ID**: Blueprint + Agent Identity pattern for governed OBO flow

> **Note:** The `src/` folder contains alternative Python examples, but this project uses the .NET implementation.

---

## Roles and Responsibilities

This project requires coordination between **developers** and **Entra ID administrators**. Some tasks can be automated by Azure AI Foundry, while others require manual admin intervention.

### Task Matrix

| Task | Who | Script | Notes |
|------|-----|--------|-------|
| Create AI Foundry project | Developer | `azd provision` | Bicep automation |
| Deploy .NET API to App Service | Developer | `azd deploy` | After provision |
| Create User-Assigned Managed Identity | Developer | `azd provision` | Bicep automation |
| Create Blueprint + Agent Identity Apps | Admin | `01-admin-create-apps.sh` | Full automation |
| Add Graph permissions + admin consent | Admin | `01-admin-create-apps.sh` | Full automation |
| Create Federated Identity Credential | Admin | `03-admin-create-fic.sh` | After `azd provision` |
| Configure Bot OAuth (optional) | Admin | `04-admin-bot-oauth.sh` | For Teams |
| Configure app settings | Developer | `azd deploy` | Automatic |

*Admin = Entra ID admin (or developer with Application.ReadWrite.All permission)*

### Entra ID Admin Workflow (Phase 1)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     ENTRA ID ADMIN TASKS (Phase 1)                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Create App Registrations (required for MAF/code-first agents)          │
│  ─────────────────────────────────────────────────────────────          │
│  1. Create Blueprint app registration                                   │
│     $ az ad app create --display-name "OneDrive-Agent-Blueprint"        │
│                                                                         │
│  2. Create Agent Identity app registration                              │
│     $ az ad app create --display-name "OneDrive-Agent-Identity"         │
│                                                                         │
│  3. Configure parent-child relationship                                 │
│     (See Entra ID setup script in /scripts/)                            │
│                                                                         │
│  4. Add delegated Graph permissions to Agent Identity                   │
│     $ az ad app permission add --id <agent-identity-id> \               │
│         --api 00000003-0000-0000-c000-000000000000 \                    │
│         --api-permissions 10465720-29dd-4523-a11a-6a75c743c9d9=Scope    │
│                                                                         │
│  5. Grant admin consent (REQUIRED)                                      │
│     $ az ad app permission admin-consent --id <agent-identity-id>       │
│                                                                         │
│  6. Provide app IDs to Developer                                        │
│     -> Blueprint Client ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx        │
│     -> Agent Identity Client ID: yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Developer Workflow

```
+-------------------------------------------------------------------------+
│                        DEVELOPER TASKS                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. Clone repository and build                                          │
│     $ git clone <repo> && cd AgentId                                    │
│     $ dotnet build OneDriveAgent                                        │
│                                                                         │
│  2. Set environment variables from Admin                                │
│     $ azd env set BLUEPRINT_CLIENT_ID "<from-admin>"                    │
│     $ azd env set AGENT_IDENTITY_CLIENT_ID "<from-admin>"               │
│                                                                         │
│  3. Deploy infrastructure + app                                         │
│     $ azd up                                                            │
│                                                                         │
│  4. Provide MI Client ID to Admin (for FIC setup)                       │
│     $ azd env get-value MANAGED_IDENTITY_CLIENT_ID                      │
│     -> Send this to Admin                                               │
│                                                                         │
│  5. Test the deployment                                                 │
│     $ curl $(azd env get-value APP_SERVICE_URL)/health                  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Entra ID Admin Workflow (Phase 2 - Post Deployment)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     ENTRA ID ADMIN TASKS (Phase 2)                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  After receiving MI Client ID from Developer:                           │
│                                                                         │
│  7. Create Federated Identity Credential                                │
│     $ az rest --method POST \                                           │
│         --uri "https://graph.microsoft.com/v1.0/applications(appId=     │
│                '<blueprint-id>')/federatedIdentityCredentials" \        │
│         --body '{"name":"MI-FIC","issuer":"https://login...","subject": │
│                 "<mi-client-id>","audiences":["api://AzureADToken..."]}'│
│                                                                         │
│  8. (Optional) Configure Bot OAuth connection for Teams                 │
│     $ ./scripts/04-admin-bot-oauth.sh                                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Handoff Checklist

**Admin provides to Developer (after Phase 1):**
- [ ] Blueprint App Client ID
- [ ] Agent Identity App Client ID
- [ ] Confirmation that admin consent was granted

**Developer provides to Admin (after deployment):**
- [ ] Managed Identity Client ID (after `azd provision`)
- [ ] Tenant ID (if not already known)

**Admin completes (Phase 2):**
- [ ] Federated Identity Credential created linking MI to Blueprint

### Non-Foundry Agents (LangChain, MAF, Custom)

If you're **not using Azure AI Foundry** (e.g., building with LangChain, Microsoft Agent Framework, or a custom solution), you still need the same Entra ID setup - but you won't get any automation from Foundry.

**What's Different Without Foundry:**

| Aspect | With Foundry | Without Foundry |
|--------|--------------|-----------------|
| Blueprint App | Auto-created by Foundry | Must create manually |
| Agent Identity App | Auto-created by Foundry | Must create manually |
| Parent-child relationship | Configured by Foundry | Must configure manually |
| Agent hosting | Foundry runs the agent | You host the agent yourself |

The Entra ID admin scripts in this project (`scripts/01-admin-create-apps.sh`, etc.) work for any agent framework. The OBO token exchange code in [AgentOboTokenService.cs](Services/AgentOboTokenService.cs) demonstrates the standard MSAL pattern that can be adapted to any language or framework.

---

## Table of Contents

1. [Roles and Responsibilities](#roles-and-responsibilities)
   - [Task Matrix](#task-matrix)
   - [Developer Workflow](#developer-workflow)
   - [Entra ID Admin Workflow](#entra-id-admin-workflow)
   - [Non-Foundry Agents (LangChain, MAF, Custom)](#non-foundry-agents-langchain-maf-custom)
2. [Concepts](#concepts)
   - [The Agent ID Architecture](#the-agent-id-architecture)
   - [The Hotel Concierge Analogy](#the-hotel-concierge-analogy)
   - [Token Flow Explained](#token-flow-explained)
3. [Implementation Approaches](#implementation-approaches)
   - [Comparison of Options](#comparison-of-options)
   - [Why Custom Function Tools?](#why-custom-function-tools)
4. [Prerequisites](#prerequisites)
5. [Project Structure](#project-structure)
6. [Local Setup](#local-setup)
   - [Step 1: Clone and Build](#step-1-clone-and-build)
   - [Step 2: Run Automated Entra ID Setup](#step-2-run-automated-entra-id-setup)
   - [Step 3: Configure the Agent](#step-3-configure-the-agent)
   - [Step 4: Grant Admin Consent](#step-4-grant-admin-consent)
7. [Local Development & Testing](#local-development--testing)
   - [Configure appsettings](#step-1-configure-appsettingsdevelopmentjson)
   - [Build and Run](#step-2-build-and-run)
   - [Test with curl](#step-3-test-with-curl-api-endpoint)
   - [Test with Agents Playground](#step-4-test-with-agents-playground-bot-endpoint)
8. [Azure Deployment](#azure-deployment)
   - [Quick Start with azd](#quick-start-with-azure-developer-cli-azd)
   - [Manual Deployment](#manual-deployment-alternative)
9. [Publishing to M365 Copilot](#publishing-to-m365-copilot)
   - [M365 Agents SDK + Bot Service](#step-1-add-m365-agents-sdk)
   - [Declarative vs SDK Agents](#key-differences-declarative-agent-vs-m365-agents-sdk)
10. [Step-by-Step Deployment Guide](#step-by-step-deployment-guide)
    - [Phase 1: Entra Admin - Create App Registrations](#phase-1-entra-admin---create-app-registrations)
    - [Phase 2: Developer - Deploy Infrastructure](#phase-2-developer---deploy-infrastructure)
    - [Phase 3: Entra Admin - Complete Identity Setup](#phase-3-entra-admin---complete-identity-setup)
    - [Phase 4: Developer - Configure and Test](#phase-4-developer---configure-and-test)
    - [Phase 5 (Optional): Teams/M365 Copilot Publishing](#phase-5-optional---teamsm365-copilot-publishing)
11. [API Reference](#api-reference)
12. [Troubleshooting](#troubleshooting)
13. [References](#references)

---

## Step-by-Step Deployment Guide

This guide provides a complete, role-based deployment workflow. Follow these phases in order, with clear handoffs between Developer and Entra Admin roles.

### Prerequisites Checklist

| Requirement | Developer | Entra Admin |
|-------------|-----------|-------------|
| Azure CLI installed | [Y] Required | [Y] Required |
| Azure subscription (Contributor) | [Y] Required | |
| .NET 9 SDK | [Y] Required | |
| Azure Developer CLI (`azd`) | [Y] Required | |
| Entra ID Global Admin or App Admin | | [Y] Required |
| Microsoft 365 license (with OneDrive) | For testing | |

### Deployment Flow Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        DEPLOYMENT TIMELINE                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  PHASE 1: ENTRA ADMIN                                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ Create Blueprint App -> Create Agent Identity App -> Add Graph Perms     │   │
│  │ -> Create Client Secret -> Grant Admin Consent                           │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                              │                                                  │
│                              v Handoff: App IDs + Secret                        │
│                                                                                 │
│  PHASE 2: DEVELOPER                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ Clone repo -> Configure azd env -> Run 'azd provision' -> Note MI ID     │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                              │                                                  │
│                              v Handoff: MI Client ID                            │
│                                                                                 │
│  PHASE 3: ENTRA ADMIN                                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ Create Federated Identity Credential (links MI to Blueprint)           │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                              │                                                  │
│                              v Confirmation                                     │
│                                                                                 │
│  PHASE 4: DEVELOPER                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ Test deployment -> Verify OBO flow -> Ready for production               │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  PHASE 5 (OPTIONAL): TEAMS/M365 COPILOT                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ Enable Bot -> Configure SSO -> Generate Teams Manifest -> Publish         │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

### Phase 1: Entra Admin - Create App Registrations

**Role:** Entra ID Administrator  
**Time:** ~5 minutes  
**Prerequisite:** Azure CLI with admin privileges

```bash
az login --tenant <your-tenant-id>
cd scripts
bash 01-admin-create-apps.sh --tenant-id <your-tenant-id>
```

The script creates:
- **Blueprint App** with `access_as_user` scope
- **Agent Identity App** with Graph permissions (Files.Read, User.Read, etc.)
- Admin consent for the permissions
- Client secret for local development
- Pre-authorized clients (Azure CLI, Teams, Agents Playground)

**Output:** Save the generated values to share with the developer:
- `BLUEPRINT_CLIENT_ID`
- `AGENT_IDENTITY_CLIENT_ID`  
- `AGENT_IDENTITY_CLIENT_SECRET`
- `TENANT_ID`

---

### Phase 2: Developer - Deploy Infrastructure

**Role:** Developer  
**Time:** ~20 minutes  
**Prerequisite:** Values from Phase 1

```bash
# Clone and build
git clone <repository-url> && cd AgentId
dotnet build OneDriveAgent

# Configure azd with values from Entra Admin
azd env set BLUEPRINT_CLIENT_ID "<from-admin>"
azd env set AGENT_IDENTITY_CLIENT_ID "<from-admin>"
azd env set AGENT_IDENTITY_CLIENT_SECRET "<from-admin>"

# Deploy infrastructure
azd provision    # Infrastructure only (recommended for local dev)
# OR
azd up           # Infrastructure + deploy code
```

> **Local-First Development:** Use `azd provision` to create infrastructure without deploying code. Then use devtunnel + F5 for local debugging. Deploy with `azd deploy` when ready for production.

This creates: Resource Group, AI Services, Foundry Project, User-Assigned Managed Identity, App Service, and RBAC role assignments.

**Output:** Send the Managed Identity Client ID to the admin:
```bash
azd env get-value MANAGED_IDENTITY_CLIENT_ID
```

---

### Phase 3: Entra Admin - Create Federated Identity Credential

**Role:** Entra ID Administrator  
**Time:** ~2 minutes  
**Prerequisite:** Managed Identity Client ID from Phase 2

```bash
cd scripts
bash 03-admin-create-fic.sh --blueprint-id <blueprint-id> --mi-client-id <mi-client-id>
```

The FIC links the Managed Identity to the Blueprint app, enabling passwordless OBO authentication in Azure.

---

### Phase 4: Developer - Test

**Role:** Developer  
**Time:** ~5 minutes  

```bash
# Verify deployment
APP_URL=$(azd env get-value APP_SERVICE_URL)
curl "$APP_URL/health"

# Get user token and test
AGENT_ID=$(azd env get-value AGENT_IDENTITY_CLIENT_ID)
TOKEN=$(az account get-access-token --resource "api://$AGENT_ID" --query accessToken -o tsv)

curl -X POST "$APP_URL/api/chat" \
  -H "Content-Type: application/json" \
  -d "{\"message\": \"Show me my files\", \"userToken\": \"$TOKEN\"}"
```

---

### Phase 5 (Optional): Teams/M365 Copilot Publishing

**Roles:** Developer + Entra Admin  
**Time:** ~30 minutes  
**Prerequisite:** Working deployment from Phase 4

This phase enables the agent to work in Microsoft Teams and M365 Copilot.

**Step 1: Enable Bot and redeploy**
```bash
azd env set ENABLE_BOT "true"
azd env set BOT_MICROSOFT_APP_ID "$(azd env get-value AGENT_IDENTITY_CLIENT_ID)"
azd up
```

**Step 2: Entra Admin - Configure Bot OAuth for SSO**
```bash
cd scripts
bash 04-admin-bot-oauth.sh --agent-id <agent-identity-id> --scope-id <access_as_user-scope-id>
```

The script configures:
- Redirect URI for Bot Framework
- Identifier URI (`api://botid-{app-id}`)
- Pre-authorized clients (Teams Desktop, Teams Web, Teams Mobile, Outlook, Office)
- Creates Bot OAuth connection secret

**Step 3: Developer - Generate Teams Manifest**
```bash
cd scripts
bash 05-dev-teams-manifest.sh
```

**Step 4: Publish to Teams**
- Sideload: Teams -> Apps -> Upload a custom app -> select `onedrive-agent-teams.zip`
- Or: Teams Admin Center -> Manage apps -> Upload new app

**SSO vs Magic Code Fallback:** When SSO works (pre-authorized clients + admin consent), no sign-in prompt appears. The magic code fallback handles edge cases (Bot Emulator, Web Test Chat, older clients).

---

### Quick Reference: All App IDs and Secrets

Keep track of these values throughout deployment:

| Value | Set By | Used By | Purpose |
|-------|--------|---------|---------|
| `TENANT_ID` | Both | Both | Azure AD tenant |
| `BLUEPRINT_CLIENT_ID` | Admin | Developer | Blueprint app ID |
| `AGENT_IDENTITY_CLIENT_ID` | Admin | Developer | Agent Identity app ID |
| `AGENT_IDENTITY_CLIENT_SECRET` | Admin | Developer | Local dev only |
| `MANAGED_IDENTITY_CLIENT_ID` | Developer | Admin | For FIC creation |
| `APP_SERVICE_URL` | Developer | Both | Deployed app URL |
| `BOT_MICROSOFT_APP_ID` | Developer | Both | Bot app ID (Phase 5) |

---

## Concepts

### The Agent ID Architecture

Microsoft Entra Agent ID introduces a new identity model specifically designed for AI agents. It consists of three main components:

```
+--------------------------------------------------------------------+
|                  AGENT IDENTITY ARCHITECTURE                       |
+--------------------------------------------------------------------+
|                                                                    |
|  +------------------------------+  +---------------------------+   |
|  | BLUEPRINT (Parent App)       |  |     MANAGED IDENTITY      |   |
|  |------------------------------|  |---------------------------|   |
|  | * App Registration in Entra  |  | * Azure Resource          |   |
|  | * Exposes API scope          |<-| * No client secret needed |   |
|  |   (access_as_user)           |FIC * Works in Azure only     |   |
|  | * Linked to MI via FIC       |  |                           |   |
|  +------------------------------+  +---------------------------+   |
|               |                                                    |
|               | Parent-Child Relationship                          |
|               v                                                    |
|  +------------------------------+                                  |
|  | AGENT IDENTITY (Child App)   |                                  |
|  |------------------------------|                                  |
|  | * Performs the OBO exchange  |                                  |
|  | * Has delegated Graph perms  |                                  |
|  | * Multiple instances per     |                                  |
|  |   Blueprint allowed          |                                  |
|  +------------------------------+                                  |
|                                                                    |
+--------------------------------------------------------------------+
```

| Component | Purpose | Configuration |
|-----------|---------|---------------|
| **Blueprint** | Parent application that defines the agent's API surface | App registration with exposed API scope |
| **Agent Identity** | Child application that performs OBO and calls resources | App registration with Graph delegated permissions |
| **Managed Identity** | Provides secure authentication without secrets | Azure User-Assigned Managed Identity linked via FIC |
| **Federated Identity Credential (FIC)** | Links Managed Identity to Blueprint | Created on Blueprint app pointing to MI |

### The Hotel Concierge Analogy

To understand the OBO flow, imagine a hotel:

```
+------------------------------------------------------------------------------+
|                     THE HOTEL CONCIERGE ANALOGY                              |
+------------------------------------------------------------------------------+
|                                                                              |
|  SETUP (done once by Admin):                                                 |
|                                                                              |
|  +--------------+                           +------------------+             |
|  |    Hotel     |  Files Employment Record  | City Tourism     |             |
|  |  Management  | ------------------------> |    Board         |             |
|  | (Blueprint)  |     (FIC) that says:      |  (Entra ID)      |             |
|  +--------------+     "Staff Badge #12345   +------------------+             |
|                        is authorized to                                      |
|                        represent our hotel"                                  |
|                                                                              |
|  RUNTIME FLOW:                                                               |
|                                                                              |
|  1. GUEST CHECKS IN                                                          |
|     +----------+     "I'm John Smith"      +--------------+                  |
|     |  Guest   | ------------------------> |  Front Desk  |                  |
|     |  (User)  | <------------------------ |(Agent Ident.)|                  |
|     +----------+     Room Key Card         +--------------+                  |
|                      (User Token)                                            |
|                                                                              |
|  2. GUEST ASKS CONCIERGE FOR HELP                                            |
|     +----------+     "Book me a spa"       +----------------+                |
|     |  Guest   | ------------------------> |   Concierge    |                |
|     |          |     Shows Room Key        |  (App Service) |                |
|     +----------+                           | [Badge #12345] |                |
|                                            |      (MI)      |                |
|                                            +----------------+                |
|                                                   |                          |
|  3. CONCIERGE CALLS SPA                           |                          |
|                                                   v                          |
|                                            +--------------+                  |
|                                            |   City Spa   |                  |
|                                            | (Graph API)  |                  |
|                                            +--------------+                  |
|                                                   |                          |
|     Concierge presents:                           |                          |
|     - Guest's Room Key (User Token)               |                          |
|     - City Tourism Board ID (token from Entra ID) |                          |
|       (The hotel pre-registered the concierge     |                          |
|        with the Tourism Board via FIC)            |                          |
|                                                   v                          |
|     Spa verifies:                                                            |
|     - "Is this Tourism Board ID authentic?" --> Yes, valid stamp             |
|     - "Is room key valid?" --> Yes                                           |
|     (Spa trusts the Tourism Board, doesn't call the hotel directly)          |
|                                                   |                          |
|  4. SPA SERVES THE GUEST                          v                          |
|                                                                              |
|                   Spa books massage for John Smith                           |
|                   (Graph returns user's files)                               |
|                                                                              |
+------------------------------------------------------------------------------+
```

**Mapping to Azure Components:**

| Hotel | Azure | Purpose |
|-------|-------|---------|
| Hotel Management | Blueprint App | Trust anchor - "who owns this agent" |
| Employment Record | FIC | Pre-created link: "MI X can represent Blueprint Y" |
| City Tourism Board | Entra ID | Trusted authority - issues verified IDs |
| Tourism Board ID | Entra-signed token | Proves concierge is registered (via FIC check) |
| Guest | User | The person requesting access |
| Front Desk | Agent Identity App | User authenticates here, gets token |
| Room Key Card | User Token | Proves "I am this guest" |
| Concierge | App Service (.NET code) | Runs code, handles requests |
| Staff Badge | Managed Identity | Proves "I am this App Service" (no secrets) |
| City Spa | Microsoft Graph API | External service with user's data |

**The key insight:** The Hotel pre-registers their concierge with the Tourism Board (FIC created on Blueprint). At runtime:
1. Concierge shows Staff Badge (MI) to Tourism Board (Entra ID)
2. Tourism Board checks FIC -> issues Tourism Board ID (token)
3. Concierge shows Tourism Board ID to Spa
4. Spa trusts the Tourism Board stamp -> serves the guest

**Why does the spa need both credentials?**

The Spa (Graph API) checks:
1. **"Is this Tourism Board ID authentic?"** -> Verify Entra signature -> Yes, valid
2. **"Is room key valid?"** -> Check User Token -> "Yes, John Smith in Room 302"

The FIC check happened earlier (step 2) when the Tourism Board issued the ID. The Spa doesn't call the hotel or check FIC - it trusts Entra ID's signature.

This prevents:
- Random people claiming to be guests (no valid room key)
- Unauthorized services claiming to act for guests (no Tourism Board ID)
- Fake hotels trying to spoof requests (no FIC -> Tourism Board won't issue ID)

### Why Agents Need This: A Use Case Comparison

**Scenario:** A user wants an app to summarize their emails every morning.

```
+------------------------------------------------------------------------------+
|                    TRADITIONAL WEB APP (Boutique Hotel)                      |
+------------------------------------------------------------------------------+
|                                                                              |
|  The user visits web app at 8am, clicks "Summarize my emails"                |
|                                                                              |
|  +--------+    Login     +------------------+                                |
|  |  User  | -----------> | Web App          |     Single registration        |
|  +--------+    Secret    | (Boutique Hotel) |     with Tourism Board          |
|       |      in config   +------------------+     (ClientID + Secret)         |
|       |                           |                                          |
|       v                           v                                          |
|  User present             App uses secret + user token                       |
|  User in control          to call Graph API                                  |
|  User sees result                                                            |
|                                                                              |
|  PROBLEM: What if user wants this at 6am before they wake up?                |
|  - App would need to store refresh tokens (security risk)                    |
|  - Secret stored in config could leak                                        |
|  - IT has no visibility into what this app does                              |
|  - If secret leaks, attacker can impersonate from ANYWHERE                   |
|                                                                              |
+------------------------------------------------------------------------------+

+------------------------------------------------------------------------------+
|                    AGENT WITH ENTRA AGENT ID (Franchise Hotel)               |
+------------------------------------------------------------------------------+
|                                                                              |
|  User tells agent: "Summarize my emails every morning at 6am"                |
|                                                                              |
|  SETUP (by IT Admin):                                                        |
|  +----------------+    Files FIC    +------------------+                     |
|  | Hotel Mgmt     | --------------> | Tourism Board    |                     |
|  | (Blueprint)    |                 | (Entra ID)       |                     |
|  +----------------+                 +------------------+                     |
|  Defines: "Agent can read Mail"          |                                   |
|                                          v                                   |
|                                    FIC: "Staff Badge #12345                  |
|                                     works for this hotel"                    |
|                                                                              |
|  RUNTIME (at 6am, user is asleep):                                           |
|  +----------------+                 +------------------+                     |
|  | App Service    | --------------> | Tourism Board    |                     |
|  | [Badge #12345] |  "I'm #12345"   | (Entra ID)       |                     |
|  | (Concierge)    | <-------------- +------------------+                     |
|  +----------------+  Tourism ID           |                                  |
|         |            (FIC verified)       |                                  |
|         |                                 |                                  |
|         v                                 |                                  |
|  +----------------+                       |                                  |
|  | Graph API      |  "Here's Tourism ID   |                                  |
|  | (Spa)          |   + user's consent"   |                                  |
|  +----------------+                       |                                  |
|         |                                 |                                  |
|         v                                 |                                  |
|  Returns user's emails (user consented earlier)                              |
|                                                                              |
|  WHY THIS IS BETTER:                                                         |
|  - NO secret in code/config - Badge #12345 is Managed Identity               |
|  - IT Admin controls what agent can do via Blueprint                         |
|  - If App Service is compromised, revoke FIC - done                          |
|  - Badge only works FROM that specific App Service                           |
|  - User granted consent once, agent acts on schedule                         |
|                                                                              |
+------------------------------------------------------------------------------+
```

**Key Insight: Agents Act Without You**

| Aspect | Web App | Agent |
|--------|---------|-------|
| **When it acts** | User clicks a button | Can act autonomously (scheduled, triggered) |
| **User presence** | User is watching | User may be asleep/offline |
| **Trust question** | "Can this app access my data NOW?" | "Can this app access my data ANYTIME on my behalf?" |
| **Credential type** | Client Secret (can leak) | Managed Identity (unforgeable) |
| **Who controls it** | Developer | IT Admin (via Blueprint) |
| **Recovery if compromised** | Rotate secret everywhere | Revoke single FIC |

**The security model is stricter because the trust is greater.** An agent that can act while you sleep needs:
1. **Admin oversight** (Blueprint defines allowed actions)
2. **No extractable secrets** (MI can't be copied to attacker's machine)
3. **Cryptographic binding** (FIC ties "permission" to "specific deployment")

**Bottom Line:** Certificate-based OAuth solves secret sprawl, but FIC + OBO adds the governance layer - admin-controlled trust, explicit user delegation, and full attribution chain in audit logs.

### Token Flow Explained

The complete OBO flow involves multiple token exchanges:

```
+------------------------------------------------------------------------------+
|                           AGENT OBO TOKEN FLOW                               |
+------------------------------------------------------------------------------+
|                                                                              |
|  Step 1: User Authentication                                                 |
|  ---------------------------                                                 |
|  User ------> Client App (Teams/Chat) ------> Entra ID                       |
|                                                    |                         |
|                                               User Token (Tc)                |
|                                               Audience: Agent Identity       |
|                                                    |                         |
|  Step 2: Agent Authenticates (in Azure)            v                         |
|  ---------------------------------------                                     |
|  Managed Identity ------> IMDS (169.254.169.254)                             |
|                                    |                                         |
|                            MI Token (T_UAMI)                                 |
|                            Audience: api://AzureADTokenExchange              |
|                                    |                                         |
|  Step 3: Exchange for Blueprint Token                                        |
|  -------------------------------------                                       |
|  POST /oauth2/v2.0/token               v                                     |
|    client_id = Blueprint                                                     |
|    scope = api://AzureADTokenExchange/.default                               |
|    client_assertion = T_UAMI  (MI Token)                                     |
|    fmi_path = AgentIdentity  (Child App ID)                                  |
|    grant_type = client_credentials                                           |
|                        |                                                     |
|                   Blueprint Token (T1)                                       |
|                        |                                                     |
|  Step 4: OBO Exchange  v                                                     |
|  ------------------------                                                    |
|  POST /oauth2/v2.0/token                                                     |
|    client_id = AgentIdentity                                                 |
|    scope = https://graph.microsoft.com/.default                              |
|    client_assertion = T1  (Blueprint Token)                                  |
|    assertion = Tc  (User Token)                                              |
|    grant_type = urn:ietf:params:oauth:grant-type:jwt-bearer                  |
|    requested_token_use = on_behalf_of                                        |
|                        |                                                     |
|                   Graph Token (for User)                                     |
|                        |                                                     |
|  Step 5: Call Graph API v                                                    |
|  -------------------------                                                   |
|  GET https://graph.microsoft.com/v1.0/me/drive/root/children                 |
|  Authorization: Bearer {Graph Token}                                         |
|                                                                              |
+------------------------------------------------------------------------------+
```

**Local Development Simplification:**

For local development (where Managed Identity is unavailable), we use a **client secret** directly on the Agent Identity app, reducing the flow to a single step:

```
User Token (Tc) ---> OBO with Client Secret ---> Graph Token
```

---

## Implementation Approaches

When building an AI agent that needs to access user data in Microsoft 365 (OneDrive, SharePoint, Outlook, etc.) on behalf of a user, there are several implementation options available in Azure AI Foundry. This section compares them to help you choose the right approach.

### Comparison of Options

| Option | OBO Support | Token Handling Code | License Required | Deployment Complexity |
|--------|-------------|---------------------|------------------|----------------------|
| **Built-in SharePoint Tool** | Yes (Platform-handled) | **0 lines** | **M365 Copilot** (~$30/user/mo) | Config only |
| **Custom Function Tools** (this project) | Yes (Full OBO) | ~150 lines | M365 Business | Single app |
| **Azure Function Tool** | Yes (Full OBO) | ~150 lines | M365 Business | Function + storage queues |
| **OpenAPI Tool + Managed Auth** | No (App-only) | 0 lines | M365 Business | OpenAPI spec + config |

### Built-in SharePoint Tool (Premium)

The easiest option if you have **Microsoft 365 Copilot licenses**. Platform handles all OBO automatically with semantic search capabilities. Requires expensive Copilot license (~$30/user/mo).

### Custom Function Tools (This Project)

Best option for **true user OBO without Copilot license**. See the actual implementation:
- [AgentOboTokenService.cs](Services/AgentOboTokenService.cs) - OBO token exchange (~80 lines)
- [OneDriveService.cs](Services/OneDriveService.cs) - Graph API calls
- [MafAgentService.cs](Services/MafAgentService.cs) - Function tool definitions

### Azure Function Tool

Similar to custom functions but executes in serverless Azure Functions with queue-based input/output. More complex deployment (Function + queues + storage).

### OpenAPI Tool with Managed Auth

For calling **external REST APIs** with app-level authentication. Uses **app-only** permissions, NOT user delegation (OBO). Best for company-internal APIs, partner services, or public APIs - not for user-specific M365 data.

### Why Custom Function Tools?

This project uses **Custom Function Tools** because:

| Reason | Explanation |
|--------|-------------|
| **No Copilot License** | Most organizations don't have M365 Copilot licenses for all users |
| **True User OBO** | Access user's personal OneDrive, not shared app resources |
| **Simple Deployment** | Single ASP.NET application, no Azure Functions or queues |
| **Full Control** | Complete control over Graph API calls, error handling, and response formatting |
| **Cost Effective** | Works with basic M365 Business licenses |
| **Production Ready** | Same OBO pattern used by Microsoft first-party apps |

The trade-off is ~150 lines of OBO token exchange code (in `AgentOboTokenService.cs`), which is well worth it for the flexibility and cost savings.

### Decision Matrix

```
Do you have M365 Copilot licenses for all users?
+-- YES --> Use Built-in SharePoint Tool (simplest)
+-- NO
    |
    Do you need user-specific data (OBO)?
    +-- YES --> Use Custom Function Tools (this project)
    +-- NO
        |
        Is your API external or company-internal?
        +-- External/Internal REST --> Use OpenAPI Tool
        +-- Azure Function needed --> Use Azure Function Tool
```

---

## Prerequisites

| Requirement | Purpose |
|-------------|---------|
| **.NET 9 SDK** | Build and run the application |
| **Azure CLI** | Authentication and resource management |
| **Azure Subscription** | For Managed Identity and deployment |
| **Azure AI Services** | Model deployments (gpt-4.1-mini or similar) |
| **Microsoft 365 License** | OneDrive access for the test user |
| **Entra ID Admin Access** | Create app registrations and grant consent |

---

## Project Structure

```
AgentId/
+-- src/                               # Alternative Python examples (not used)
|   +-- agent_manager.py              # Example: AIProjectClient usage
|   +-- pyproject.toml                # Python dependencies
+-- OneDriveAgent/                     # .NET application (main)
|   +-- Models/
|   |   +-- DriveModels.cs            # OneDrive API response models
|   +-- Services/
|   |   +-- AgentOboConfig.cs         # OBO configuration options
|   |   +-- AgentOboTokenService.cs   # OBO token exchange (~150 lines)
|   |   +-- MafAgentService.cs        # MAF Agent with function tools
|   |   +-- OneDriveAgentBot.cs       # Teams bot handler
|   |   +-- OneDriveService.cs        # Microsoft Graph client for OneDrive
|   +-- Setup/
|   |   +-- AgentIdentitySetup.cs     # Automated Entra ID provisioning
|   |   +-- SetupProgram.cs           # CLI interface for setup command
|   +-- Program.cs                     # ASP.NET Core startup + REST endpoints
|   +-- appsettings.json               # Production configuration
|   +-- appsettings.Development.json   # Development configuration
|   +-- OneDriveAgent.csproj          # Project file
+-- scripts/                           # Automation scripts
|   +-- 00-admin-cleanup.sh           # Cleanup: Remove app registrations
|   +-- 01-admin-create-apps.sh       # Step 1: Create app registrations
|   +-- 02-dev-generate-handoff.sh    # Step 2: Generate admin handoff
|   +-- 03-admin-create-fic.sh        # Step 3: Create FIC
|   +-- 04-admin-bot-oauth.sh         # Step 4: Configure bot OAuth
|   +-- 05-dev-teams-manifest.sh      # Step 5: Generate Teams app package
|   +-- cleanup-deploy.sh             # Full cleanup (Azure + Entra + azd)
+-- infra/                             # Azure infrastructure (Bicep)
```

### Available Scripts

| Script | Role | Purpose |
|--------|------|---------|
| `01-admin-create-apps.sh` | Entra Admin | Creates Blueprint + Agent Identity apps, permissions, consent |
| `02-dev-generate-handoff.sh` | Developer | Generates handoff file for admin after azd provision |
| `03-admin-create-fic.sh` | Entra Admin | Creates Federated Identity Credential |
| `04-admin-bot-oauth.sh` | Entra Admin | Configures Bot OAuth connection |
| `05-dev-teams-manifest.sh` | Developer | Generates Teams app package |
| `00-admin-cleanup.sh` | Entra Admin | Removes app registrations (for cleanup/reset) |
| `cleanup-deploy.sh` | Developer | Full cleanup: Azure resources, Entra apps, azd env |

**Key SDK Packages:**
- **.NET:** `Microsoft.Agents.AI` (Microsoft Agent Framework for agent logic)
- **.NET:** `Azure.AI.OpenAI` (Azure OpenAI client with DefaultAzureCredential)
- **.NET:** `Microsoft.Agents.Builder` (Bot Framework integration)

> **Note:** This project uses code-first agents defined in `MafAgentService.cs`. The agent is NOT created in Foundry portal - it's entirely in .NET code using MAF's `AIAgent` class.

---

## Local Setup

### Step 1: Clone and Build

```bash
# Clone the repository
git clone <repository-url>
cd AgentId

# Build .NET application
cd OneDriveAgent
dotnet restore
dotnet build
cd ..
```

### Step 2: Run Automated Entra ID Setup

The project includes an automated setup command that creates all necessary Entra ID resources using the Microsoft Graph API.

```bash
# Login to Azure CLI with admin permissions
az login --tenant <your-tenant-id>

# Run the setup command
dotnet run setup --tenant-id <your-tenant-id>
```

**What the setup creates:**

| Resource | Description |
|----------|-------------|
| **OneDrive-Agent-Blueprint** | Parent app registration with exposed API scope |
| **OneDrive-Agent-Identity** | Child app registration with Graph permissions |
| **Service Principals** | Enterprise app entries for both apps |
| **API Scope** | `access_as_user` scope on Blueprint |
| **Pre-authorized Client** | Azure CLI authorized for testing |

**Example output:**

```
================================================================================
                    AGENT IDENTITY SETUP COMPLETE
================================================================================

Blueprint App ID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Agent Identity App ID:   yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy

NEXT STEPS:
================================================================================

1. Create a User Assigned Managed Identity in Azure Portal

2. Add Federated Identity Credential to Blueprint app:
   - Issuer: https://login.microsoftonline.com/<tenant-id>/v2.0
   - Subject: <managed-identity-client-id>
   - Audience: api://AzureADTokenExchange

3. Update appsettings.Development.json with the values above

4. Grant admin consent at:
   https://login.microsoftonline.com/<tenant-id>/adminconsent?client_id=<agent-identity-client-id>
```

### Step 3: Configure the Agent

For **local development**, you need a client secret on the Agent Identity app (since Managed Identity only works in Azure).

**Create a client secret:**

```bash
az ad app credential reset --id <agent-identity-client-id> --display-name "LocalDevSecret" --years 1
```

**Update `appsettings.Development.json`:**

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug",
      "Microsoft.AspNetCore": "Information"
    }
  },
  "FoundryAgent": {
    "ProjectEndpoint": "https://<your-foundry-resource>.services.ai.azure.com/api/projects/<your-project>",
    "ModelDeploymentName": "gpt-4o-mini",
    "AgentName": "OneDrive-Agent-Dev"
  },
  "AgentObo": {
    "TenantId": "<your-tenant-id>",
    "AgentBlueprintClientId": "<blueprint-app-id>",
    "AgentIdentityClientId": "<agent-identity-app-id>",
    "AgentIdentityClientSecret": "<client-secret-from-above>",
    "ManagedIdentityClientId": "<managed-identity-client-id>",
    "TargetScope": "https://graph.microsoft.com/.default"
  }
}
```

### Step 4: Grant Admin Consent

Grant admin consent for the Graph API permissions:

```bash
az ad app permission admin-consent --id <agent-identity-client-id>
```

Or open the admin consent URL in a browser:
```
https://login.microsoftonline.com/<tenant-id>/adminconsent?client_id=<agent-identity-client-id>
```

---

## Local Development & Testing

This section covers how to build, run, and test the agent locally.

### Prerequisites

1. **.NET 9 SDK** installed
2. **Azure CLI** logged in: `az login --tenant <your-tenant-id>`
3. **Deployment completed** (you need the app IDs and secrets from deployment)
4. **Dev Tunnel** (optional, for Agents Playground testing): `winget install Microsoft.devtunnel`
5. **Azure OpenAI RBAC access** - Your Azure CLI identity needs `Cognitive Services OpenAI User` role on the AI Services resource (see Step 1.5 below)

### Step 1: Configure appsettings.Development.json

Copy the template and fill in your values:

```bash
cd OneDriveAgent
cp appsettings.Development.json.template appsettings.Development.json
```

Edit `appsettings.Development.json` with values from your deployment:

```json
{
  "MafAgent": {
    "FoundryEndpoint": "https://ai-<env>.cognitiveservices.azure.com/",
    "ModelDeploymentName": "gpt-4o-mini"
  },
  "AgentObo": {
    "TenantId": "<from handoff/01-admin-output-*.txt>",
    "AgentBlueprintClientId": "<BLUEPRINT_CLIENT_ID from handoff>",
    "AgentIdentityClientId": "<AGENT_IDENTITY_CLIENT_ID from handoff>",
    "AgentIdentityClientSecret": "<AGENT_IDENTITY_CLIENT_SECRET from handoff>",
    "ManagedIdentityClientId": "<from azd env get-value MANAGED_IDENTITY_CLIENT_ID>",
    "TargetScope": "https://graph.microsoft.com/.default"
  },
  "Bot": {
    "MicrosoftAppId": "<same as AgentIdentityClientId>",
    "MicrosoftAppPassword": "<same as AgentIdentityClientSecret>",
    "MicrosoftAppTenantId": "<same as TenantId>",
    "OAuthConnectionName": "graph-connection"
  },
  "Connections": {
    "BotServiceConnection": {
      "Assembly": "Microsoft.Agents.Authentication.Msal",
      "Type": "MsalAuth",
      "Settings": {
        "AuthType": "ClientSecret",
        "TenantId": "<same as TenantId>",
        "ClientId": "<same as AgentIdentityClientId>",
        "ClientSecret": "<same as AgentIdentityClientSecret>",
        "Scopes": ["https://api.botframework.com/.default"]
      }
    }
  }
}
```

> **Tip:** Run `02-dev-generate-handoff.sh` to see all required values after `azd provision` (or `azd up`).

### Step 1.5: Grant Azure OpenAI RBAC Access

The agent uses `DefaultAzureCredential` to authenticate with Azure OpenAI. For local development, this uses your Azure CLI identity. You need the `Cognitive Services OpenAI User` role:

```bash
# Get your subscription ID
subId=$(az account show --query id -o tsv)

# Grant role (replace <env> with your environment name, e.g., onedriveagent10)
az role assignment create \
  --assignee "$(az account show --query user.name -o tsv)" \
  --role "Cognitive Services OpenAI User" \
  --scope "/subscriptions/$subId/resourceGroups/rg-<env>/providers/Microsoft.CognitiveServices/accounts/ai-<env>"
```

> **Note:** If you get a 401 error when calling the agent, check this RBAC assignment first.

### Step 2: Build and Run

```bash
cd OneDriveAgent

# Build
dotnet build

# Run in development mode
ASPNETCORE_ENVIRONMENT=Development dotnet run
```

The agent starts on `http://localhost:3978`.

### Step 3: Test with curl (API Endpoint)

```bash
# Get a token for the Agent Identity app
TOKEN=$(az account get-access-token \
  --resource api://$(azd env get-value AGENT_IDENTITY_CLIENT_ID) \
  --query accessToken -o tsv)

# Test the chat endpoint
curl -X POST http://localhost:3978/api/chat \
  -H "Content-Type: application/json" \
  -d "{\"message\": \"Show me my files\", \"userToken\": \"$TOKEN\"}"
```

**Expected response:**

```json
{
  "message": "Here are your main folders in OneDrive:\n\n- Documents\n- Photos\n- Projects\n\nNo files are directly found in the root folder. Would you like to open any of these folders to see what's inside?",
  "conversationId": "396262e9-f8e2-42f5-ab7f-cc770d52bdc9",
  "timestamp": "2026-02-09T08:38:00Z"
}
```

### Step 4: Test with Agents Playground (Bot Endpoint)

The [Microsoft Agents Playground](https://playground.dev.agents.azure.com) lets you test the bot interface with full SSO/OBO support.

#### 4.1 Create a Dev Tunnel

```bash
# Install dev tunnel CLI (Windows)
winget install Microsoft.devtunnel

# Or on macOS/Linux
# Follow: https://learn.microsoft.com/azure/developer/dev-tunnels/get-started

# Login to dev tunnels
devtunnel user login

# Create a persistent tunnel (reusable)
devtunnel create --allow-anonymous
devtunnel port create -p 3978

# Start the tunnel
devtunnel host
```

Note your tunnel URL (e.g., `https://abc123.devtunnels.ms`).

#### 4.2 Update Bot Messaging Endpoint (Temporary)

Point the Azure Bot Service to your tunnel:

```bash
# Get current bot name
BOT_NAME=$(azd env get-value BOT_NAME)

# Update messaging endpoint to tunnel
az bot update --resource-group rg-$(azd env get-value AZURE_ENV_NAME) \
  --name $BOT_NAME \
  --endpoint "https://<your-tunnel-url>/api/messages"
```

#### 4.3 Test in Agents Playground

1. Go to https://playground.dev.agents.azure.com
2. Click **"Add connection"**
3. Configure:
   - **Bot URL**: `https://<your-tunnel-url>/api/messages`
   - **App ID**: Your `AGENT_IDENTITY_CLIENT_ID`
4. Send a message like "Show me my OneDrive files"
5. Complete SSO sign-in if prompted

#### 4.4 Restore Production Endpoint

After testing, restore the Azure endpoint:

```bash
APP_URL=$(azd env get-value APP_SERVICE_URL)
az bot update --resource-group rg-$(azd env get-value AZURE_ENV_NAME) \
  --name $BOT_NAME \
  --endpoint "${APP_URL}/api/messages"
```

### More Example Queries

```bash
# List files in a specific folder
curl -X POST http://localhost:3978/api/chat \
  -H "Content-Type: application/json" \
  -d "{\"message\": \"Show me the files in Documents folder\", \"userToken\": \"$TOKEN\"}"

# Check storage usage
curl -X POST http://localhost:3978/api/chat \
  -H "Content-Type: application/json" \
  -d "{\"message\": \"How much storage do I have?\", \"userToken\": \"$TOKEN\"}"
```

### Debugging Tips

1. **View logs**: Logs are at Debug level in `appsettings.Development.json`
2. **Check Application Insights**: Even locally, telemetry goes to Application Insights if configured
3. **Validate token**: Use https://jwt.ms to decode and inspect tokens
4. **OBO issues**: Ensure `AgentIdentityClientSecret` is the `LocalDev-Secret-*` from Step 1

---

## Azure Deployment

### Quick Start with Azure Developer CLI (azd)

The fastest way to deploy is using `azd`:

**Prerequisites:**
1. [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) installed
2. Entra ID apps created (Blueprint + Agent Identity) - see [Step 3](#step-3-run-automated-entra-id-setup)

**Deploy:**

```bash
# Login to Azure
azd auth login

# Set required environment variables (from your Entra ID setup)
azd env set BLUEPRINT_CLIENT_ID "<your-blueprint-app-id>"
azd env set AGENT_IDENTITY_CLIENT_ID "<your-agent-identity-app-id>"

# Optional: customize deployment
azd env set APP_SERVICE_SKU "B1"           # B1, S1, P1v3, etc.

# Provision infrastructure and deploy
azd up
```

**What gets deployed:**

| Resource | Purpose |
|----------|---------|
| Resource Group | `rg-{env-name}` |
| AI Services + Foundry Project | Model deployments (gpt-4.1-mini) |
| User Assigned Managed Identity | `id-{env-name}` - for OBO token flow |
| App Service Plan + App Service | `app-{env-name}` - hosts the .NET app + MAF agent |
| RBAC Role Assignments | MI gets OpenAI Contributor/User roles |

**Post-deployment: Create Federated Identity Credential**

After `azd provision` (or `azd up`) completes, have the Entra Admin run:
```bash
./scripts/03-admin-create-fic.sh --blueprint-id <blueprint-id> --mi-client-id $(azd env get-value MANAGED_IDENTITY_CLIENT_ID)
```

**Test the deployment:**
```bash
APP_URL=$(azd env get-value APP_SERVICE_URL)
curl $APP_URL/health

TOKEN=$(az account get-access-token --resource api://$(azd env get-value AGENT_IDENTITY_CLIENT_ID) --query accessToken -o tsv)
curl -X POST $APP_URL/api/chat -H "Content-Type: application/json" \
  -d "{\"message\": \"List my files\", \"userToken\": \"$TOKEN\"}"
```

**Output variables from azd:**

| Variable | Description |
|----------|-------------|
| `PROJECT_ENDPOINT` | AI Foundry project endpoint |
| `MANAGED_IDENTITY_CLIENT_ID` | MI client ID (for FIC setup) |
| `APP_SERVICE_URL` | Deployed app URL |
| `APP_SERVICE_HOSTNAME` | App hostname |

---

### Manual Deployment (Alternative)

For manual deployment without `azd`, you need to:
1. Create Resource Group, User-Assigned Managed Identity, App Service Plan, and App Service
2. Assign the MI to the App Service
3. Create Federated Identity Credential on Blueprint (run `03-admin-create-fic.sh`)
4. Configure app settings with project endpoint, tenant ID, app IDs, and MI client ID
5. Publish with `dotnet publish` and deploy

See the Bicep files in `infra/` for the complete resource definitions.

---

## Publishing to M365 Copilot

To make your agent available in Microsoft 365 Copilot and Teams, this project uses the **Microsoft 365 Agents SDK** and **Azure Bot Service**.

### Architecture Overview

```
+-------------------------------------------------------------------------+
|                    M365 COPILOT INTEGRATION                             |
+-------------------------------------------------------------------------+
|                                                                         |
|  +-------------+      +-------------+      +----------------------+     |
|  |   M365      |      |   Azure Bot |      |   Your Agent         |     |
|  |   Copilot   |<---->|   Service   |<---->|   (App Service)      |     |
|  |             |      |   (Channel) |      |                      |     |
|  +-------------+      +-------------+      |  +----------------+  |     |
|                                            |  | M365 Agents SDK|  |     |
|                                            |  | + Bot Framework|  |     |
|  +-------------+                           |  +----------------+  |     |
|  |   Teams     |<---- Also connects ------>|          |          |     |
|  |   Client    |                           |          v          |     |
|  +-------------+                           |  +----------------+  |     |
|                                            |  |  OBO + Graph   |  |     |
|                                            |  |  (OneDrive)    |  |     |
|                                            |  +----------------+  |     |
|                                            +----------------------+     |
|                                                                         |
+-------------------------------------------------------------------------+
```

### Actual Implementation

The bot/Teams integration is already implemented in this project:

| File | Purpose |
|------|---------|
| [Program.cs](Program.cs) | Configures M365 Agents SDK with `builder.AddAgent<OneDriveAgentBot>()` |
| [OneDriveAgentBot.cs](Services/OneDriveAgentBot.cs) | Bot message handler with SSO token exchange |
| [BotConfig.cs](Services/BotConfig.cs) | Bot configuration and pre-authorized client IDs |
| [scripts/04-admin-bot-oauth.sh](../scripts/04-admin-bot-oauth.sh) | Creates Bot OAuth connection for SSO |
| [teams-manifest/](../teams-manifest/) | Teams app manifest templates |

### Deployment Steps

See [Phase 5 (Optional): Teams/M365 Copilot Publishing](#phase-5-optional-teamsm365-copilot-publishing) in the deployment guide above for the complete deployment process using the provided scripts.

### Key Differences: Declarative Agent vs M365 Agents SDK

| Aspect | Declarative Agent | M365 Agents SDK (this project) |
|--------|-------------------|-------------------------------|
| Complexity | Low (config only) | Higher (code required) |
| OBO Support | Via OpenAPI plugin | Full control in code |
| Hosting | Copilot handles routing | You manage Bot Service |
| Customization | Limited to manifest | Full programmatic control |
| SSO | Automatic | Implemented via Bot Framework |
| Use case | Simple API wrappers | Complex agents with OBO |

For agents requiring **OBO with custom logic** (like this OneDrive agent), the M365 Agents SDK approach is required.

---

## API Reference

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Welcome message |
| `/health` | GET | Health check with timestamp |
| `/api/chat` | POST | Send a message to the agent |

### POST /api/chat

**Request:**

```json
{
  "message": "Show me my files",
  "userToken": "eyJ0eXAiOiJKV1QiLCJhbGciOiJS...",
  "conversationId": "optional-conversation-id"
}
```

**Response:**

```json
{
  "message": "Here are your OneDrive folders:\n\n- Documents\n- Photos\n...",
  "conversationId": "396262e9-f8e2-42f5-ab7f-cc770d52bdc9",
  "timestamp": "2026-02-09T08:38:00Z"
}
```

### Available Commands

| Query | Function Called | Description |
|-------|----------------|-------------|
| "Show me my files" | `listOneDriveFiles` | Lists root OneDrive contents |
| "What's in Documents?" | `listOneDriveFiles` | Lists folder contents |
| "How much storage?" | `getDriveInfo` | Shows quota and usage |

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Not authenticated" | OBO token not set | Ensure `userToken` is passed in request |
| "Invalid audience" | Token targets wrong app | Get token for Agent Identity app, not Blueprint |
| "AADSTS500131" | Audience mismatch | User token audience must match client_id in OBO request |
| "169.254.169.254 unreachable" | MI only works in Azure | Use client secret for local development |
| "Admin consent required" | Permissions not consented | Run `az ad app permission admin-consent` |
| "Access denied" | Missing permission | Add required Graph delegated permissions |
| "401 Unauthorized" from OpenAI | Missing RBAC role | Grant `Cognitive Services OpenAI User` role to your Azure CLI identity (see Step 1.5) |
| Health endpoint returns 404 | App listening on wrong port | Set `ASPNETCORE_URLS=http://0.0.0.0:8080` in App Service settings |
| No response from bot | `/api/messages` not mapped | Ensure `app.MapPost("/api/messages", ...)` is in Program.cs |
| SSO shows sign-in card | Teams clients not pre-authorized | Pre-authorize Teams client IDs (see Phase 5.2) |

### Azure App Service Port Configuration

**Important:** Azure App Service Linux requires apps to listen on port 8080. The M365 Agents SDK defaults to port 3978 for local development. 

The infrastructure templates set `ASPNETCORE_URLS=http://0.0.0.0:8080` automatically. If you see 404 errors on the health endpoint after deployment, verify this setting:

```bash
# Check current settings
az webapp config appsettings list --name <app-name> --resource-group <rg> --query "[?name=='ASPNETCORE_URLS']"

# Set if missing
az webapp config appsettings set --name <app-name> --resource-group <rg> --settings ASPNETCORE_URLS=http://0.0.0.0:8080
```

### Debug Logging

Enable detailed logging in `appsettings.Development.json`:

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug",
      "OneDriveAgent": "Debug",
      "Azure.AI": "Debug"
    }
  }
}
```

### Verify Token Audience

Decode your token at [jwt.ms](https://jwt.ms) and check:
- `aud` claim should be `api://<agent-identity-client-id>`
- `scp` claim should include `access_as_user`

---

## References

### Microsoft Entra Agent ID

- [Agent On-Behalf-Of OAuth Flow](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/agent-on-behalf-of-oauth-flow)
- [Agent OAuth Protocols](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/agent-oauth-protocols)
- [Agent Identity Overview](https://learn.microsoft.com/en-us/entra/agent-id/overview)

### Azure AI & Microsoft Agent Framework

- [Microsoft Agent Framework (MAF)](https://github.com/microsoft/agents) - Code-first agent development
- [Azure.AI.OpenAI SDK](https://learn.microsoft.com/en-us/dotnet/api/azure.ai.openai) - Azure OpenAI client
- [Microsoft.Extensions.AI](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.ai) - AI abstractions for .NET
- [Function Calling with Azure OpenAI](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/function-calling)

### Built-in Tools

- [SharePoint Tool (requires M365 Copilot)](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/tools-classic/sharepoint)
- [Azure Function Tool](https://learn.microsoft.com/en-us/azure/ai-services/agents/how-to/tools/azure-functions)
- [OpenAPI Tool](https://learn.microsoft.com/en-us/azure/ai-services/agents/how-to/tools/openapi-spec)

### Microsoft Graph

- [OneDrive API - List Children](https://learn.microsoft.com/en-us/graph/api/driveitem-list-children)
- [OneDrive API - Get Drive](https://learn.microsoft.com/en-us/graph/api/drive-get)

### M365 Copilot

- [Build Declarative Agents](https://learn.microsoft.com/en-us/microsoft-365-copilot/extensibility/build-declarative-agents)
- [Teams App Manifest](https://learn.microsoft.com/en-us/microsoftteams/platform/resources/schema/manifest-schema)
- [M365 Copilot Retrieval API](https://learn.microsoft.com/en-us/microsoft-365-copilot/extensibility/api-reference/retrieval-api-overview) - Used by SharePoint Tool

---

## License

MIT License - See [LICENSE](LICENSE) for details.
