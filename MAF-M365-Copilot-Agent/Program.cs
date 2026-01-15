// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

// Sample that shows how to create a Microsoft Agent Framework agent 
// that is hosted using the M365 Agents SDK for Teams and M365 Copilot channels.
// Uses Microsoft Foundry (Azure AI Foundry) as the AI provider.

using System;
using System.Threading;
using Azure.AI.OpenAI;
using Azure.Identity;
using M365CopilotAgent;
using M365CopilotAgent.Agents;
using Microsoft.Agents.AI;
using Microsoft.Agents.Builder;
using Microsoft.Agents.Hosting.AspNetCore;
using Microsoft.Agents.Storage;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

// Load user secrets in development
if (builder.Environment.IsDevelopment())
{
    builder.Configuration.AddUserSecrets<Program>();
}

builder.Services.AddHttpClient();

// Microsoft Foundry configuration
// Uses DefaultAzureCredential for authentication (supports Azure CLI, Managed Identity, etc.)
var projectEndpoint = builder.Configuration.GetSection("Foundry").GetValue<string>("ProjectEndpoint");
var modelDeployment = builder.Configuration.GetSection("Foundry").GetValue<string>("ModelDeployment");

if (string.IsNullOrEmpty(projectEndpoint))
{
    throw new InvalidOperationException(
        "Foundry:ProjectEndpoint is not configured. " +
        "Please set it in appsettings.json or appsettings.Development.json. " +
        "Example: https://your-project.services.ai.azure.com");
}

if (string.IsNullOrEmpty(modelDeployment))
{
    throw new InvalidOperationException(
        "Foundry:ModelDeployment is not configured. " +
        "Please set it in appsettings.json or appsettings.Development.json. " +
        "Example: gpt-4o-mini");
}

// Create chat client using Foundry project endpoint
// Foundry projects expose OpenAI-compatible endpoints
var chatClient = new AzureOpenAIClient(
    new Uri(projectEndpoint),
    new DefaultAzureCredential())
    .GetChatClient(modelDeployment)
    .AsIChatClient();

builder.Services.AddSingleton(chatClient);

// Add AgentApplicationOptions from appsettings section "AgentApplication"
builder.AddAgentApplicationOptions();

// Register the Microsoft Agent Framework AIAgent
builder.Services.AddSingleton<AIAgent, MyAIAgent>();

// Add optional welcome message for the agent
builder.Services.AddKeyedSingleton("MAFAgentApplicationWelcomeMessage", 
    "Hello! 👋 I'm your AI assistant powered by Microsoft Agent Framework. I can help you with various tasks including checking the weather, telling jokes, and answering questions. How can I help you today?");

// Add the MAFAgentApplication adapter, which bridges MAF to M365 Agents SDK
builder.AddAgent<MAFAgentApplication>();

// Register IStorage. For development, MemoryStorage is suitable.
// For production, use persisted storage so state survives restarts.
builder.Services.AddSingleton<IStorage, MemoryStorage>();

// Configure the HTTP request pipeline
builder.Services.AddControllers();
builder.Services.AddAgentAspNetAuthentication(builder.Configuration);

WebApplication app = builder.Build();

// Enable AspNet authentication and authorization
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/", () => "Microsoft Agent Framework + M365 Agents SDK Sample");

// This receives incoming messages from Azure Bot Service or other SDK Agents
var incomingRoute = app.MapPost("/api/messages", async (HttpRequest request, HttpResponse response, IAgentHttpAdapter adapter, IAgent agent, CancellationToken cancellationToken) =>
{
    await adapter.ProcessAsync(request, response, agent, cancellationToken);
});

if (!app.Environment.IsDevelopment())
{
    incomingRoute.RequireAuthorization();
}
else
{
    // Hardcoded for brevity and ease of testing
    app.Urls.Add($"http://localhost:3978");
}

app.Run();
