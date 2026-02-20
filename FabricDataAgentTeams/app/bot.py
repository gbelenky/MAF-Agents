"""
Fabric Data Agent Teams Bot.

Handles Teams messages with SSO authentication, forwarding queries to Fabric Data Agent.
"""

import logging
from typing import Optional

from botbuilder.core import (
    ActivityHandler,
    TurnContext,
    UserState,
    ConversationState,
)
from botbuilder.schema import Activity, ActivityTypes, ChannelAccount
from botbuilder.core.teams import TeamsActivityHandler

from .config import AppConfig
from .fabric_agent import FabricDataAgentService

logger = logging.getLogger(__name__)


class FabricDataAgentBot(TeamsActivityHandler):
    """
    Bot that handles Teams messages and forwards them to Fabric Data Agent.
    
    Uses Teams SSO for authentication - the user's token is exchanged for
    a Fabric API token via the OAuth connection configured in Azure Bot Service.
    """
    
    def __init__(
        self,
        config: AppConfig,
        fabric_service: FabricDataAgentService,
        user_state: UserState,
        conversation_state: ConversationState,
    ):
        self._config = config
        self._fabric_service = fabric_service
        self._user_state = user_state
        self._conversation_state = conversation_state
    
    async def on_turn(self, turn_context: TurnContext):
        """Process each turn and save state."""
        await super().on_turn(turn_context)
        await self._user_state.save_changes(turn_context)
        await self._conversation_state.save_changes(turn_context)
    
    async def on_message_activity(self, turn_context: TurnContext):
        """Handle incoming messages from Teams."""
        user_message = turn_context.activity.text
        if not user_message:
            await turn_context.send_activity("Please send a message.")
            return
        
        user_message = user_message.strip()
        logger.info(f"Received message: {user_message[:50]}...")
        
        # Check for magic code (6-digit OAuth fallback)
        if user_message.isdigit() and len(user_message) == 6:
            logger.info("Received magic code, attempting token exchange")
            token = await self._get_user_token(turn_context, magic_code=user_message)
            if token:
                await turn_context.send_activity(
                    "You're now signed in! How can I help you with your data?"
                )
            else:
                await self._send_oauth_card(turn_context)
            return
        
        # Try to get user token from SSO
        token = await self._get_user_token(turn_context)
        
        if not token:
            logger.info("No token available, sending OAuth card")
            await self._send_oauth_card(turn_context)
            return
        
        # Process the message with Fabric Data Agent
        try:
            # Show typing indicator
            await turn_context.send_activity(Activity(type=ActivityTypes.typing))
            
            response = await self._fabric_service.chat(user_message, token)
            await turn_context.send_activity(response)
            
        except Exception as e:
            logger.exception("Error processing message")
            await turn_context.send_activity(
                f"Sorry, I encountered an error: {str(e)}"
            )
    
    async def on_token_response_event(self, turn_context: TurnContext):
        """Handle OAuth token response from sign-in card."""
        logger.info("Token response event received - user signed in")
        await turn_context.send_activity(
            "You're now signed in! How can I help you with your data?"
        )
    
    async def on_teams_signin_verify_state(self, turn_context: TurnContext):
        """Handle Teams sign-in verification."""
        logger.info("Teams signin verify state received")
        await turn_context.send_activity(
            "You're now signed in! How can I help you with your data?"
        )
    
    async def on_members_added_activity(
        self, 
        members_added: list[ChannelAccount], 
        turn_context: TurnContext
    ):
        """Welcome new members."""
        for member in members_added:
            if member.id != turn_context.activity.recipient.id:
                await turn_context.send_activity(
                    "Hello! I'm the Fabric Data Agent assistant. "
                    "Ask me questions about your data and I'll help you find answers."
                )
    
    async def _get_user_token(
        self, 
        turn_context: TurnContext,
        magic_code: Optional[str] = None
    ) -> Optional[str]:
        """
        Get the user's token from the OAuth connection.
        
        With Teams SSO properly configured, this returns the token immediately.
        Falls back to OAuth card if SSO isn't available.
        """
        try:
            # Get token from Bot Framework token service
            user_token_client = turn_context.turn_state.get("UserTokenClient")
            if not user_token_client:
                logger.warning("No UserTokenClient in turn state")
                return None
            
            token_response = await user_token_client.get_user_token(
                turn_context.activity.from_property.id,
                self._config.bot.oauth_connection_name,
                turn_context.activity.channel_id,
                magic_code,
            )
            
            if token_response and token_response.token:
                return token_response.token
            
            return None
            
        except Exception as e:
            logger.warning(f"Failed to get user token: {e}")
            return None
    
    async def _send_oauth_card(self, turn_context: TurnContext):
        """Send OAuth sign-in card to the user."""
        try:
            user_token_client = turn_context.turn_state.get("UserTokenClient")
            if not user_token_client:
                await turn_context.send_activity(
                    "Authentication is not configured. Please contact your administrator."
                )
                return
            
            # Get sign-in resource (URL for OAuth)
            # final_redirect is optional but some SDK versions require it
            signin_resource = await user_token_client.get_sign_in_resource(
                self._config.bot.oauth_connection_name,
                turn_context.activity,
                "",  # final_redirect - empty string for default behavior
            )
            
            if signin_resource and signin_resource.sign_in_link:
                from botbuilder.schema import (
                    OAuthCard, 
                    Attachment, 
                    CardAction, 
                    ActionTypes
                )
                
                oauth_card = OAuthCard(
                    text="Please sign in to access Fabric Data Agent",
                    connection_name=self._config.bot.oauth_connection_name,
                    buttons=[
                        CardAction(
                            type=ActionTypes.signin,
                            title="Sign In",
                            value=signin_resource.sign_in_link,
                        )
                    ],
                    token_exchange_resource=signin_resource.token_exchange_resource,
                )
                
                attachment = Attachment(
                    content_type="application/vnd.microsoft.card.oauth",
                    content=oauth_card,
                )
                
                reply = Activity(
                    type=ActivityTypes.message,
                    attachments=[attachment],
                )
                
                await turn_context.send_activity(reply)
            else:
                await turn_context.send_activity(
                    "Unable to create sign-in link. Please try again later."
                )
                
        except Exception as e:
            logger.exception("Failed to send OAuth card")
            await turn_context.send_activity(
                f"Authentication error: {str(e)}"
            )
    
    async def on_invoke_activity(self, turn_context: TurnContext):
        """Handle invoke activities including SSO token exchange."""
        if turn_context.activity.name == "signin/tokenExchange":
            return await self._handle_token_exchange(turn_context)
        
        return await super().on_invoke_activity(turn_context)
    
    async def _handle_token_exchange(self, turn_context: TurnContext):
        """Handle Teams SSO token exchange."""
        from botbuilder.schema import InvokeResponse, TokenExchangeInvokeResponse
        from botframework.connector.token_api.models import TokenExchangeRequest
        
        logger.info("SSO token exchange request received")
        
        try:
            # Extract token from the request
            value = turn_context.activity.value
            if isinstance(value, dict):
                token_exchange_request_token = value.get("token")
                token_exchange_request_id = value.get("id")
            else:
                token_exchange_request_token = getattr(value, "token", None)
                token_exchange_request_id = getattr(value, "id", None)
            
            if not token_exchange_request_token:
                logger.warning("No token in exchange request")
                return InvokeResponse(status=400)
            
            user_token_client = turn_context.turn_state.get("UserTokenClient")
            if not user_token_client:
                logger.warning("No UserTokenClient for token exchange")
                return InvokeResponse(status=500)
            
            # Exchange the token
            token_response = await user_token_client.exchange_token(
                turn_context.activity.from_property.id,
                self._config.bot.oauth_connection_name,
                turn_context.activity.channel_id,
                TokenExchangeRequest(token=token_exchange_request_token),
            )
            
            # Check if response is an error
            if hasattr(token_response, 'error') and token_response.error:
                error_msg = getattr(token_response.error, 'message', str(token_response.error))
                logger.warning(f"Token exchange returned error: {error_msg}")
                return InvokeResponse(
                    status=409,
                    body={
                        "id": token_exchange_request_id,
                        "connectionName": self._config.bot.oauth_connection_name,
                        "failureDetail": error_msg,
                    },
                )
            
            if token_response and hasattr(token_response, 'token') and token_response.token:
                logger.info("SSO token exchange successful")
                return InvokeResponse(status=200)
            
            logger.warning("Token exchange returned no token")
            return InvokeResponse(
                status=409,
                body={
                    "id": token_exchange_request_id,
                    "connectionName": self._config.bot.oauth_connection_name,
                    "failureDetail": "Token exchange failed",
                },
            )
            
        except Exception as e:
            logger.exception("Token exchange error")
            return InvokeResponse(
                status=409,
                body={
                    "connectionName": self._config.bot.oauth_connection_name,
                    "failureDetail": str(e),
                },
            )
