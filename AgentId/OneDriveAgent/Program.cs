// Copyright (c) Microsoft. All rights reserved.

using Microsoft.Agents.Hosting.AspNetCore;
using Microsoft.Agents.Builder;
using OneDriveAgent.Services;

// =============================================================================
// Handle "setup" command for Agent Identity provisioning
// =============================================================================
if (args.Length > 0 && args[0] == "setup")
{
    var exitCode = await SetupProgram.RunSetupAsync(args.Skip(1).ToArray());
    return;
}

var builder = WebApplication.CreateBuilder(args);

// Note: Port configuration is in appsettings.json (Kestrel section)
// - Production: 8080 (appsettings.json)
// - Development: 3978 (appsettings.Development.json)

if (builder.Environment.IsDevelopment())
{
    builder.Configuration.AddUserSecrets<Program>();
}

builder.Services.AddHttpClient();

// Add Application Insights for telemetry - auto-reads APPLICATIONINSIGHTS_CONNECTION_STRING
builder.Services.AddApplicationInsightsTelemetry(options => 
{
    options.EnableDebugLogger = true;
});

// Set Cloud_RoleName for multi-component filtering in App Insights
// This enables filtering this component vs AI Services logs in the same workspace
builder.Services.AddSingleton<Microsoft.ApplicationInsights.Extensibility.ITelemetryInitializer>(sp =>
    new CloudRoleNameInitializer("OneDriveAgent"));

// =============================================================================
// Configure MAF Agent Service with OneDrive tools
// =============================================================================
builder.Services.Configure<MafAgentConfig>(builder.Configuration.GetSection("MafAgent"));
builder.Services.AddSingleton<IMafAgentService, MafAgentService>();

// =============================================================================
// Configure Bot Framework for Teams / M365 Copilot
// =============================================================================
builder.Services.Configure<BotConfig>(builder.Configuration.GetSection("Bot"));

// Add M365 Agents SDK - handles authentication and activity processing
builder.AddAgent<OneDriveAgentBot>();

var app = builder.Build();

// =============================================================================
// API Endpoints
// =============================================================================

app.MapGet("/", () => "OneDrive Agent - Powered by Azure AI Foundry Agent Service");

app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }));

/// <summary>
/// Chat endpoint - send a message and get a response from the MAF Agent.
/// </summary>
app.MapPost("/api/chat", async (
    ChatRequest request,
    IMafAgentService agentService,
    ILogger<Program> logger,
    CancellationToken cancellationToken) =>
{
    if (string.IsNullOrWhiteSpace(request.Message))
    {
        return Results.BadRequest(new { error = "Message is required" });
    }

    try
    {
        // Process message with MAF Agent (OBO handled internally)
        var response = await agentService.ChatAsync(
            request.Message,
            request.UserToken,
            cancellationToken);

        return Results.Ok(new ChatResponse
        {
            Message = response,
            ConversationId = Guid.NewGuid().ToString(),
            Timestamp = DateTime.UtcNow
        });
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error processing chat message");
        return Results.Problem(
            detail: ex.Message,
            statusCode: 500,
            title: "Error processing message");
    }
});

/// <summary>
/// Create a new conversation.
/// </summary>
app.MapPost("/api/conversations", () =>
{
    return Results.Ok(new { conversationId = Guid.NewGuid().ToString(), createdAt = DateTime.UtcNow });
});

// Bot Framework messaging endpoint (for Teams / M365 Copilot)
app.MapPost("/api/messages", async (HttpContext context,
    Microsoft.Agents.Builder.IAgent agent,
    Microsoft.Agents.Builder.IChannelServiceClientFactory channelServiceClientFactory,
    ILogger<Program> logger) =>
{
    try
    {
        var adapter = context.RequestServices.GetRequiredService<Microsoft.Agents.Hosting.AspNetCore.CloudAdapter>();
        await adapter.ProcessAsync(context.Request, context.Response, agent);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error processing bot message");
        context.Response.StatusCode = 500;
        await context.Response.WriteAsync($"Error: {ex.Message}");
    }
});

app.Run();

// =============================================================================
// Request/Response Models
// =============================================================================

/// <summary>
/// Chat request model.
/// </summary>
public record ChatRequest
{
    /// <summary>
    /// The user's message.
    /// </summary>
    public string Message { get; init; } = string.Empty;

    /// <summary>
    /// Optional conversation ID for continuing a conversation.
    /// </summary>
    public string? ConversationId { get; init; }

    /// <summary>
    /// Optional user token for OBO flow (OneDrive access).
    /// </summary>
    public string? UserToken { get; init; }
}

/// <summary>
/// Chat response model.
/// </summary>
public record ChatResponse
{
    /// <summary>
    /// The agent's response message.
    /// </summary>
    public string Message { get; init; } = string.Empty;

    /// <summary>
    /// Conversation ID for continuing the conversation.
    /// </summary>
    public string ConversationId { get; init; } = string.Empty;

    /// <summary>
    /// Timestamp of the response.
    /// </summary>
    public DateTime Timestamp { get; init; }
}

/// <summary>
/// Sets Cloud_RoleName for Application Insights telemetry.
/// Enables filtering by component in multi-service scenarios.
/// </summary>
public class CloudRoleNameInitializer : Microsoft.ApplicationInsights.Extensibility.ITelemetryInitializer
{
    private readonly string _roleName;

    public CloudRoleNameInitializer(string roleName)
    {
        _roleName = roleName;
    }

    public void Initialize(Microsoft.ApplicationInsights.Channel.ITelemetry telemetry)
    {
        telemetry.Context.Cloud.RoleName = _roleName;
    }
}

