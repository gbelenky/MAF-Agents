# Microsoft Agent Framework + M365 Agents SDK Sample

This sample demonstrates how to build an AI Agent using **Microsoft Agent Framework** and expose it through the **M365 Agents SDK** for integration with Microsoft Teams and M365 Copilot.

## Features

- 🤖 **Microsoft Agent Framework (MAF)** - Flexible AI agent with tool calling capabilities
- 🔧 **Function Tools** - Weather and time tools demonstrating function calling
- 📱 **M365 Agents SDK** - Expose the agent to Teams and M365 Copilot channels
- 💬 **Multi-turn Conversations** - Conversation history is preserved across turns
- 🔐 **Authentication** - Supports Azure Bot Service authentication
- ☁️ **Microsoft Foundry** - Native integration with Azure AI Foundry

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       M365 Channels                         │
│               (Teams, M365 Copilot, WebChat)                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│               M365 Agents SDK (ASP.NET Core)                │
│  - MAFAdapter                                               │
│  - Authentication & Authorization                           │
│  - Activity Handling                                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│             Microsoft Agent Framework (MAF)                 │
│  - MyAIAgent (AIAgent)                                      │
│  - Tool Calling (GetWeather, GetTime)                       │
│  - Conversation Thread Management                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Microsoft Foundry                        │
│            (Azure AI Foundry with deployed model)           │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- [.NET 8.0 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/8.0) or later
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) - for authentication
- [Agents Playground](https://github.com/microsoft/agents-playground) - for local testing (`winget install agentsplayground`)
- [dev tunnel](https://learn.microsoft.com/azure/developer/dev-tunnels/get-started?tabs=windows) (optional, for Teams/WebChat testing)
- **Microsoft Foundry** - Azure AI Foundry project with a deployed model

## Configuration

### 1. Configure Microsoft Foundry

Edit `appsettings.Development.json` for local development:

```json
"Foundry": {
  "ProjectEndpoint": "https://your-resource.openai.azure.com/",
  "ModelDeployment": "your-model-deployment-name"
}
```

> ⚠️ **Important Endpoint Format:**
> - Use the **Azure OpenAI endpoint** format: `https://your-resource.openai.azure.com/`
> - Do **NOT** use the Foundry project endpoint with `/api/projects/...` path
> - Find the correct endpoint in Azure AI Foundry → Models + endpoints → Your deployment → Target URI

### 2. Configure Azure Authentication

This project uses `DefaultAzureCredential` for authentication. Before running:

1. **Login to Azure CLI:**
   ```bash
   az login
   ```

2. **Assign the required role** on your Azure OpenAI / AI Foundry resource:
   
   | Role | Purpose |
   |------|---------|
   | **Cognitive Services OpenAI User** | Required for making inference calls to models |
   
   To assign via Azure Portal:
   - Go to your Azure AI Foundry resource → **Access control (IAM)**
   - Click **Add** → **Add role assignment**
   - Select **Cognitive Services OpenAI User**
   - Assign to your user account

   Or via Azure CLI:
   ```bash
   az role assignment create \
     --role "Cognitive Services OpenAI User" \
     --assignee your-email@domain.com \
     --scope /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{resource-name}
   ```

### 3. Configure Authentication (Optional for Teams/Copilot)

For Azure Bot Service integration, configure the `TokenValidation` and `Connections` sections.

## QuickStart using Agents Playground

1. Login to Azure (required for model access):
   ```bash
   az login
   ```

2. Start the agent:
   ```bash
   dotnet run
   ```
   
   > The project includes `Properties/launchSettings.json` which automatically sets `ASPNETCORE_ENVIRONMENT=Development` to load `appsettings.Development.json`.

3. Start Agents Playground (in a new terminal or from Start menu):
   ```bash
   agentsplayground
   ```

4. In Agents Playground:
   - The endpoint should auto-detect as `http://localhost:3978/api/messages`
   - Type a message and press Enter to chat with the agent

## Troubleshooting

### 401 Unauthorized Error
- **Cause:** Azure credentials don't have access to the model
- **Fix:** Ensure you have **Cognitive Services OpenAI User** role assigned on the resource
- **Fix:** Run `az login` to refresh credentials

### "No such host" Error
- **Cause:** Wrong endpoint format in configuration
- **Fix:** Use `https://your-resource.openai.azure.com/` (not the Foundry project URL with `/api/projects/...`)

### "Foundry:ProjectEndpoint is not configured" Error
- **Cause:** Development environment not loaded
- **Fix:** Ensure `Properties/launchSettings.json` exists with `ASPNETCORE_ENVIRONMENT=Development`
- **Fix:** Or run with: `ASPNETCORE_ENVIRONMENT=Development dotnet run`

### Agent not responding / "No text was streamed"
- **Cause:** Model deployment name mismatch
- **Fix:** Verify `ModelDeployment` in config matches your actual deployment name in Azure AI Foundry

## QuickStart using WebChat or Teams

1. Create an Azure Bot with one of these authentication types:
   - [SingleTenant, Client Secret](https://learn.microsoft.com/en-us/microsoft-365/agents-sdk/azure-bot-create-single-secret)
   - [SingleTenant, Federated Credentials](https://learn.microsoft.com/en-us/microsoft-365/agents-sdk/azure-bot-create-federated-credentials)
   - [User Assigned Managed Identity](https://learn.microsoft.com/en-us/microsoft-365/agents-sdk/azure-bot-create-managed-identity)

2. Run dev tunnel for local testing:
   ```bash
   devtunnel host -p 3978 --allow-anonymous
   ```

3. Update the Azure Bot messaging endpoint to `{tunnel-url}/api/messages`

4. Start the agent:
   ```bash
   dotnet run
   ```

## Deploying to Teams and M365 Copilot

1. Edit `appManifest/manifest.json`:
   - Replace `{{AAD_APP_CLIENT_ID}}` with your Azure Bot's App ID
   - Replace `{{BOT_DOMAIN}}` with your deployed domain

2. Create the manifest package:
   - Zip the contents of `appManifest/` folder (manifest.json, color.png, outline.png)

3. Add the **Microsoft Teams** channel to your Azure Bot

4. Upload the manifest package via Microsoft Admin Portal or Teams Admin Center

## Deployment & Hosting

### Hosting Options

| Option | Best For | Scaling |
|--------|----------|---------|
| **Azure App Service** | Production workloads | Auto-scale, deployment slots |
| **Azure Container Apps** | Containerized deployments | Serverless containers |
| **Azure Kubernetes Service** | Enterprise, multi-agent | Full orchestration |

### Deploy to Azure App Service

1. **Create an App Service:**
   ```bash
   az webapp create --resource-group <rg> --plan <plan> --name <app-name> --runtime "DOTNET:8.0"
   ```

2. **Configure App Settings** (equivalent to `appsettings.json`):
   ```bash
   az webapp config appsettings set --resource-group <rg> --name <app-name> --settings \
     Foundry__ProjectEndpoint="https://your-resource.openai.azure.com/" \
     Foundry__ModelDeployment="your-model-deployment-name" \
     TokenValidation__Enabled="true" \
     TokenValidation__Audiences__0="<your-bot-app-id>" \
     TokenValidation__TenantId="<your-tenant-id>"
   ```

3. **Enable Managed Identity** (recommended for Foundry auth):
   ```bash
   az webapp identity assign --resource-group <rg> --name <app-name>
   ```
   Then assign **Cognitive Services OpenAI User** role to the managed identity.

4. **Deploy the code:**
   ```bash
   dotnet publish -c Release -o ./publish
   az webapp deploy --resource-group <rg> --name <app-name> --src-path ./publish --type zip
   ```

5. **Update Azure Bot messaging endpoint:**
   ```
   https://<app-name>.azurewebsites.net/api/messages
   ```

### Production Configuration

For production deployments, update `appsettings.json`:

```json
{
  "Foundry": {
    "ProjectEndpoint": "https://your-resource.openai.azure.com/",
    "ModelDeployment": "your-model-deployment-name"
  },
  "TokenValidation": {
    "Enabled": true,
    "Audiences": ["<your-bot-app-id>"],
    "TenantId": "<your-tenant-id>"
  },
  "Connections": {
    "ServiceConnection": {
      "Settings": {
        "AuthType": "ManagedIdentity",
        "ClientId": "<managed-identity-client-id>"
      }
    }
  }
}
```

### Authentication in Production

| Auth Type | When to Use | Configuration |
|-----------|-------------|---------------|
| **Managed Identity** | Azure-hosted, most secure | `AuthType: ManagedIdentity` |
| **Federated Credentials** | GitHub Actions, no secrets | Workload identity federation |
| **Client Secret** | Legacy, external hosting | `AuthType: ClientCredentials` |

> ⚠️ **Important:** Always enable `TokenValidation` in production to secure your `/api/messages` endpoint.

## Key Components

### MAFAdapter - The Bridge Between Frameworks

The `MAFAdapter` class is the core integration point that bridges **Microsoft Agent Framework (MAF)** with the **M365 Agents SDK**:

```
M365 Channels (Teams/Copilot) → M365 Agents SDK → MAFAdapter → MAF AIAgent → AI Model
```

**What it does:**
- Extends `AgentApplication` from M365 Agents SDK to receive bot activities
- Wraps a MAF `AIAgent` instance to handle the actual AI processing
- Converts M365 activities into MAF conversation threads
- Streams responses back to the M365 channel

**Why it exists:**
- MAF provides powerful AI agent capabilities (tool calling, conversation management)
- M365 Agents SDK provides the channel integration (Teams, Copilot, WebChat)
- MAFAdapter connects these two worlds, letting you use MAF's AI features through M365 channels

**Key code flow:**
```csharp
protected override async Task OnMessageActivityAsync(ITurnContext<IMessageActivity> turnContext, ...)
{
    // 1. Get or create conversation thread for this chat
    var threadId = turnContext.Activity.Conversation.Id;
    
    // 2. Send message to MAF agent and stream response
    await foreach (var content in _agent.RunAsync(threadId, message))
    {
        // 3. Stream text back to Teams/Copilot
        await turnContext.StreamMessageAsync(content.Text);
    }
}
```

### Adapter Pattern for Other Frameworks

The same adapter pattern can be used with other AI agent frameworks. Here's an example for **LangChain (Python)**:

```python
from botbuilder.core import ActivityHandler, TurnContext
from langchain.agents import AgentExecutor
from langchain_openai import AzureChatOpenAI
from langchain.memory import ConversationBufferMemory

class LangChainAdapter(ActivityHandler):
    """Adapter: LangChain Agent → M365 Agents SDK (Python)"""
    
    def __init__(self, agent_executor: AgentExecutor):
        self._agent = agent_executor
        self._memories: dict[str, ConversationBufferMemory] = {}
    
    async def on_message_activity(self, turn_context: TurnContext):
        # 1. Get or create conversation memory for this chat
        conversation_id = turn_context.activity.conversation.id
        if conversation_id not in self._memories:
            self._memories[conversation_id] = ConversationBufferMemory(
                memory_key="chat_history", return_messages=True
            )
        
        # 2. Invoke LangChain agent with user message
        user_message = turn_context.activity.text
        response = await self._agent.ainvoke({
            "input": user_message,
            "chat_history": self._memories[conversation_id].chat_memory.messages
        })
        
        # 3. Update memory and send response back to Teams/Copilot
        self._memories[conversation_id].save_context(
            {"input": user_message}, {"output": response["output"]}
        )
        await turn_context.send_activity(response["output"])
```

**Usage with FastAPI and Bot Framework:**
```python
from botbuilder.core import BotFrameworkAdapter
from fastapi import FastAPI, Request

app = FastAPI()
adapter = BotFrameworkAdapter()
langchain_adapter = LangChainAdapter(your_agent_executor)

@app.post("/api/messages")
async def messages(request: Request):
    body = await request.json()
    activity = Activity().deserialize(body)
    await adapter.process_activity(activity, "", langchain_adapter.on_turn)
```

> 💡 **Tip:** The adapter pattern works with any AI framework—Semantic Kernel, AutoGen, CrewAI, etc. The key is extending `ActivityHandler` (Python) or `AgentApplication` (C#) to bridge your framework with M365 channels.

## Project Structure

```
MAF-M365-Copilot-Agent/
├── Program.cs                      # Application entry point and DI configuration
├── MAFAdapter.cs                   # Adapter: MAF Agent → M365 Agents SDK
├── AspNetExtensions.cs             # JWT authentication extensions for production
├── Agents/
│   └── MyAIAgent.cs               # Microsoft Agent Framework AI Agent with tools
├── appsettings.json               # Configuration for AI services and authentication
├── appsettings.Development.json   # Local development settings (git-ignored)
├── appManifest/
│   └── manifest.json              # Teams/Copilot app manifest
├── MAF-M365-Copilot-Agent.csproj  # Project file with MAF and M365 SDK packages
├── LICENSE                         # MIT License
└── .gitignore                      # Git ignore rules
```

## Important Notes

> **Microsoft Agent Framework packages are in preview.** Use `--prerelease` flag when adding packages:
> ```bash
> dotnet add package Microsoft.Agents.AI.AzureAI --prerelease
> dotnet add package Microsoft.Agents.AI.OpenAI --prerelease
> ```

## Key Packages

This project uses the following NuGet packages (all preview versions where noted):

| Package | Purpose |
|---------|---------|
| `Microsoft.Agents.AI.OpenAI` | MAF integration with OpenAI/Azure OpenAI |
| `Microsoft.Agents.AI.AzureAI` | MAF integration with Azure AI services |
| `Azure.AI.OpenAI` | Azure OpenAI client for Foundry |
| `Microsoft.Agents.Hosting.AspNetCore` | M365 Agents SDK hosting |
| `Microsoft.Agents.Authentication.Msal` | Bot authentication |
| `Azure.Identity` | Azure credential management (DefaultAzureCredential) |

## Resources

- [Microsoft Agent Framework Documentation](https://github.com/microsoft/agent-framework)
- [M365 Agents SDK Documentation](https://learn.microsoft.com/en-us/microsoft-365/agents-sdk/)
- [Microsoft Foundry (Azure AI Foundry)](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Teams App Manifest Schema](https://learn.microsoft.com/en-us/microsoftteams/platform/resources/schema/manifest-schema)

## Testing this Agent in Teams or M365

1. Update the manifest.json
   - Edit the `manifest.json` contained in the `/appManifest` folder
     - Replace with your AppId (that was created above) *everywhere* you see the place holder string `<<AAD_APP_CLIENT_ID>>`
     - Replace `<<BOT_DOMAIN>>` with your Agent url.  For example, the tunnel host name.
   - Zip up the contents of the `/appManifest` folder to create a `manifest.zip`
     - `manifest.json`
     - `outline.png`
     - `color.png`

1. Your Azure Bot should have the **Microsoft Teams** channel added under **Channels**.

1. Navigate to the Microsoft Admin Portal (MAC). Under **Settings** and **Integrated Apps,** select **Upload Custom App**.

1. Select the `manifest.zip` created in the previous step. 

1. After a short period of time, the agent shows up in Microsoft Teams and Microsoft 365 Copilot.

## Enabling JWT token validation
1. By default, the AspNet token validation is disabled in order to support local debugging.
1. Enable by updating appsettings
   ```json
   "TokenValidation": {
     "Enabled": true,
     "Audiences": [
       "{{ClientId}}" // this is the Client ID used for the Azure Bot
     ],
     "TenantId": "{{TenantId}}"
   },
   ```

## Further reading
To learn more about building Agents, see [Microsoft 365 Agents SDK](https://learn.microsoft.com/en-us/microsoft-365/agents-sdk/).