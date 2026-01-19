# MAF M365 Copilot Agent

A **Microsoft Agent Framework (MAF)** agent deployed on **Azure Functions** that works with **Microsoft Teams**, **M365 Copilot**, and **Bot Framework Web Chat**.

## Features

- 🤖 **MAF Durable Agent** - Stateful agent with durable orchestration
- 🛠️ **Function Tools** - Weather, time, and echo tools demonstrating function calling
- 🎯 **Custom Engine Agent** - Full control over orchestration across Teams & M365 Copilot
- ⚡ **Azure Functions** - Serverless hosting with HTTP trigger
- 💾 **Durable Task Scheduler (DTS)** - Persistent conversation state via Azure-managed backend
- ☁️ **Azure OpenAI** - GPT model integration via Azure AI Foundry
- 🎮 **Multi-Channel** - Works with Teams, M365 Copilot, Web Chat, and Agents Playground
- 🔐 **Bot Framework Auth** - JWT token validation for secure production deployment

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                            Channels                                │
│  Microsoft Teams │ M365 Copilot │ Web Chat │ Agents Playground     │
└────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│                       Azure Bot Service                            │
│                 (Routes messages, handles auth)                    │
└────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│                      Azure Functions Host                          │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                        MAFAdapter                            │  │
│  │  - POST /api/messages (Bot Framework protocol)               │  │
│  │  - JWT token validation (production) / bypass (local)        │  │
│  │  - Calls Azure OpenAI via IChatClient                        │  │
│  │  - Proactive messaging to serviceUrl                         │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                 │                                  │
│                                 ▼                                  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │            Microsoft.Extensions.AI (IChatClient)             │  │
│  │  - Function invocation pipeline                              │  │
│  │  - AIFunction tools (GetWeather, GetCurrentTime)             │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
                │                                │
                ▼                                ▼
┌──────────────────────────────┐  ┌──────────────────────────────────┐
│      Azure AI Foundry        │  │   Durable Task Scheduler (DTS)   │
│  (Model inference via SDK)   │  │       (State persistence)        │
│    Uses Managed Identity     │  │     Deployed to North Europe     │
└──────────────────────────────┘  └──────────────────────────────────┘
```

## Why Bot Framework?

This project uses **Azure Bot Service** and the **Bot Framework protocol** as the messaging layer for several important reasons:

### 1. M365 Copilot Requires Bot Framework
**M365 Copilot only supports custom agents via Bot Framework.** When you create a Custom Engine Agent for M365 Copilot, messages are routed through Azure Bot Service to your endpoint using the Bot Framework protocol (`/api/messages`). There is no alternative—if you want your agent in M365 Copilot, you need Bot Framework.

### 2. Microsoft Teams Integration  
Teams also uses Bot Framework as its messaging backbone. By building on Bot Framework, your agent automatically works across Teams (personal chats, channels, group chats) without additional code.

### 3. Multi-Channel from One Endpoint
Azure Bot Service acts as a **channel router**, translating native channel protocols (Teams, Slack, Web Chat, etc.) into a unified Bot Framework Activity format. Your code handles one protocol, and Bot Service handles the rest.

### 4. Built-in Authentication
Bot Framework provides **JWT token validation** for securing your endpoint. When Azure Bot Service forwards messages to your function, it includes a signed JWT token proving the request came from a legitimate channel.

### 5. Proactive Messaging
Bot Framework's `serviceUrl` pattern enables **proactive replies**—your agent can send responses back to the conversation asynchronously. This is essential for long-running operations where you need to reply after processing completes.

```
Without Bot Framework:        With Bot Framework:
┌──────────────────┐          ┌──────────────────┐
│   Your Agent     │          │   Your Agent     │
│   (HTTP API)     │          │   (HTTP API)     │
└────────┬─────────┘          └────────┬─────────┘
         │                             │
         ▼                             ▼
    ❌ Teams                 ┌──────────────────┐
    ❌ M365 Copilot          │  Azure Bot Svc   │
    ❌ Web Chat              └────────┬─────────┘
    ✅ Custom clients only            │
                             ┌────────┴─────────┐
                             ▼        ▼         ▼
                          Teams   M365 Cop   Web Chat
```

## Why Not Full M365 Agents SDK?

The **M365 Agents SDK** (`Microsoft.Agents.*` packages) provides excellent abstractions for building bots, including built-in authentication via `AddAgentAspNetAuthentication()`. However, **this project uses Azure Functions isolated worker**, which has a critical incompatibility:

### The Problem: ASP.NET Core vs Azure Functions

| Feature | ASP.NET Core | Azure Functions (Isolated) |
|---------|--------------|---------------------------|
| **SDK Auth Helper** | ✅ `AddAgentAspNetAuthentication()` | ❌ Not supported |
| **DI Pipeline** | `IServiceCollection` + middleware | `HostBuilder` (different pipeline) |
| **Request Type** | `HttpRequest` | `HttpRequestData` |
| **Auth Middleware** | `UseAuthentication()` / `UseAuthorization()` | Must validate manually |

The M365 Agents SDK's authentication is designed for ASP.NET Core's middleware pipeline. Azure Functions isolated worker doesn't have this middleware concept—each function handles its own request independently.

### What We Use from M365 Agents SDK

We still leverage several M365 Agents SDK packages for non-auth purposes:

| Package | What We Use |
|---------|-------------|
| `Microsoft.Agents.Core` | `Activity`, `ActivityTypes`, `ChannelAccount`, `Channels` models |
| `Microsoft.Agents.Authentication` | `AuthenticationConstants` (issuer URLs, metadata endpoints) |

### What We Had to Build Ourselves

Since SDK auth doesn't work with Azure Functions, we implemented:

1. **`BotTokenValidator.cs`** - Custom JWT validation using:
   - `JwtSecurityTokenHandler` for token parsing
   - OIDC configuration from Bot Framework metadata endpoint
   - Valid issuers from `AuthenticationConstants`
   - Audience validation against App Registration

2. **`MAFAdapter.cs`** - Bot Framework protocol adapter:
   - Extracts Bearer token from Authorization header
   - Validates tokens via `BotTokenValidator`
   - Parses `Activity` objects from request body
   - Sends proactive replies to `serviceUrl`

### The Trade-off

| Approach | Pros | Cons |
|----------|------|------|
| **ASP.NET Core + SDK Auth** | One-line auth setup, SDK handles everything | No serverless, always-on hosting cost |
| **Azure Functions + Custom Auth** | Serverless, pay-per-use, auto-scale | Must implement JWT validation manually |

We chose Azure Functions for **cost efficiency** (pay only when invoked) and **auto-scaling**, accepting the trade-off of implementing authentication ourselves.

### Future: When SDK Supports Functions

If Microsoft adds Azure Functions support to the M365 Agents SDK (e.g., `AddAgentFunctionsAuthentication()`), this project could be simplified to:

```csharp
// Hypothetical future API
services.AddAgentFunctionsAuthentication(options => {
    options.ClientId = Environment.GetEnvironmentVariable("MicrosoftAppId");
    options.TenantId = Environment.GetEnvironmentVariable("MicrosoftAppTenantId");
});
```

Until then, `BotTokenValidator.cs` bridges the gap.

## Prerequisites

### For Local Development
- [.NET 8.0 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/8.0)
- [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local)
- [Azurite](https://learn.microsoft.com/azure/storage/common/storage-use-azurite) for local storage emulation
- [Durable Task Scheduler Emulator](https://github.com/microsoft/durabletask-azuremanaged)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) authenticated (`az login`)

### For Azure Deployment
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- Azure subscription with permissions to create resources
- Azure AI Foundry project with deployed model

## Quick Start (Local Development)

1. **Login to Azure** (for Azure OpenAI access):
   ```bash
   az login
   ```

2. **Start Azurite** (storage emulator):
   ```bash
   azurite --silent
   ```

3. **Start Durable Task Scheduler Emulator**:
   ```bash
   docker run -d -p 8080:8080 -p 8081:8081 -p 8082:8082 mcr.microsoft.com/dts/dts-emulator:latest
   ```
   - Dashboard available at http://localhost:8082

4. **Configure local.settings.json**:
   ```json
   {
     "IsEncrypted": false,
     "Values": {
       "AzureWebJobsStorage": "UseDevelopmentStorage=true",
       "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
       "DURABLE_TASK_SCHEDULER_CONNECTION_STRING": "Endpoint=http://localhost:8080;TaskHub=default;Authentication=None",
       "AZURE_OPENAI_ENDPOINT": "https://your-resource.services.ai.azure.com/",
       "AZURE_OPENAI_DEPLOYMENT": "gpt-4.1-mini",
       "TASKHUB_NAME": "default",
       "MicrosoftAppId": "",
       "MicrosoftAppPassword": "",
       "MicrosoftAppTenantId": ""
     },
     "Host": {
       "LocalHttpPort": 3978
     }
   }
   ```
   > **Note**: Empty auth values disable JWT validation for local testing.

5. **Start the Function App**:
   ```bash
   func start
   ```

6. **Test with Agents Playground**:
   - Install the [Agents Playground VS Code Extension](https://marketplace.visualstudio.com/items?itemName=TeamsDevApp.vscode-agents-playground)
   - Connect to `http://localhost:3978/api/messages`
   - Send: "What's the weather in Seattle?"

## Deploy to Azure

### Using Azure Developer CLI (azd)

1. **Initialize** (first time only):
   ```bash
   azd init
   ```

2. **Deploy**:
   ```bash
   azd up
   ```

   This creates:
   - Resource Group
   - Azure Function App
   - Azure Bot Service (with Teams & Web Chat channels)
   - Durable Task Scheduler (North Europe)
   - App Registration (multi-tenant)
   - Role assignments for AI Foundry

3. **Configure Bot Messaging Endpoint**:
   After deployment, update the Bot Service messaging endpoint in Azure Portal:
   ```
   https://<function-app-name>.azurewebsites.net/api/messages
   ```

### Infrastructure Components

| Resource | Purpose |
|----------|---------|
| Azure Function App | Hosts the MAF agent |
| Azure Bot Service | Routes messages from channels |
| Durable Task Scheduler | Persists conversation state |
| App Registration | Bot Framework authentication |
| Managed Identity | Secure access to AI Foundry |

## Testing

### Web Chat (Azure Portal)
1. Go to **Azure Portal** → **Bot Service** → **Test in Web Chat**
2. Send a message like "What's the weather in Seattle?"

### Microsoft Teams
1. **Upload the app** to Teams Admin Center:
   - Go to https://admin.teams.microsoft.com/
   - **Teams apps** → **Manage apps** → **Upload new app**
   - Upload `MAFWeatherAgent.zip`

2. **Enable for users**:
   - **Teams apps** → **Permission policies** → **Global**
   - Under "Custom apps", allow all apps or add this specific app

3. **Find in Teams**:
   - Open Teams → **Apps** → Search "MAF Weather Agent"
   - Or look under **"Built for your org"**

### M365 Copilot
1. **Prerequisites**:
   - M365 Copilot license assigned to user
   - Copilot extensions enabled in M365 Admin Center
   - App installed in Teams first

2. **Access**:
   - Go to https://microsoft365.com/copilot
   - Type `@` and select "MAF Weather Agent"
   - Or type `@MAF Weather Agent What's the weather in Seattle?`

### Creating the Teams App Package

The app manifest is in `appManifest/`:
```
appManifest/
├── manifest.json       # Teams/M365 Copilot custom engine agent manifest
├── color.png          # 192x192 color icon
└── outline.png        # 32x32 outline icon
```

To create the zip package:
```powershell
cd appManifest
Compress-Archive -Path manifest.json,color.png,outline.png -DestinationPath ../MAFWeatherAgent.zip -Force
```

> **Note**: This uses a **custom engine agent** configuration, which routes M365 Copilot messages through your bot endpoint (same as Teams). This enables tool calling across all channels.

## Project Structure

```
MAF-M365-Copilot-Agent/
├── Program.cs                # Entry point, DI configuration, tool registration
├── WeatherAgent.cs           # Agent tools (GetWeather, GetCurrentTime, Echo)
├── MAFAdapter.cs             # Bot Framework adapter with JWT auth
├── host.json                 # Azure Functions + DTS configuration
├── local.settings.json       # Local settings (gitignored)
├── appManifest/              # Teams/M365 Copilot app manifest
│   ├── manifest.json         # Custom engine agent manifest
│   ├── color.png
│   └── outline.png
├── infra/                    # Bicep infrastructure (azd)
│   ├── main.bicep
│   ├── main.parameters.json
│   └── modules/
└── .vscode/
    ├── launch.json           # F5 debug configuration
    └── tasks.json            # Build tasks
```

## Adding Tools

Tools are defined as instance methods in [WeatherAgent.cs](WeatherAgent.cs):

```csharp
public class WeatherAgent
{
    [Description("Gets the current weather for a location.")]
    public string GetWeather(
        [Description("The city name, e.g. 'Seattle', 'New York'")] string location) 
        => location.ToLowerInvariant() switch
        {
            "seattle" => "🌧️ Seattle: 52°F, Rainy",
            "new york" => "☀️ New York: 68°F, Sunny",
            _ => $"🌡️ {location}: 65°F, Typical weather"
        };

    [Description("Gets the current date and time.")]
    public string GetCurrentTime() 
        => $"🕐 Current time: {DateTime.Now:f}";

    [Description("Returns a banana sandwich. Use this to test tool calling.")]
    public string Echo()
        => "🍌 Banana Sandwich 🥪";
}
```

Tools are registered in [Program.cs](Program.cs) using `AIFunctionFactory.Create`:

```csharp
var weatherAgent = new WeatherAgent();
var tools = new AIFunction[]
{
    AIFunctionFactory.Create(weatherAgent.GetWeather),
    AIFunctionFactory.Create(weatherAgent.GetCurrentTime),
    AIFunctionFactory.Create(weatherAgent.Echo)
};
```

### Adding a New Tool

1. Add an instance method with `[Description]` attribute in `WeatherAgent.cs`:
   ```csharp
   [Description("Searches for information on a topic.")]
   public string Search(
       [Description("The search query")] string query) 
       => $"Results for: {query}";
   ```

2. Register it in `Program.cs`:
   ```csharp
   var tools = new AIFunction[]
   {
       AIFunctionFactory.Create(weatherAgent.GetWeather),
       AIFunctionFactory.Create(weatherAgent.GetCurrentTime),
       AIFunctionFactory.Create(weatherAgent.Echo),
       AIFunctionFactory.Create(weatherAgent.Search)  // Add new tool
   };
   ```

3. Restart the function app and redeploy.

## Authentication

### Local Development
- Leave `MicrosoftAppId`, `MicrosoftAppPassword`, and `MicrosoftAppTenantId` empty
- JWT validation is bypassed when these are empty

### Production (Azure)
- App Registration must be **multi-tenant** (required by Bot Framework)
- Credentials are configured via Azure Key Vault references
- Managed Identity is used for AI Foundry access

## Troubleshooting

### Bot not responding in Teams
1. Check the Function App logs in Azure Portal
2. Verify the messaging endpoint is correct: `https://<app>.azurewebsites.net/api/messages`
3. Ensure the App Registration is multi-tenant

### Agent not appearing in M365 Copilot
1. Verify M365 Copilot license is assigned
2. Check that the app is installed in Teams first
3. Wait 15-30 minutes for sync after uploading
4. Ensure Copilot extensions are enabled in admin settings

### "Permission denied" errors
1. Verify Managed Identity has `Cognitive Services OpenAI User` role on AI Foundry
2. Check the principal ID used for role assignment (should be Managed Identity, not App Registration)

### Teams admin can see app but users cannot
1. Go to Teams Admin Center → **Permission policies**
2. Ensure custom apps are allowed for users
3. Wait for policy propagation (can take up to 24 hours)

## Key Packages

| Package | Purpose |
|---------|---------|
| `Microsoft.Agents.AI.Hosting.AzureFunctions` | MAF Durable Agent hosting |
| `Microsoft.Agents.AI.OpenAI` | OpenAI/Azure OpenAI integration |
| `Microsoft.Azure.Functions.Worker` | Azure Functions runtime |
| `Azure.AI.OpenAI` | Azure OpenAI client |
| `Azure.Identity` | DefaultAzureCredential for auth |
| `Microsoft.Extensions.AI` | IChatClient abstraction |
| `System.IdentityModel.Tokens.Jwt` | JWT token validation |

## License

MIT
