// MAF Durable Agent running on Azure Functions
// Run locally with: func start
// Test with HTTP trigger or Agents Playground

using Azure.AI.OpenAI;
using Azure.Identity;
using MAFCopilotAgent;
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Hosting.AzureFunctions;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

// Get configuration from environment variables
var endpoint = Environment.GetEnvironmentVariable("AZURE_OPENAI_ENDPOINT")
    ?? throw new InvalidOperationException("AZURE_OPENAI_ENDPOINT environment variable is not set");
var deploymentName = Environment.GetEnvironmentVariable("AZURE_OPENAI_DEPLOYMENT") ?? "gpt-4o-mini";

// Get tools from the agent class (discovered via [Description] attributes)
var tools = WeatherAgent.GetTools();

// Create the underlying chat client with tools (for MAFAdapter direct invocation)
IChatClient chatClient = new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential())
    .GetChatClient(deploymentName)
    .AsIChatClient()
    .AsBuilder()
    .UseFunctionInvocation()
    .Build();

// Create the MAF Durable Agent with tools (for DTS-based invocation)
AIAgent agent = chatClient.CreateAIAgent(
    instructions: WeatherAgent.Instructions,
    name: "MAFDurableAgent",
    tools: tools);

// Build and run the Azure Functions host with Durable Agent
var builder = FunctionsApplication
    .CreateBuilder(args)
    .ConfigureFunctionsWebApplication()
    .ConfigureDurableAgents(options => options.AddAIAgent(agent));

// Register HttpClientFactory for MAFAdapter
builder.Services.AddHttpClient();

// Register Bot Framework authentication config
// When MicrosoftAppId is empty, authentication is disabled (local development)
var authConfig = new BotAuthConfig
{
    MicrosoftAppId = Environment.GetEnvironmentVariable("MicrosoftAppId"),
    MicrosoftAppPassword = Environment.GetEnvironmentVariable("MicrosoftAppPassword"),
    MicrosoftAppTenantId = Environment.GetEnvironmentVariable("MicrosoftAppTenantId")
};
builder.Services.AddSingleton(authConfig);

// Register IChatClient and tools for direct invocation from MAFAdapter (no HTTP)
builder.Services.AddSingleton(chatClient);
builder.Services.AddSingleton(tools);
builder.Services.AddSingleton(WeatherAgent.Instructions);

using IHost app = builder.Build();

app.Run();
