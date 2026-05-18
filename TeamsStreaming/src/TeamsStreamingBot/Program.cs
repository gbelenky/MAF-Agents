// Copyright (c) Microsoft. All rights reserved.

using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Agents.Builder;
using Microsoft.Agents.Hosting.AspNetCore;
using Microsoft.Extensions.AI;
using TeamsStreamingBot.Services;

var builder = WebApplication.CreateBuilder(args);

// Add Application Insights for telemetry - auto-reads APPLICATIONINSIGHTS_CONNECTION_STRING
builder.Services.AddApplicationInsightsTelemetry();

// Configure Azure OpenAI
var azureOpenAIEndpoint = Environment.GetEnvironmentVariable("AZURE_OPENAI_ENDPOINT") 
    ?? builder.Configuration["AzureOpenAI:Endpoint"]
    ?? throw new InvalidOperationException("AZURE_OPENAI_ENDPOINT is required");

var azureOpenAIDeployment = Environment.GetEnvironmentVariable("AZURE_OPENAI_DEPLOYMENT_NAME") 
    ?? builder.Configuration["AzureOpenAI:DeploymentName"]
    ?? "gpt-4o";

Console.WriteLine($"Azure OpenAI Endpoint: {azureOpenAIEndpoint}");
Console.WriteLine($"Azure OpenAI Deployment: {azureOpenAIDeployment}");

// Create the MAF Agent using the same pattern as AgentId project
var agent = new AzureOpenAIClient(
    new Uri(azureOpenAIEndpoint),
    new DefaultAzureCredential())
    .GetChatClient(azureOpenAIDeployment)
    .AsIChatClient()
    .AsBuilder()
    .UseFunctionInvocation()
    .Build()
    .AsAIAgent(
        name: "TeamsStreamingBot",
        instructions: """
            You are a helpful AI assistant integrated with Microsoft Teams.
            You provide clear, concise, and helpful responses.
            When appropriate, you can use markdown formatting in your responses.
            Be friendly and professional.
            """);

builder.Services.AddSingleton<AIAgent>(agent);

// Also register the streaming chat client for token-by-token streaming
var streamingChatClient = new AzureOpenAIClient(
    new Uri(azureOpenAIEndpoint),
    new DefaultAzureCredential())
    .GetChatClient(azureOpenAIDeployment)
    .AsIChatClient();
builder.Services.AddSingleton<IChatClient>(streamingChatClient);

builder.Services.AddHttpClient();

// Add the M365 Agents SDK bot
builder.AddAgent<StreamingBot>();

var app = builder.Build();

// Map endpoints
app.MapGet("/", () => "Teams Streaming Bot - Powered by Microsoft Agent Framework");
app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }));

// Bot Framework messaging endpoint (for Teams)
app.MapPost("/api/messages", async (HttpContext context,
    Microsoft.Agents.Builder.IAgent agent,
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

Console.WriteLine("Teams Streaming Bot is starting...");

app.Run();
