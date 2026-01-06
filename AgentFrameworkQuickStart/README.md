# Microsoft Agent Framework Quick Start with Foundry Models

A simple example demonstrating how to use the Microsoft Agent Framework with models deployed in Microsoft Foundry (formerly Azure AI Foundry).

## Prerequisites

- [.NET 9.0 SDK](https://dotnet.microsoft.com/download/dotnet/9.0) or later
- A Microsoft Foundry project with a deployed model
- Azure CLI authenticated (`az login`)

## Setup

### 1. Clone and restore packages

```bash
dotnet restore
```

### 2. Configure your endpoint

Create an `appsettings.Development.json` file (this file is git-ignored):

```json
{
  "Foundry-Resource": {
    "Endpoint": "https://your-foundry-resource.services.ai.azure.com"
  }
}
```

### 3. Update the model name

In `Program.cs`, update the model deployment name to match your Foundry deployment:

```csharp
.GetChatClient("your-model-deployment-name")
```

## Running the Application

```bash
dotnet run
```

Or press **F5** in VS Code to debug.

## Project Structure

```
AgentFrameworkQuickStart/
├── Program.cs                      # Main application code
├── appsettings.json                # Base configuration (committed)
├── appsettings.Development.json    # Development settings with endpoint (git-ignored)
├── AgentFrameworkQuickStart.csproj # Project file with dependencies
└── .vscode/
    ├── launch.json                 # Debug configuration
    └── tasks.json                  # Build tasks
```

## Code Overview

```csharp
using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Configuration;

// Load configuration from appsettings files
var configuration = new ConfigurationBuilder()
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", optional: false)
    .AddJsonFile("appsettings.Development.json", optional: true)
    .Build();

var endpoint = configuration["Foundry-Resource:Endpoint"] 
    ?? throw new InvalidOperationException("Foundry-Resource:Endpoint is not configured.");

// Create an AI Agent using AzureOpenAIClient
AIAgent agent = new AzureOpenAIClient(
    new Uri(endpoint),
    new DefaultAzureCredential())
    .GetChatClient("your-model-deployment")
    .AsIChatClient()
    .CreateAIAgent(instructions: "You are a helpful assistant.");

// Run the agent
Console.WriteLine(await agent.RunAsync("Hello!"));
```

## Key Concepts

### SDK Architecture

This project uses two layers of SDKs that work together:

**Azure/Foundry SDKs (base clients):**

| Package | Type | Purpose |
|---------|------|---------|
| `Azure.AI.OpenAI` | Azure SDK | Connect to Azure OpenAI / Foundry endpoints |
| `Azure.AI.Projects` | Azure SDK | Foundry project operations |
| `Azure.AI.Agents.Persistent` | Azure SDK | Assistants-style persistent agents |

**Microsoft Agent Framework (MAF) SDKs (extensions):**

| Package | Purpose |
|---------|---------|
| `Microsoft.Agents.AI` | Core MAF abstractions (`AIAgent`, etc.) |
| `Microsoft.Agents.AI.OpenAI` | Extensions for `AzureOpenAIClient`/`ChatClient` → `AIAgent` |
| `Microsoft.Agents.AI.AzureAI` | Extensions for `AIProjectClient` → `AIAgent` |
| `Microsoft.Agents.AI.AzureAI.Persistent` | Extensions for `PersistentAgentsClient` → `AIAgent` |

**How they work together:**

```
Azure SDK (client)       +  MAF Extension                    =  AIAgent
──────────────────────────────────────────────────────────────────────────
AzureOpenAIClient        +  .AsIChatClient().CreateAIAgent() → AIAgent
AIProjectClient          +  .CreateAIAgentAsync()            → AIAgent
PersistentAgentsClient   +  .GetAIAgentAsync()               → AIAgent
```

MAF provides a **unified `AIAgent` abstraction** that wraps the different Azure SDK clients, giving you a consistent API regardless of which underlying client you use.

### Authentication

Uses `DefaultAzureCredential` which supports:
- Azure CLI (`az login`)
- Visual Studio / VS Code authentication
- Managed Identity (for deployed apps)
- Environment variables

### Agent Creation Flow

1. **AzureOpenAIClient** - Connects to your Foundry/Azure OpenAI endpoint
2. **GetChatClient** - Gets a chat client for a specific model deployment
3. **AsIChatClient** - Converts to the `IChatClient` interface
4. **CreateAIAgent** - Creates an AI agent with instructions

## Adding Custom Tools

You can extend the agent with custom tools (function calling):

```csharp
using System.ComponentModel;
using Microsoft.Extensions.AI;

// Add tools when creating the agent
AIAgent agent = new AzureOpenAIClient(...)
    .GetChatClient("your-model")
    .AsIChatClient()
    .CreateAIAgent(
        instructions: "You are a helpful assistant.",
        tools: [AIFunctionFactory.Create(GetWeather)]);

// Define your tool function
[Description("Get the weather for a location")]
static string GetWeather([Description("The location")] string location)
{
    return $"The weather in {location} is sunny, 22°C.";
}
```

## Alternative: Using AIProjectClient (Persistent Agents)

For creating persistent agents in Foundry (server-side agents):

```bash
dotnet add package Azure.AI.Projects --prerelease
dotnet add package Microsoft.Agents.AI.AzureAI --prerelease
```

```csharp
using Azure.AI.Projects;

var projectClient = new AIProjectClient(
    new Uri("https://your-resource.services.ai.azure.com/api/projects/your-project"),
    new DefaultAzureCredential());

AIAgent agent = await projectClient.CreateAIAgentAsync(
    name: "MyAgent",
    model: "gpt-4o-mini",
    instructions: "You are a helpful assistant.");
```

## Local Agent vs Persistent Agent

| Aspect | Local Agent (this project) | Persistent Agent |
|--------|---------------------------|------------------|
| **Client** | `AzureOpenAIClient` | `AIProjectClient` |
| **Lifetime** | In-memory, exists only during app execution | Server-side, persists in Foundry |
| **Visibility** | Not visible in Foundry portal | Visible and manageable in Foundry portal |
| **State** | No server-side state | Maintains state across sessions |
| **Threads** | Managed locally | Server-managed conversation threads |
| **Use case** | Quick prototyping, stateless apps | Production apps, multi-session conversations |
| **Packages** | `Microsoft.Agents.AI.OpenAI` | `Azure.AI.Projects` + `Microsoft.Agents.AI.AzureAI` |

### When to use Local Agent (AzureOpenAIClient)
- Simple, stateless applications
- Quick prototyping and testing
- Single-session conversations
- When you don't need Foundry agent management features
- Lower complexity, fewer dependencies

### When to use Persistent Agent (AIProjectClient)
- Production applications requiring durability
- Multi-session conversations with memory
- When you need to manage agents via Foundry portal
- Team collaboration on agent definitions
- Built-in conversation thread management
- Server-side tool and file storage

## NuGet Packages Used

| Package | Purpose |
|---------|---------|
| `Azure.AI.OpenAI` | Azure OpenAI client |
| `Azure.Identity` | Azure authentication |
| `Microsoft.Agents.AI.OpenAI` | Agent Framework OpenAI extensions |
| `Microsoft.Extensions.Configuration.Json` | Configuration loading |

> **Note:** The `--prerelease` flag is required when adding Agent Framework packages as they are currently in preview.

## Resources

- [Microsoft Agent Framework GitHub](https://github.com/microsoft/agent-framework)
- [Microsoft Foundry Documentation](https://learn.microsoft.com/azure/ai-foundry/)
- [Azure OpenAI Documentation](https://learn.microsoft.com/azure/ai-services/openai/)

## License

This project is for demonstration purposes.
