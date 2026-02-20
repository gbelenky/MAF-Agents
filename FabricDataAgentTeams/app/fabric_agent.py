"""
Fabric Data Agent client for Teams bot integration.

Adapted from the standalone prototype to accept user tokens for SSO.
"""

import asyncio
import time
from typing import Optional

import aiohttp


class FabricDataAgentClient:
    """
    Async client for querying Fabric Data Agents via OpenAI Assistants API.
    
    Accepts a user token for on-behalf-of (OBO) access.
    """
    
    FABRIC_API = "https://api.fabric.microsoft.com/v1"
    API_VERSION = "2024-05-01-preview"
    
    def __init__(
        self, 
        workspace_id: str, 
        agent_id: str,
        user_token: str,
    ):
        """
        Initialize the client.
        
        Args:
            workspace_id: Fabric workspace ID
            agent_id: Fabric Data Agent item ID
            user_token: User's access token (from Teams SSO / OBO)
        """
        self.base_url = (
            f"{self.FABRIC_API}/workspaces/{workspace_id}"
            f"/dataagents/{agent_id}/aiassistant/openai"
        )
        self.agent_id = agent_id
        self._token = user_token
        self._thread_id: Optional[str] = None
        self._session: Optional[aiohttp.ClientSession] = None
    
    async def _get_session(self) -> aiohttp.ClientSession:
        """Get or create aiohttp session."""
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession()
        return self._session
    
    async def close(self):
        """Close the HTTP session."""
        if self._session and not self._session.closed:
            await self._session.close()
            self._session = None
    
    async def _request(
        self, 
        method: str, 
        endpoint: str, 
        json_data: dict = None
    ) -> dict:
        """Make an authenticated request to the Fabric API."""
        separator = "&" if "?" in endpoint else "?"
        url = f"{self.base_url}{endpoint}{separator}api-version={self.API_VERSION}"
        headers = {
            "Authorization": f"Bearer {self._token}",
            "Content-Type": "application/json"
        }
        
        session = await self._get_session()
        async with session.request(method, url, headers=headers, json=json_data) as resp:
            if resp.status >= 400:
                error_text = await resp.text()
                raise Exception(f"API error {resp.status}: {error_text}")
            
            if resp.content_length == 0:
                return {}
            return await resp.json()
    
    async def create_thread(self) -> str:
        """Create a new conversation thread."""
        result = await self._request("POST", "/threads")
        self._thread_id = result.get("id")
        return self._thread_id
    
    async def query(self, question: str, timeout: int = 300) -> str:
        """
        Send a query and wait for response.
        
        Args:
            question: The user's question
            timeout: Maximum wait time in seconds
            
        Returns:
            The agent's response text
        """
        if not self._thread_id:
            await self.create_thread()
        
        # Add message to thread
        await self._request("POST", f"/threads/{self._thread_id}/messages", {
            "role": "user",
            "content": question
        })
        
        # Create assistant (required for each run with Fabric)
        assistant = await self._request("POST", "/assistants", {"model": "not used"})
        assistant_id = assistant.get("id")
        
        # Create run
        run = await self._request("POST", f"/threads/{self._thread_id}/runs", {
            "assistant_id": assistant_id
        })
        
        # Poll for completion
        start = time.time()
        while run.get("status") not in ("completed", "failed", "cancelled", "expired"):
            if time.time() - start > timeout:
                raise TimeoutError("Query timed out")
            await asyncio.sleep(2)
            run = await self._request("GET", f"/threads/{self._thread_id}/runs/{run['id']}")
        
        if run["status"] != "completed":
            raise RuntimeError(f"Run failed with status: {run['status']}")
        
        # Get response messages
        messages = await self._request(
            "GET", 
            f"/threads/{self._thread_id}/messages?order=desc"
        )
        
        for msg in messages.get("data", []):
            if msg["role"] == "assistant":
                content = msg.get("content", [])
                if content:
                    return content[0].get("text", {}).get("value", "")
        
        return ""
    
    async def clear_thread(self):
        """Delete the current thread and reset."""
        if self._thread_id:
            try:
                await self._request("DELETE", f"/threads/{self._thread_id}")
            except Exception:
                pass  # Ignore errors when deleting
            self._thread_id = None


class FabricDataAgentService:
    """
    Service wrapper for Fabric Data Agent interactions.
    
    Creates per-request clients with user tokens.
    """
    
    def __init__(self, workspace_id: str, agent_id: str):
        """
        Initialize the service.
        
        Args:
            workspace_id: Fabric workspace ID
            agent_id: Fabric Data Agent item ID
        """
        self.workspace_id = workspace_id
        self.agent_id = agent_id
    
    async def chat(self, message: str, user_token: str) -> str:
        """
        Process a chat message using the user's token.
        
        Args:
            message: The user's message
            user_token: User's Fabric API access token
            
        Returns:
            The agent's response
        """
        client = FabricDataAgentClient(
            workspace_id=self.workspace_id,
            agent_id=self.agent_id,
            user_token=user_token,
        )
        
        try:
            response = await client.query(message)
            return response
        finally:
            await client.close()
