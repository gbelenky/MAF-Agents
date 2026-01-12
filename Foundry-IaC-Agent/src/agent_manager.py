"""
Azure AI Foundry Standard Agent Manager

This module manages the lifecycle of Standard Agents with Vector Store
using the new Azure AI Foundry API (not Classic/Persistent agents).

Usage:
    python agent_manager.py create   - Create agent with vector store
    python agent_manager.py delete   - Delete agent and vector store
    python agent_manager.py chat     - Interactive chat with the agent
"""

import os
import sys
from pathlib import Path

from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    PromptAgentDefinition,
    FileSearchTool,
)


def get_project_client() -> AIProjectClient:
    """Create and return an AIProjectClient using DefaultAzureCredential."""
    endpoint = os.environ.get("PROJECT_ENDPOINT")
    if not endpoint:
        raise ValueError("PROJECT_ENDPOINT environment variable is required")
    
    credential = DefaultAzureCredential()
    return AIProjectClient(endpoint=endpoint, credential=credential)


def create_agent_with_vector_store():
    """
    Create a Standard Agent with Vector Store and File Search capability.
    
    This creates:
    1. Uploads a document to the file store
    2. Creates a vector store with the document
    3. Creates a Standard Agent with FileSearchTool pointing to the vector store
    """
    print("Creating Standard Agent with Vector Store...")
    
    # Get configuration
    model_deployment = os.environ.get("CHAT_MODEL_DEPLOYMENT", "gpt-4.1-mini")
    
    # Initialize clients
    project_client = get_project_client()
    openai_client = project_client.get_openai_client()
    
    # Step 1: Upload document file
    print("  Uploading document...")
    docs_path = Path(__file__).parent / "docs" / "product_manual.md"
    
    if not docs_path.exists():
        raise FileNotFoundError(f"Document not found: {docs_path}")
    
    with open(docs_path, "rb") as f:
        uploaded_file = openai_client.files.create(
            file=f,
            purpose="assistants"
        )
    print(f"  FILE_ID: {uploaded_file.id}")
    
    # Step 2: Create vector store with the file
    print("  Creating vector store...")
    vector_store = openai_client.vector_stores.create(
        name="ProductDocsVectorStore",
        file_ids=[uploaded_file.id]
    )
    print(f"  VECTORSTORE_ID: {vector_store.id}")
    
    # Wait for vector store to be ready
    print("  Waiting for vector store processing...")
    import time
    while True:
        vs_status = openai_client.vector_stores.retrieve(vector_store.id)
        if vs_status.status == "completed":
            print("  Vector store ready!")
            break
        elif vs_status.status == "failed":
            raise RuntimeError(f"Vector store creation failed: {vs_status}")
        time.sleep(1)
    
    # Step 3: Create Standard Agent with File Search tool
    print("  Creating Standard Agent...")
    
    agent_definition = PromptAgentDefinition(
        model=model_deployment,
        instructions="""You are a helpful product documentation assistant.
You have access to product documentation via file search.
When users ask questions, search the documents to provide accurate answers.
Always cite the source when providing information from documents.
If you cannot find relevant information, say so clearly.""",
        tools=[
            FileSearchTool(vector_store_ids=[vector_store.id])
        ]
    )
    
    # Create versioned agent using the new Foundry API
    agent = project_client.agents.create_version(
        agent_name="IaCDocumentAgent",
        definition=agent_definition
    )
    
    print(f"  AGENT_ID: {agent.id}")
    print()
    print("=" * 50)
    print("Standard Agent created successfully!")
    print(f"  Agent ID: {agent.id}")
    print(f"  Vector Store ID: {vector_store.id}")
    print(f"  File ID: {uploaded_file.id}")
    print("=" * 50)
    
    return agent.id, vector_store.id, uploaded_file.id


def delete_agent_and_resources():
    """
    Delete the Standard Agent and associated resources.
    
    Reads resource IDs from environment variables set by azd.
    """
    print("Deleting Standard Agent and resources...")
    
    agent_id = os.environ.get("AGENT_ID")
    vectorstore_id = os.environ.get("VECTORSTORE_ID")
    file_id = os.environ.get("FILE_ID")
    
    project_client = get_project_client()
    openai_client = project_client.get_openai_client()
    
    # Delete agent
    if agent_id:
        try:
            # Extract name and version from ID (format: "AgentName:version")
            if ":" in agent_id:
                agent_name, agent_version = agent_id.rsplit(":", 1)
            else:
                agent_name = agent_id
                agent_version = "1"
            
            print(f"  Deleting agent: {agent_name} version {agent_version}")
            project_client.agents.delete_version(agent_name=agent_name, agent_version=agent_version)
            print("  Agent deleted.")
        except Exception as e:
            print(f"  Warning: Could not delete agent: {e}")
    
    # Delete vector store
    if vectorstore_id:
        try:
            print(f"  Deleting vector store: {vectorstore_id}")
            openai_client.vector_stores.delete(vectorstore_id)
            print("  Vector store deleted.")
        except Exception as e:
            print(f"  Warning: Could not delete vector store: {e}")
    
    # Delete file
    if file_id:
        try:
            print(f"  Deleting file: {file_id}")
            openai_client.files.delete(file_id)
            print("  File deleted.")
        except Exception as e:
            print(f"  Warning: Could not delete file: {e}")
    
    print()
    print("Cleanup completed.")


def chat_with_agent():
    """
    Interactive chat session with the Standard Agent.
    Uses the new Conversations/Responses API.
    """
    agent_id = os.environ.get("AGENT_ID")
    if not agent_id:
        print("Error: AGENT_ID not set. Run 'create' first.")
        sys.exit(1)
    
    # Extract agent name from ID (format: "AgentName:version")
    agent_name = agent_id.split(":")[0] if ":" in agent_id else agent_id
    
    print(f"Starting chat with Standard Agent '{agent_name}'...")
    print("Type 'quit' or 'exit' to end the session.")
    print("-" * 50)
    
    project_client = get_project_client()
    openai_client = project_client.get_openai_client()
    
    # Create a conversation
    conversation = openai_client.conversations.create(
        items=[]
    )
    print(f"Conversation started (id: {conversation.id})")
    
    while True:
        user_input = input("\nYou: ").strip()
        if user_input.lower() in ["quit", "exit", "q"]:
            # Clean up conversation
            try:
                openai_client.conversations.delete(conversation_id=conversation.id)
            except:
                pass
            print("Goodbye!")
            break
        
        if not user_input:
            continue
        
        # Add user message to conversation
        openai_client.conversations.items.create(
            conversation_id=conversation.id,
            items=[{"type": "message", "role": "user", "content": user_input}]
        )
        
        # Get response from agent
        response = openai_client.responses.create(
            conversation=conversation.id,
            extra_body={"agent": {"name": agent_name, "type": "agent_reference"}},
            input=""
        )
        
        print(f"\nAssistant: {response.output_text}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python agent_manager.py <command>")
        print("Commands:")
        print("  create  - Create agent with vector store")
        print("  delete  - Delete agent and resources")
        print("  chat    - Interactive chat with agent")
        sys.exit(1)
    
    command = sys.argv[1].lower()
    
    if command == "create":
        create_agent_with_vector_store()
    elif command == "delete":
        delete_agent_and_resources()
    elif command == "chat":
        chat_with_agent()
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
