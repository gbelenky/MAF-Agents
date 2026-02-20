"""
Fabric Data Agent Chat Client

A standalone client for interacting with published Microsoft Fabric Data Agents.
Uses Azure Identity for authentication.
"""

import os
import sys
import time
import requests

from dotenv import load_dotenv
load_dotenv()

from azure.identity import DefaultAzureCredential


class DataAgentClient:
    """Client for querying published Fabric Data Agents via OpenAI Assistants API."""
    
    FABRIC_API = "https://api.fabric.microsoft.com/v1"
    FABRIC_SCOPE = "https://api.fabric.microsoft.com/.default"
    API_VERSION = "2024-05-01-preview"
    
    def __init__(self, workspace_id: str, agent_id: str, verbose: bool = True):
        self.base_url = f"{self.FABRIC_API}/workspaces/{workspace_id}/dataagents/{agent_id}/aiassistant/openai"
        self.agent_id = agent_id
        self.credential = DefaultAzureCredential()
        self._token = None
        self._token_expires = 0
        self._thread_id = None
        self._verbose = verbose
        
        if verbose:
            print(f"Endpoint: {self.base_url}")
    
    @classmethod
    def from_env(cls, verbose: bool = True) -> "DataAgentClient":
        """Create client from FABRIC_WORKSPACE_ID and FABRIC_AGENT_ITEM_ID env vars."""
        workspace_id = os.environ.get("FABRIC_WORKSPACE_ID")
        agent_id = os.environ.get("FABRIC_AGENT_ITEM_ID")
        
        if not workspace_id or not agent_id:
            raise ValueError(
                "Set FABRIC_WORKSPACE_ID and FABRIC_AGENT_ITEM_ID in .env file"
            )
        
        return cls(workspace_id, agent_id, verbose)
    
    def _get_token(self) -> str:
        if not self._token or time.time() >= self._token_expires - 300:
            token = self.credential.get_token(self.FABRIC_SCOPE)
            self._token = token.token
            self._token_expires = token.expires_on
            if self._verbose:
                print("Token acquired")
        return self._token
    
    def _request(self, method: str, endpoint: str, json_data: dict = None) -> dict:
        separator = "&" if "?" in endpoint else "?"
        url = f"{self.base_url}{endpoint}{separator}api-version={self.API_VERSION}"
        headers = {
            "Authorization": f"Bearer {self._get_token()}",
            "Content-Type": "application/json"
        }
        
        resp = requests.request(method, url, headers=headers, json=json_data)
        resp.raise_for_status()
        return resp.json() if resp.content else {}
    
    def create_thread(self) -> str:
        result = self._request("POST", "/threads")
        self._thread_id = result.get("id")
        if self._verbose:
            print(f"Thread: {self._thread_id}")
        return self._thread_id
    
    def query(self, question: str, timeout: int = 300) -> str:
        """Send query and wait for response."""
        if not self._thread_id:
            self.create_thread()
        
        # Add message to thread
        self._request("POST", f"/threads/{self._thread_id}/messages", {
            "role": "user", "content": question
        })
        
        # Create assistant (required for each run)
        assistant = self._request("POST", "/assistants", {"model": "not used"})
        assistant_id = assistant.get("id")
        
        # Create run
        run = self._request("POST", f"/threads/{self._thread_id}/runs", {
            "assistant_id": assistant_id
        })
        
        start = time.time()
        while run.get("status") not in ("completed", "failed", "cancelled", "expired"):
            if time.time() - start > timeout:
                raise TimeoutError("Query timed out")
            time.sleep(2)
            run = self._request("GET", f"/threads/{self._thread_id}/runs/{run['id']}")
        
        if run["status"] != "completed":
            raise RuntimeError(f"Run failed: {run['status']}")
        
        # Get response
        messages = self._request("GET", f"/threads/{self._thread_id}/messages?order=desc")
        for msg in messages.get("data", []):
            if msg["role"] == "assistant":
                content = msg.get("content", [])
                if content:
                    return content[0].get("text", {}).get("value", "")
        return ""
    
    def clear(self):
        """Delete thread and start fresh."""
        if self._thread_id:
            try:
                self._request("DELETE", f"/threads/{self._thread_id}")
            except Exception:
                pass
            self._thread_id = None


def chat():
    """Interactive chat with Fabric Data Agent."""
    if sys.platform == 'win32':
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    
    print("=" * 50)
    print("  Fabric Data Agent Chat")
    print("=" * 50)
    print("\nConnecting...")
    
    try:
        client = DataAgentClient.from_env()
        client.create_thread()
        print("Ready!\n")
    except Exception as e:
        print(f"Error: {e}")
        return
    
    print("Commands: quit, clear\n")
    
    try:
        while True:
            try:
                q = input("You: ").strip()
            except EOFError:
                break
            
            if not q:
                continue
            if q.lower() in ('quit', 'exit', 'q'):
                break
            if q.lower() == 'clear':
                client.clear()
                client.create_thread()
                print("Thread cleared.\n")
                continue
            
            try:
                print("\nAgent: ", end="", flush=True)
                print(client.query(q))
                print()
            except Exception as e:
                print(f"\n[Error: {e}]\n")
    finally:
        client.clear()
        print("\nSession ended.")


if __name__ == "__main__":
    chat()
