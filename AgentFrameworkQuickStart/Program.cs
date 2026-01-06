using System.ComponentModel;
using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Configuration;

var configuration = new ConfigurationBuilder()
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", optional: false)
    .AddJsonFile("appsettings.Development.json", optional: true)
    .Build();

var endpoint = configuration["Foundry-Resource:Endpoint"] 
    ?? throw new InvalidOperationException("Foundry-Resource:Endpoint is not configured in appsettings.");

AIAgent agent = new AzureOpenAIClient(
  new Uri(endpoint),
  new DefaultAzureCredential())
    .GetChatClient("gpt-4.1-mini")
    .AsIChatClient()
    .CreateAIAgent(
        instructions: "You are good at telling jokes. Use available tools when relevant.",
        tools: [AIFunctionFactory.Create(GetWeather)]);

Console.WriteLine(await agent.RunAsync("Tell me a joke about a pirate."));
Console.WriteLine(await agent.RunAsync("What's the weather like in Seattle?"));

// Custom tool function
[Description("Get the weather for a given location.")]
static string GetWeather([Description("The location to get the weather for.")] string location)
{
    Random rand = new();
    string[] conditions = ["sunny", "cloudy", "rainy", "stormy"];
    return $"The weather in {location} is {conditions[rand.Next(0, 4)]} with a high of {rand.Next(10, 30)}°C.";
}