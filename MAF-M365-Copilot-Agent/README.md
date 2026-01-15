# MAF Durable Agent on Azure Functions

This project runs a **Microsoft Agent Framework (MAF) Durable Agent** on **Azure Functions** with durable execution, state persistence, and **Agents Playground** compatibility.

## Features

- 🤖 **MAF Durable Agent** - Stateful agent with durable orchestration
- 🛠️ **Function Tools** - Weather and time tools demonstrating function calling
- ⚡ **Azure Functions** - Serverless hosting with `func start`
- 💾 **Durable Task Scheduler (DTS)** - Persistent conversation state via Azure-managed backend
- ☁️ **Azure OpenAI** - GPT model integration via Azure AI Foundry
- 🎮 **Agents Playground** - Bot Framework `/api/messages` endpoint for testing

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│           Agents Playground / Bot Framework Client          │
│                 (connects to /api/messages)                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Azure Functions Host                     │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                     MAFAdapter                        │  │
│  │  - POST /api/messages (Bot Framework protocol)        │  │
│  │  - Injects IChatClient + AIFunction[] tools           │  │
│  │  - Calls Azure OpenAI directly (no HTTP loopback)     │  │
│  │  - Proactive messaging to serviceUrl                  │  │
│  └───────────────────────────────────────────────────────┘  │
│                              │                              │
│                              ▼                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         Microsoft.Extensions.AI (IChatClient)         │  │
│  │  - Function invocation pipeline                       │  │
│  │  - AIFunction tools (GetWeather, GetCurrentTime)      │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
          │                                    │
          ▼                                    ▼
┌──────────────────────────────┐  ┌────────────────────────────┐
│      Azure OpenAI            │  │  Durable Task Scheduler    │
│  (Model inference via SDK)   │  │  (State persistence)       │
│  Uses DefaultAzureCredential │  │  Dashboard: localhost:8082 │
└──────────────────────────────┘  └────────────────────────────┘
```

## Prerequisites

- [.NET 8.0 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/8.0)
- [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local) (`winget install Microsoft.Azure.FunctionsCoreTools`)
- [Azurite](https://learn.microsoft.com/azure/storage/common/storage-use-azurite) for local storage emulation
- [Durable Task Scheduler Emulator](https://github.com/microsoft/durabletask-azuremanaged) for local durable task
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) authenticated (`az login`)
- [Agents Playground VS Code Extension](https://marketplace.visualstudio.com/items?itemName=TeamsDevApp.vscode-agents-playground) (optional, for testing)

## Configuration

Edit `local.settings.json`:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "DURABLE_TASK_SCHEDULER_CONNECTION_STRING": "Endpoint=http://localhost:8080;TaskHub=default;Authentication=None",
    "AZURE_OPENAI_ENDPOINT": "https://your-resource.openai.azure.com/",
    "AZURE_OPENAI_DEPLOYMENT": "gpt-4o-mini",
    "TASKHUB_NAME": "default"
  },
  "Host": {
    "LocalHttpPort": 3978
  }
}
```

## QuickStart

1. **Login to Azure** (for Azure OpenAI access):
   ```bash
   az login
   ```

2. **Start Azurite** (storage emulator):
   ```bash
   azurite --silent
   ```

3. **Start Durable Task Scheduler Emulator** (with dashboard):
   ```bash
   docker run -d -p 8080:8080 -p 8081:8081 -p 8082:8082 mcr.microsoft.com/dts/dts-emulator:latest
   ```
   - Port 8080: gRPC endpoint
   - Port 8082: Dashboard at http://localhost:8082

4. **Start the Function App**:
   ```bash
   func start
   ```

5. **Test with Agents Playground**:
   - Open VS Code Agents Playground extension
   - Connect to `http://localhost:3978/api/messages`
   - Send messages like "What's the weather in Seattle?"

6. **Or test with curl**:
   ```bash
   curl -X POST http://localhost:3978/api/messages \
     -H "Content-Type: application/json" \
     -d '{"type":"message","text":"What is the weather in Seattle?","from":{"id":"user1"},"conversation":{"id":"conv1"},"serviceUrl":"http://localhost:3978"}'
   ```

## API Endpoint

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/messages` | Bot Framework / Agents Playground endpoint |

## Project Structure

```
MAF-M365-Copilot-Agent/
├── Program.cs                      # Entry point, IChatClient + DI configuration
├── WeatherAgent.cs                 # Agent tools defined with [Description] decorators
├── MAFAdapter.cs                   # Bot Framework adapter (direct IChatClient invocation)
├── host.json                       # Azure Functions host + DTS configuration
├── local.settings.json             # Local development settings (gitignored)
├── MAF-M365-Copilot-Agent.csproj   # Project file with NuGet dependencies
├── .vscode/
│   ├── launch.json                 # F5 debug configuration
│   └── tasks.json                  # Build and func start tasks
└── test.http                       # HTTP test requests
```

## Key Packages

| Package | Purpose |
|---------|---------|
| `Microsoft.Agents.AI.Hosting.AzureFunctions` | MAF Durable Agent hosting |
| `Microsoft.Agents.AI.OpenAI` | OpenAI/Azure OpenAI integration |
| `Microsoft.Azure.Functions.Worker` | Azure Functions runtime |
| `Azure.AI.OpenAI` | Azure OpenAI client |
| `Azure.Identity` | DefaultAzureCredential for auth |
| `Microsoft.Extensions.AI` | IChatClient abstraction + function invocation |

## MAFAdapter

The `MAFAdapter` class ([MAFAdapter.cs](MAFAdapter.cs)) bridges the **Bot Framework protocol** to **Azure OpenAI** via direct `IChatClient` invocation:

### How It Works

1. **Receives** Bot Framework activities at `/api/messages`
2. **Extracts** the user message from the activity
3. **Invokes** Azure OpenAI directly via injected `IChatClient` with:
   - System instructions for agent behavior
   - AIFunction tools for function calling (weather, time)
   - Function invocation pipeline for automatic tool execution
4. **Sends** the AI response back via **proactive messaging** to the `serviceUrl`

### Key Features

- **No HTTP Loopback**: Calls `IChatClient.GetResponseAsync()` directly instead of HTTP round-trip
- **Tool Execution**: Uses `UseFunctionInvocation()` pipeline for automatic tool calling
- **Proactive Messaging**: Replies via Bot Framework's `/v3/conversations/{id}/activities` endpoint
- **Agents Playground Compatible**: Works with the VS Code Agents Playground extension

### Injected Dependencies

```csharp
public MAFAdapter(
    IChatClient chatClient,           // Azure OpenAI via M.E.AI
    AIFunction[] tools,               // GetWeather, GetCurrentTime
    [FromKeyedServices("SystemInstructions")] string systemInstructions
)
```

## Adding Tools

Tools are defined as **decorated methods** on the `WeatherAgent` class in [WeatherAgent.cs](WeatherAgent.cs):

```csharp
public class WeatherAgent
{
    public const string Instructions = "You are a helpful AI assistant...";

    [Description("Gets the current weather for a location.")]
    public static string GetWeather(
        [Description("The city name, e.g. 'Seattle', 'New York'")] string location) 
        => location.ToLowerInvariant() switch
    {
        "seattle" => "🌧️ Seattle: 52°F, Rainy",
        "new york" => "☀️ New York: 68°F, Sunny",
        _ => $"🌡️ {location}: 65°F, Typical weather"
    };

    [Description("Gets the current date and time.")]
    public static string GetCurrentTime() 
        => $"🕐 Current time: {DateTime.Now:f}";

    // Returns all tools for registration
    public static AIFunction[] GetTools() =>
    [
        AIFunctionFactory.Create(GetWeather),
        AIFunctionFactory.Create(GetCurrentTime)
    ];
}
```

### Available Decorators

| Attribute | Applies To | Purpose |
|-----------|------------|---------|
| `[Description("...")]` | Method | Describes the tool's purpose for the AI model |
| `[Description("...")]` | Parameter | Describes what the parameter expects |

### Adding a New Tool

1. Add a new static method to `WeatherAgent.cs`:
   ```csharp
   [Description("Searches for information on a topic.")]
   public static string Search(
       [Description("The search query")] string query) 
       => $"Results for: {query}";
   ```

2. Register it in `GetTools()`:
   ```csharp
   public static AIFunction[] GetTools() =>
   [
       AIFunctionFactory.Create(GetWeather),
       AIFunctionFactory.Create(GetCurrentTime),
       AIFunctionFactory.Create(Search)  // Add here
   ];
   ```

## Deployment to Azure

Use Azure Developer CLI:

```bash
azd init
azd up
```

Or deploy via Azure Functions:

```bash
func azure functionapp publish <function-app-name>
```
