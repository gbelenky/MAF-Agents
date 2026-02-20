# Fabric Data Agent Chat Client

A standalone Python client for interacting with published Microsoft Fabric Data Agents using Azure Identity authentication.

## Features

- **Standalone client** - Works outside Fabric notebooks (local machine, Azure Functions, etc.)
- **Azure Identity authentication** - Supports Azure CLI, service principal, managed identity
- **Interactive chat** - Conversational interface with conversation history
- **OpenAI Assistants API** - Uses the standard Assistants API pattern

## Installation

```bash
uv sync
```

## Prerequisites

1. **Microsoft Fabric** with:
   - Fabric Capacity F2+ (F64 recommended)
   - Copilot and AI skill enabled
   - A **published** Data Agent

2. **Authentication** (choose one):
   - **Azure CLI**: Run `az login` first (easiest)
   - **Service Principal**: Set `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`
   - **Managed Identity**: Automatic in Azure-hosted environments

## Quick Start

### 1. Configure Environment

Copy `.env.example` to `.env` and fill in your values:

```bash
FABRIC_WORKSPACE_ID=your-workspace-guid
FABRIC_AGENT_ITEM_ID=your-agent-item-guid
```

To find these IDs, open your Data Agent in Fabric portal and look at the URL:
```
https://app.fabric.microsoft.com/groups/{WORKSPACE_ID}/dataagents/{AGENT_ITEM_ID}
```

### 2. Login to Azure

```bash
az login
```

### 3. Run the Chat

```bash
uv run python main.py
```

## Usage

### Interactive Chat

```bash
uv run python main.py
```

Output:
```
==================================================
  Fabric Data Agent Chat
==================================================

Connecting...
Endpoint: https://api.fabric.microsoft.com/v1/workspaces/.../aiassistant/openai
Token acquired
Thread: thread_abc123
Ready!

Commands: quit, clear

You: How many holidays were in the US in 1993?

Agent: There were 11 public holidays in the United States in 1993.

You: quit
```

### Programmatic Usage

```python
from main import DataAgentClient

# Create client from environment
client = DataAgentClient.from_env()

# Or provide IDs directly
client = DataAgentClient(
    workspace_id="your-workspace-guid",
    agent_id="your-agent-guid"
)

# Create a conversation thread
client.create_thread()

# Query the agent
response = client.query("What are the top 5 products by sales?")
print(response)

# Clear the thread (start fresh conversation)
client.clear()
```

## API Reference

### DataAgentClient

| Method | Description |
|--------|-------------|
| `__init__(workspace_id, agent_id, verbose)` | Create client with workspace and agent IDs |
| `from_env(verbose)` | Create client from `.env` file |
| `create_thread()` | Create a conversation thread |
| `query(question, timeout)` | Send a query and get response |
| `clear()` | Delete thread and start fresh |

## How It Works

The client uses the **OpenAI Assistants API pattern** over Fabric's REST API:

```
+------------------+     +------------------------------------------+
|  DataAgentClient |     |  Microsoft Fabric                        |
|                  |---->|  /aiassistant/openai                     |
|                  |     |       |                                  |
|                  |<----|  Data Agent -> Lakehouse/SQL             |
+------------------+     +------------------------------------------+
```

### Query Flow

1. `POST /threads` - Create conversation thread
2. `POST /threads/{id}/messages` - Add user question
3. `POST /assistants` - Create assistant instance
4. `POST /threads/{id}/runs` - Start execution
5. `GET /threads/{id}/runs/{id}` - Poll until complete
6. `GET /threads/{id}/messages` - Get response

## Requirements

- Python 3.10+
- Published Fabric Data Agent
- Azure Identity credentials

## Dependencies

- `azure-identity` - Azure authentication
- `requests` - HTTP client
- `python-dotenv` - Environment variable loading
