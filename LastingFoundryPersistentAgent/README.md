# Lasting Foundry Persistent Agent (Python - Standard Agents)

An Azure Developer CLI (azd) project that creates and manages **Azure AI Foundry Standard Agents** with Vector Store capability for document Q&A (RAG pattern).

## Key Features

- **Standard Agents** - Uses the new Foundry API (not classic agents)
- **Vector Store** - Automatic file search capability for RAG
- **azd Integration** - Full lifecycle management via `azd provision` and `azd down`
- **Python SDK** - Uses `azure-ai-projects` SDK for Standard Agent creation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure AI Foundry                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Foundry Project                         │   │
│  │  ┌─────────────────┐    ┌──────────────────────┐   │   │
│  │  │ Standard Agent  │───▶│    Vector Store      │   │   │
│  │  │ (file_search)   │    │  (product_manual.md) │   │   │
│  │  └─────────────────┘    └──────────────────────┘   │   │
│  │                                                      │   │
│  │  ┌─────────────────┐                                │   │
│  │  │   gpt-4.1-mini  │                                │   │
│  │  │   deployment    │                                │   │
│  │  └─────────────────┘                                │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
- [Python 3.10+](https://www.python.org/downloads/)
- Azure subscription with AI Services access
- Azure CLI logged in (`az login`)

## Quick Start

### 1. Deploy Everything

```bash
# Provision infrastructure AND create the Standard Agent
azd provision
```

This command:
1. Creates Azure AI Services with Foundry Project
2. Deploys the gpt-4.1-mini model
3. Creates a Python virtual environment
4. Uploads the sample document
5. Creates a Vector Store
6. Creates the Standard Agent with file_search tool
7. Saves resource IDs to azd environment

### 2. View Created Resources

```bash
# Check azd environment for resource IDs
azd env get-values

# Or run the list command
cd src
.\.venv\Scripts\Activate.ps1  # Windows
# source .venv/bin/activate   # Linux/Mac
python agent_manager.py list
```

### 3. Tear Down Everything

```bash
# Delete agent, vector store, file, then Azure resources
azd down --force --purge
```

## Project Structure

```
LastingFoundryPersistentAgent/
├── azure.yaml              # azd configuration with hooks
├── infra/
│   ├── main.bicep          # Main infrastructure
│   ├── main.parameters.json
│   └── app/
│       ├── ai/
│       │   └── cognitive-services.bicep  # AI Services + Foundry Project
│       ├── rbac/
│       │   └── openai-access.bicep       # Role assignments
│       └── util/
│           └── region-selector.bicep     # Model availability
├── src/
│   ├── agent_manager.py    # Python agent lifecycle manager
│   ├── pyproject.toml      # Python dependencies (uv)
│   └── docs/
│       └── product_manual.md  # Sample document for RAG
└── README.md
```

## Manual Commands

If you need to manage the agent manually:

```bash
cd src

# Install dependencies with uv
uv sync

# Set environment variables
export PROJECT_ENDPOINT="https://your-project.services.ai.azure.com/api/projects/your-project"
export CHAT_MODEL_DEPLOYMENT="gpt-4.1-mini"

# Create agent with vector store
uv run python agent_manager.py create

# Chat with the agent
export AGENT_ID="LastingDocumentAgent:1"  # From create output
uv run python agent_manager.py chat

# Delete agent and resources
export VECTORSTORE_ID="..."  # From create output
export FILE_ID="..."         # From create output
uv run python agent_manager.py delete

# Help
uv run python agent_manager.py --help
```

## Standard vs Classic Agents

| Feature | Classic Agents | Standard Agents |
|---------|---------------|-----------------|
| API | Assistants API | Foundry projects API |
| Portal Location | Under "Classic" | Main agents section |
| SDK (Python) | `azure-ai-agents-persistent` | `azure-ai-projects` |
| SDK (.NET) | ✅ Available | ❌ Not yet |
| Vector Store | ✅ Yes | ✅ Yes |
| File Search | ✅ Yes | ✅ Yes |
| Code Interpreter | ✅ Yes | ✅ Yes |

## Environment Variables

After `azd provision`, these are set automatically:

| Variable | Description |
|----------|-------------|
| `PROJECT_ENDPOINT` | AI Foundry project endpoint |
| `CHAT_MODEL_DEPLOYMENT` | Model deployment name |
| `AGENT_ID` | Created agent ID |
| `VECTORSTORE_ID` | Created vector store ID |
| `FILE_ID` | Uploaded file ID |

## Customization

### Change the Document

Replace `src/docs/product_manual.md` with your own document before running `azd provision`.

### Change Agent Name/Instructions

Set environment variables before provisioning:

```bash
azd env set AGENT_NAME "MyCustomAgent"
azd env set AGENT_INSTRUCTIONS "You are a specialist in..."
azd provision
```

### Change the Model

Edit `infra/main.bicep`:

```bicep
@allowed(['gpt-4o-mini', 'gpt-4.1-mini', 'gpt-4o'])
param chatModelName string = 'gpt-4o'  // Change default
```

## Troubleshooting

### "Model not available in region"

Some models aren't available in all regions. The project includes region selection logic. Check `infra/app/util/region-selector.bicep` for supported regions.

### "Authentication failed"

Ensure you're logged in:
```bash
az login
azd auth login
```

### "Agent created but appears under Classic"

This version uses the Python SDK with the new Foundry API - agents should appear in the main agents section, not under "Classic". If they still appear under Classic, ensure you're using `azure-ai-projects>=1.0.0b10`.

## License

MIT
