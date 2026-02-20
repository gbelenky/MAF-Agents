"""
Configuration for Fabric Data Agent Teams Bot.

Loads settings from environment variables (set by Azure App Service or .env file).
"""

import os
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class BotConfig:
    """Bot Framework configuration for Teams/M365 Copilot."""
    
    # Bot identity (from Entra ID app registration)
    microsoft_app_id: str = ""
    microsoft_app_password: str = ""  # Not used with Managed Identity
    microsoft_app_tenant_id: str = ""
    
    # OAuth connection (configured in Azure Bot Service)
    oauth_connection_name: str = "fabric-connection"
    
    @classmethod
    def from_env(cls) -> "BotConfig":
        return cls(
            microsoft_app_id=os.environ.get("BOT_MICROSOFT_APP_ID") or os.environ.get("MicrosoftAppId", ""),
            microsoft_app_password=os.environ.get("BOT_MICROSOFT_APP_PASSWORD") or os.environ.get("MicrosoftAppPassword", ""),
            microsoft_app_tenant_id=os.environ.get("BOT_MICROSOFT_APP_TENANT_ID") or os.environ.get("MicrosoftAppTenantId", ""),
            oauth_connection_name=os.environ.get("BOT_OAUTH_CONNECTION_NAME", "fabric-connection"),
        )


@dataclass
class FabricAgentConfig:
    """Fabric Data Agent configuration."""
    
    # Fabric workspace and agent IDs
    workspace_id: str = ""
    agent_id: str = ""
    
    @classmethod
    def from_env(cls) -> "FabricAgentConfig":
        return cls(
            workspace_id=os.environ.get("FABRIC_WORKSPACE_ID", ""),
            agent_id=os.environ.get("FABRIC_AGENT_ITEM_ID", ""),
        )


@dataclass 
class AppConfig:
    """Application configuration combining all settings."""
    
    bot: BotConfig = field(default_factory=BotConfig)
    fabric: FabricAgentConfig = field(default_factory=FabricAgentConfig)
    
    # Server settings
    port: int = 8080
    
    # Application Insights
    app_insights_connection_string: str = ""
    
    @classmethod
    def from_env(cls) -> "AppConfig":
        return cls(
            bot=BotConfig.from_env(),
            fabric=FabricAgentConfig.from_env(),
            port=int(os.environ.get("PORT", "8080")),
            app_insights_connection_string=os.environ.get(
                "APPLICATIONINSIGHTS_CONNECTION_STRING", ""
            ),
        )
    
    def validate(self) -> list[str]:
        """Validate configuration and return list of missing settings."""
        errors = []
        
        if not self.bot.microsoft_app_id:
            errors.append("BOT_MICROSOFT_APP_ID")
        if not self.bot.microsoft_app_tenant_id:
            errors.append("BOT_MICROSOFT_APP_TENANT_ID")
        if not self.fabric.workspace_id:
            errors.append("FABRIC_WORKSPACE_ID")
        if not self.fabric.agent_id:
            errors.append("FABRIC_AGENT_ITEM_ID")
            
        return errors
