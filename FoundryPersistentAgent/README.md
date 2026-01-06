# MAF + Foundry Persistent Agent Hybrid

A .NET console application demonstrating the **hybrid pattern**: using **Microsoft.Extensions.AI** (MAF's `IChatClient` abstraction) to orchestrate calls to **Azure AI Foundry Persistent Agents** with built-in **File Search**.

## What This Sample Demonstrates

| Feature | Description |
|---------|-------------|
| **IChatClient Wrapper** | MAF abstraction over Foundry persistent agents |
| **PersistentAgentsClient** | Server-side hosted agents in Azure AI Foundry |
| **File Upload** | Upload documents to Foundry for agent access |
| **Vector Store** | Create and manage vector stores for document indexing |
| **File Search Tool** | Built-in RAG without external Azure AI Search |
| **Multi-turn Conversation** | Persistent threads with conversation history |
| **Citation Handling** | Parse and display document citations |

> **Note:** The agent created by this sample uses the `Azure.AI.Agents.Persistent` SDK (Assistants API pattern), so it appears under **"Classic Agents"** in the [Azure AI Foundry portal](https://ai.azure.com), not in the newer "Standard Agents" section. Classic Agents use the thread → message → run workflow, while Standard Agents use the newer visual builder experience.

## Why the Hybrid Pattern?

### The Challenge

We want to use **Microsoft Agent Framework (MAF)** for its orchestration benefits, but MAF doesn't expose Foundry's native infrastructure APIs:

| Capability | Azure.AI.Agents.Persistent | Microsoft.Agents.AI (MAF) |
|------------|---------------------------|---------------------------|
| File Upload API | ✅ Built-in | ❌ Not available |
| Vector Store Management | ✅ Built-in | ❌ Not available |
| Built-in File Search Tool | ✅ Native Foundry tool | ❌ Requires custom implementation |
| Server-side Agent Hosting | ✅ Foundry-managed | ❌ Local orchestration only |
| IChatClient Abstraction | ❌ Not provided | ✅ Core feature |
| Middleware Pipeline | ❌ Not provided | ✅ Core feature |

### The Solution: Hybrid Pattern

Wrap `PersistentAgentsClient` in an `IChatClient` implementation to get **both**:

```
┌─────────────────────────────────────────┐
│         Your Application Code           │
│    (uses IChatClient abstraction)       │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│     FoundryPersistentChatClient         │
│   (implements IChatClient, wraps        │
│    PersistentAgentsClient calls)        │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│     Azure AI Foundry (Server-side)      │
│  • Persistent Agent with File Search    │
│  • Vector Store + Document Storage      │
│  • Thread/Conversation Management       │
└─────────────────────────────────────────┘
```

### Pattern Options Considered

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| **1. IChatClient Wrapper** ✅ | Wrap Foundry agent in IChatClient | Full Foundry features, clean abstraction, path to multi-agent | Medium complexity |
| **2. MAF Tool** | Foundry as a tool in MAF agent | Simpler | Limited to search, loses thread management |
| **3. Full Integration** | Both frameworks managing state | Maximum flexibility | High complexity, state sync issues |

**We chose Option 1** because it:
- Preserves all Foundry capabilities (file upload, vector stores, citations)
- Provides MAF benefits (middleware, logging, future multi-agent)
- Keeps Foundry managing conversation state (no duplication)
- Creates a clean path to add more agents later

## Architecture: Local vs Persistent Agents

| Aspect | Local Agent (QuickStart) | Persistent Agent (This Sample) |
|--------|--------------------------|-------------------------------|
| **Client** | `AzureOpenAIClient` | `PersistentAgentsClient` via `IChatClient` |
| **Agent Lifecycle** | In-memory only | Server-side hosted |
| **Built-in Tools** | None | File Search, Code Interpreter, Bing, etc. |
| **File Storage** | N/A | Foundry file storage |
| **Vector Stores** | N/A | Built-in vector store management |
| **Thread Persistence** | Manual | Automatic server-side |
| **Use Case** | Simple chat, custom tools | Document Q&A, code execution, RAG |

## Prerequisites

- [.NET 9.0 SDK](https://dotnet.microsoft.com/download/dotnet/9.0)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) (for authentication)
- **Azure AI Foundry Project** (created May 2025 or later)
- Model deployment with chat completion capability (e.g., `gpt-4.1-mini`)

## Project Endpoint

Your Foundry project endpoint follows this format:
```
https://<AIFoundryResourceName>.services.ai.azure.com/api/projects/<ProjectName>
```

Find it in [Azure AI Foundry portal](https://ai.azure.com) → Your Project → **Overview** → **Libraries** → **Foundry**.

## Setup

### 1. Clone and Navigate
```bash
cd MAF-Agents/FoundryPersistentAgent
```

### 2. Restore Packages
```bash
dotnet restore
```

### 3. Configure Settings

Create `appsettings.Development.json` (git-ignored):
```json
{
  "Foundry-Project": {
    "Endpoint": "https://your-resource.services.ai.azure.com/api/projects/your-project",
    "ModelDeployment": "gpt-4.1-mini"
  }
}
```

### 4. Authenticate
```bash
az login
```

### 5. Run
```bash
dotnet run
```

## Sample Output

```
=== Foundry Persistent Agent with File Search ===

Step 1: Uploading document to Foundry...
  Uploaded: product_manual.md (ID: file-abc123)

Step 2: Creating Vector Store...
  Vector Store created: ProductDocumentation (ID: vs-xyz789)
  File added to Vector Store (Status: InProgress)
  Processing.... Done (Completed)

Step 3: Creating Agent with File Search tool...
  Agent created: Product Documentation Assistant (ID: agent-def456)

Step 4: Creating MAF-wrapped Foundry client...
  Thread created (ID: thread-ghi789)
  IChatClient wrapper ready

Step 5: Running conversation via MAF IChatClient...

User: What is the SmartWidget Pro and what are its key features?
Assistant: The SmartWidget Pro is an advanced IoT device designed for smart home automation. 
Key features include:
- WiFi Connectivity (2.4GHz and 5GHz dual-band)
- Voice Control (Alexa, Google Assistant, Siri)
- Energy Monitoring
- Mobile App for iOS and Android [product_manual.md]
  [Tokens: 1250 in, 85 out]

User: How do I connect the device to WiFi?
Assistant: To connect to WiFi:
1. Open the SmartWidget app
2. Tap "Add Device" → "SmartWidget Pro"
3. Ensure your phone is on the 2.4GHz network
4. Enter your WiFi password
5. Wait for solid green LED (connected) [product_manual.md]
  [Tokens: 1480 in, 72 out]
```

## Code Walkthrough

### 1. Create Foundry Client (Infrastructure)
```csharp
PersistentAgentsClient foundryClient = new(projectEndpoint, new DefaultAzureCredential());
```

### 2. Upload File to Foundry
```csharp
PersistentAgentFileInfo uploadedFile = foundryClient.Files.UploadFile(
    filePath: "docs/product_manual.md",
    purpose: PersistentAgentFilePurpose.Agents);
```

### 3. Create Vector Store
```csharp
PersistentAgentsVectorStore vectorStore = foundryClient.VectorStores.CreateVectorStore(
    name: "ProductDocumentation");

foundryClient.VectorStores.CreateVectorStoreFile(
    vectorStoreId: vectorStore.Id,
    fileId: uploadedFile.Id);
```

### 4. Create Agent with File Search
```csharp
FileSearchToolResource fileSearchResource = new();
fileSearchResource.VectorStoreIds.Add(vectorStore.Id);

PersistentAgent agent = foundryClient.Administration.CreateAgent(
    model: modelDeploymentName,
    name: "Documentation Assistant",
    instructions: "You help users find information in product docs...",
    tools: [new FileSearchToolDefinition()],
    toolResources: new ToolResources { FileSearch = fileSearchResource });
```

### 5. Wrap with MAF IChatClient
```csharp
PersistentAgentThread thread = foundryClient.Threads.CreateThread();

// Create MAF abstraction over Foundry
IChatClient chatClient = new FoundryPersistentChatClient(
    client: foundryClient,
    agentId: agent.Id,
    threadId: thread.Id,
    fileIds: fileIds);
```

### 6. Use MAF Patterns for Conversation
```csharp
var messages = new List<ChatMessage>
{
    new(ChatRole.User, "What are the key features?")
};

// Call through MAF IChatClient abstraction
var response = await chatClient.GetResponseAsync(messages);
var text = response.Messages.FirstOrDefault()?.Text;
Console.WriteLine(text);
```

## The FoundryPersistentChatClient

The key to the hybrid pattern is [FoundryPersistentChatClient.cs](FoundryPersistentChatClient.cs), which:

1. **Implements `IChatClient`** - MAF's core abstraction for chat completions
2. **Wraps `PersistentAgentsClient`** - Delegates all calls to Foundry
3. **Handles Foundry specifics** - Run polling, citation formatting, usage tracking
4. **Exposes underlying client** - Via `GetService<PersistentAgentsClient>()` for advanced scenarios

```csharp
public class FoundryPersistentChatClient : IChatClient
{
    private readonly PersistentAgentsClient _client;
    
    public async Task<ChatResponse> GetResponseAsync(IEnumerable<ChatMessage> chatMessages, ...)
    {
        // 1. Send message to Foundry thread
        // 2. Create and poll run until complete
        // 3. Extract response with citations
        // 4. Return as ChatResponse
    }
}
```

## Other Foundry Tools

The same pattern works for other built-in tools:

| Tool | Definition | Use Case |
|------|------------|----------|
| **File Search** | `FileSearchToolDefinition` | Document Q&A, RAG |
| **Code Interpreter** | `CodeInterpreterToolDefinition` | Python execution, charts |
| **Bing Search** | `BingGroundingToolDefinition` | Web search grounding |
| **Azure AI Search** | `AzureAISearchToolDefinition` | Enterprise search index |

## Packages Used

| Package | Purpose |
|---------|---------|
| `Azure.AI.Agents.Persistent` | Foundry Agent Service SDK (infrastructure) |
| `Microsoft.Extensions.AI` | MAF IChatClient abstraction |
| `Azure.Identity` | Azure authentication |
| `Microsoft.Extensions.Configuration.Json` | Configuration management |

## SDK Decision: Why Both?

This sample uses **both** SDKs in a hybrid pattern:

| Layer | SDK | Purpose |
|-------|-----|---------|
| **Abstraction** | `Microsoft.Extensions.AI` | IChatClient interface for orchestration |
| **Infrastructure** | `Azure.AI.Agents.Persistent` | Foundry file storage, vector stores, tools |

### SDK Capabilities Comparison

| Capability | Azure.AI.Agents.Persistent | Microsoft.Extensions.AI |
|------------|---------------------------|-------------------------|
| File Upload API | ✅ Built-in | ❌ Not available |
| Vector Store Management | ✅ Built-in | ❌ Not available |
| Built-in File Search Tool | ✅ Native Foundry tool | ❌ Not available |
| Server-side Agent Hosting | ✅ Foundry-managed | ❌ Not available |
| IChatClient Abstraction | ❌ Not provided | ✅ Core feature |
| Middleware Pipeline | ❌ Not provided | ✅ Core feature |
| Multi-agent Orchestration | ❌ Not provided | ✅ Supported |

### When to Use Each Pattern

| Scenario | Recommended Approach |
|----------|---------------------|
| Simple Foundry agent, no orchestration | `Azure.AI.Agents.Persistent` only |
| Need middleware (logging, caching, rate limiting) | Hybrid (this sample) |
| Multi-agent with Foundry capabilities | Hybrid (this sample) |
| Pure orchestration, no Foundry features | `Microsoft.Extensions.AI` only |
| Custom tool implementations | `Microsoft.Agents.AI` |
| Combining both (hosted agents + orchestration) | Both together |

## Related Resources

- [Azure AI Agent Service Documentation](https://learn.microsoft.com/azure/ai-foundry/agents/)
- [File Search Tool Guide](https://learn.microsoft.com/azure/ai-foundry/agents/how-to/tools/file-search)
- [Azure.AI.Agents.Persistent API Reference](https://learn.microsoft.com/dotnet/api/azure.ai.agents.persistent)
- [Microsoft Agent Framework](https://github.com/microsoft/agents)
