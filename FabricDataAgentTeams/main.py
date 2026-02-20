"""
Fabric Data Agent Teams Bot - Main Entry Point

Runs an aiohttp web server that handles Bot Framework messages from Teams.
"""

import logging
import sys
import os

from aiohttp import web
from aiohttp.web import Request, Response
from dotenv import load_dotenv

from botbuilder.core import (
    MemoryStorage,
    UserState,
    ConversationState,
    TurnContext,
)
from botbuilder.integration.aiohttp import CloudAdapter
from botbuilder.core.integration import aiohttp_error_middleware
from botbuilder.schema import Activity

from botframework.connector.auth import (
    AuthenticationConfiguration,
    BotFrameworkAuthenticationFactory,
    ManagedIdentityServiceClientCredentialsFactory,
)

# Load environment variables
load_dotenv()

from app.config import AppConfig
from app.bot import FabricDataAgentBot
from app.fabric_agent import FabricDataAgentService

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)

# Load configuration
config = AppConfig.from_env()

# Validate configuration
missing = config.validate()
if missing:
    logger.warning(f"Missing configuration: {', '.join(missing)}")

# Create credential factory for bot authentication
# Priority: Password auth > Managed Identity
# Note: Python Bot Framework SDK's MI support doesn't fully support FIC
from botframework.connector.auth import PasswordServiceClientCredentialFactory

if config.bot.microsoft_app_password:
    logger.info("Using password-based authentication")
    credential_factory = PasswordServiceClientCredentialFactory(
        app_id=config.bot.microsoft_app_id,
        password=config.bot.microsoft_app_password,
        tenant_id=config.bot.microsoft_app_tenant_id,
    )
else:
    # Try Managed Identity (works for system-assigned MI with direct permissions)
    managed_identity_client_id = os.getenv("AZURE_CLIENT_ID")
    if managed_identity_client_id:
        logger.info(f"Using Managed Identity auth with client ID: {managed_identity_client_id[:8]}...")
        credential_factory = ManagedIdentityServiceClientCredentialsFactory(
            app_id=config.bot.microsoft_app_id,
        )
    else:
        logger.error("No authentication configured - bot will not work")
        credential_factory = PasswordServiceClientCredentialFactory(
            app_id=config.bot.microsoft_app_id,
            password="",
            tenant_id=config.bot.microsoft_app_tenant_id,
        )

# Create authentication configuration
auth_config = AuthenticationConfiguration()

# Create bot framework authentication using the factory
bot_framework_auth = BotFrameworkAuthenticationFactory.create(
    credential_factory=credential_factory,
    auth_configuration=auth_config,
)

# Create CloudAdapter with proper authentication (supports SSO/token exchange)
adapter = CloudAdapter(bot_framework_auth)


async def on_error(context, error):
    """Error handler for the bot adapter."""
    logger.exception(f"Bot error: {error}")
    
    await context.send_activity("Sorry, something went wrong. Please try again.")
    
    # Clear state on error
    await conversation_state.delete(context)
    await user_state.delete(context)


adapter.on_turn_error = on_error

# State storage
storage = MemoryStorage()
user_state = UserState(storage)
conversation_state = ConversationState(storage)

# Fabric Data Agent service
fabric_service = FabricDataAgentService(
    workspace_id=config.fabric.workspace_id,
    agent_id=config.fabric.agent_id,
)

# Create bot instance
bot = FabricDataAgentBot(
    config=config,
    fabric_service=fabric_service,
    user_state=user_state,
    conversation_state=conversation_state,
)


# =============================================================================
# HTTP Endpoints
# =============================================================================

async def health(request: Request) -> Response:
    """Health check endpoint."""
    return web.json_response({
        "status": "healthy",
        "service": "Fabric Data Agent Teams Bot",
    })


async def home(request: Request) -> Response:
    """Root endpoint."""
    return web.Response(
        text="Fabric Data Agent Teams Bot - Powered by Microsoft Fabric",
        content_type="text/plain",
    )


async def messages(request: Request) -> Response:
    """Bot Framework messaging endpoint."""
    if request.content_type != "application/json":
        return Response(status=415)
    
    body = await request.json()
    activity = Activity().deserialize(body)
    auth_header = request.headers.get("Authorization", "")
    
    # CloudAdapter.process_activity signature
    invoke_response = await adapter.process_activity(auth_header, activity, bot.on_turn)
    
    if invoke_response:
        return web.json_response(data=invoke_response.body, status=invoke_response.status)
    return Response(status=201)


# =============================================================================
# Application Setup
# =============================================================================

def create_app() -> web.Application:
    """Create and configure the aiohttp application."""
    app = web.Application(middlewares=[aiohttp_error_middleware])
    
    app.router.add_get("/", home)
    app.router.add_get("/health", health)
    app.router.add_post("/api/messages", messages)
    
    return app


def main():
    """Run the application."""
    app = create_app()
    
    port = config.port
    logger.info(f"Starting Fabric Data Agent Teams Bot on port {port}")
    logger.info(f"Bot App ID: {config.bot.microsoft_app_id[:8]}..." if config.bot.microsoft_app_id else "Bot App ID: not configured")
    logger.info(f"Fabric Workspace: {config.fabric.workspace_id[:8]}..." if config.fabric.workspace_id else "Fabric Workspace: not configured")
    
    web.run_app(app, host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
