#!/usr/bin/env python3
"""
Standard Agent Manager for OneDrive Agent.

Creates a Standard Agent (visible in Foundry portal) with function tools
for OneDrive/SharePoint access. The .NET MAF app will instantiate this
agent and handle the actual function execution with OBO token flow.

Uses the Azure AI Projects SDK v2.x with create_version for Standard Agents.
"""

import os
import sys

from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    PromptAgentDefinition,
    FunctionTool,
)


def get_env_or_fail(name: str) -> str:
    """Get environment variable or exit with error."""
    value = os.environ.get(name)
    if not value:
        print(f"Error: {name} environment variable not set")
        sys.exit(1)
    return value


def get_project_client() -> AIProjectClient:
    """Create and return an AIProjectClient using DefaultAzureCredential."""
    endpoint = get_env_or_fail("PROJECT_ENDPOINT")
    credential = DefaultAzureCredential()
    return AIProjectClient(endpoint=endpoint, credential=credential)


def get_function_tools():
    """Define the function tools that will be executed by the .NET MAF app."""
    return [
        FunctionTool(
            name="list_files",
            description="List files in the user's OneDrive. Can optionally filter by folder path.",
            parameters={
                "type": "object",
                "properties": {
                    "folder_path": {
                        "type": "string",
                        "description": "Optional folder path to list files from. Use '/' for root, or specify a path like 'Documents' or 'Documents/Projects'. If not provided, lists files in the root folder."
                    },
                    "include_subfolders": {
                        "type": "boolean",
                        "description": "Whether to include files from subfolders. Default is false."
                    }
                },
                "required": []
            },
            strict=False
        ),
        FunctionTool(
            name="get_drive_info",
            description="Get information about the user's OneDrive, including total storage, used storage, and remaining storage.",
            parameters={
                "type": "object",
                "properties": {},
                "required": []
            },
            strict=False
        ),
        FunctionTool(
            name="search_files",
            description="Search for files in the user's OneDrive by name or content.",
            parameters={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "The search query to find files. Can search by filename or content."
                    }
                },
                "required": ["query"]
            },
            strict=False
        )
    ]


AGENT_INSTRUCTIONS = """You are an OneDrive assistant that helps users manage and explore their files.

You can:
- List files in any folder in the user's OneDrive
- Search for files by name or content
- Show drive storage information

Always be helpful and provide clear, organized responses. When listing files, format them nicely.
If an operation fails, explain what happened and suggest alternatives.

Note: You access the user's OneDrive on their behalf using delegated permissions."""


def create_agent():
    """Create the Standard Agent using the AI Projects API with create_version."""
    model_deployment = get_env_or_fail("CHAT_MODEL_DEPLOYMENT")
    agent_name = os.environ.get("AGENT_NAME", "OneDrive-Agent")
    
    print(f"Creating Standard Agent: {agent_name}")
    
    project_client = get_project_client()
    
    # Create agent definition with function tools
    agent_definition = PromptAgentDefinition(
        model=model_deployment,
        instructions=AGENT_INSTRUCTIONS,
        tools=get_function_tools()
    )
    
    # Create versioned agent using the new Foundry API (visible in portal)
    agent = project_client.agents.create_version(
        agent_name=agent_name,
        definition=agent_definition
    )
    
    print(f"Created agent: {agent.id}")
    
    # Save to azd environment
    os.system(f'azd env set AGENT_ID "{agent.id}"')
    os.system(f'azd env set AGENT_NAME "{agent_name}"')
    
    print()
    print("=" * 50)
    print("Standard Agent created successfully!")
    print(f"  Agent ID: {agent.id}")
    print(f"  Agent Name: {agent_name}")
    print("=" * 50)
    print(f"\nAgent visible in Foundry portal under: Build > Agents > {agent_name}")


def delete_agent():
    """Delete the Standard Agent."""
    agent_id = os.environ.get("AGENT_ID")
    agent_name = os.environ.get("AGENT_NAME", "OneDrive-Agent")
    
    if not agent_id:
        print("No agent to delete (AGENT_ID not set)")
        return
    
    print(f"Deleting agent: {agent_name} (ID: {agent_id})")
    
    project_client = get_project_client()
    
    try:
        # Agent ID format from create_version is "AgentName:version"
        if ":" in agent_id:
            name, version = agent_id.rsplit(":", 1)
            project_client.agents.delete_version(agent_name=name, agent_version=version)
        else:
            # Fallback: try to delete by name with version 1
            project_client.agents.delete_version(agent_name=agent_name, agent_version="1")
        print("Agent deleted successfully")
    except Exception as e:
        print(f"Error deleting agent: {e}")


def list_agents():
    """List all Standard Agents."""
    print("Standard Agents in project:")
    print("-" * 50)
    
    project_client = get_project_client()
    
    agents = project_client.agents.list()
    for agent in agents:
        print(f"  {agent.name} (id: {agent.id})")


def main():
    if len(sys.argv) < 2:
        print("Usage: python agent_manager.py <command>")
        print("Commands:")
        print("  create  - Create Standard Agent")
        print("  delete  - Delete Standard Agent")
        print("  list    - List all agents")
        sys.exit(1)
    
    command = sys.argv[1].lower()
    
    if command == "create":
        create_agent()
    elif command == "delete":
        delete_agent()
    elif command == "list":
        list_agents()
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
