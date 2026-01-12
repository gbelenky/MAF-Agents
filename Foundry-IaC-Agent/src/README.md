# Foundry-IaC-Agent

Azure AI Foundry Standard Agent with Vector Store managed via azd lifecycle.

## Features

- Creates Standard Agents (not Classic) using the new Foundry API
- Vector Store with File Search capability
- Automatic lifecycle management via azd hooks

## Usage

```bash
# Create agent with vector store
uv run python agent_manager.py create

# Chat with the agent
uv run python agent_manager.py chat

# Delete agent and resources
uv run python agent_manager.py delete
```
