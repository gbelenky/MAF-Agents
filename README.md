# MAF-Agents

A collection of sample projects demonstrating the **Microsoft Agent Framework (MAF)** for building AI agents on Azure.

## Projects

| Project | Description |
|---------|-------------|
| [AgentFrameworkQuickStart](./AgentFrameworkQuickStart/) | A minimal .NET console app showing how to create a local AI agent with tool calling using Azure OpenAI models from Azure AI Foundry |
| [FoundryPersistentAgent](./FoundryPersistentAgent/) | Demonstrates Azure AI Agent Service with persistent agents, file upload, vector stores, and the built-in File Search tool |

## Prerequisites

- [.NET 9.0 SDK](https://dotnet.microsoft.com/download/dotnet/9.0) or later
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) (for authentication)
- Access to [Azure AI Foundry](https://ai.azure.com/) with deployed models

## Getting Started

Each project folder contains its own `README.md` with specific setup instructions. Navigate to the project you're interested in to get started.

### Quick Start

```bash
# Clone the repository
git clone <your-repo-url>
cd MAF-Agents

# Navigate to a project
cd AgentFrameworkQuickStart

# Follow the project-specific README
```

## Project Structure

```
MAF-Agents/
├── README.md                      # This file
├── LICENSE                        # MIT License
├── .gitignore                     # Git ignore rules
├── AgentFrameworkQuickStart/      # Quick start sample (local agent)
│   ├── README.md                  # Project documentation
│   ├── Program.cs                 # Main application code
│   ├── appsettings.json           # Base configuration
│   └── appsettings.Development.json # Dev config (git-ignored)
└── FoundryPersistentAgent/        # Persistent agent with File Search
    ├── README.md                  # Project documentation
    ├── Program.cs                 # Main application code
    ├── appsettings.json           # Base configuration
    ├── appsettings.Development.json # Dev config (git-ignored)
    └── docs/                      # Sample documents for File Search
```

## Related Resources

- [Microsoft Agent Framework Documentation](https://github.com/microsoft/agents)
- [Azure AI Foundry](https://ai.azure.com/)
- [Azure OpenAI Service](https://learn.microsoft.com/azure/ai-services/openai/)
- [Microsoft.Extensions.AI](https://learn.microsoft.com/dotnet/ai/ai-extensions)

## License

MIT
