// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System;
using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Serialization;
using AdaptiveCards;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;

namespace M365CopilotAgent.Agents;

/// <summary>
/// A sample AI Agent built with Microsoft Agent Framework.
/// This agent demonstrates tool calling and structured responses.
/// </summary>
public class MyAIAgent : DelegatingAIAgent
{
    private const string AgentName = "MyAIAgent";
    private const string AgentInstructions = """
        You are a friendly and helpful AI assistant.
        You can help users with various tasks and answer questions.
        When providing information, be concise but thorough.
        You have access to tools that can help you get real-time information.
        
        When answering with information that includes data from tools, structure your response clearly.
        Be conversational and engaging while remaining professional.
        """;

    /// <summary>
    /// Initializes a new instance of the <see cref="MyAIAgent"/> class.
    /// </summary>
    /// <param name="chatClient">An instance of <see cref="IChatClient"/> for interacting with an LLM.</param>
    public MyAIAgent(IChatClient chatClient)
        : base(new ChatClientAgent(
            chatClient: chatClient,
            new ChatClientAgentOptions()
            {
                Name = AgentName,
                ChatOptions = new ChatOptions()
                {
                    Instructions = AgentInstructions,
                    Tools = [
                        AIFunctionFactory.Create(GetWeather),
                        AIFunctionFactory.Create(GetCurrentTime)
                    ],
                }
            }))
    {
    }

    /// <summary>
    /// Get the weather for a given location.
    /// </summary>
    [Description("Get the current weather for a given location.")]
    private static string GetWeather([Description("The city or location to get the weather for.")] string location)
    {
        // Mock implementation - replace with real weather API call
        var conditions = new[] { "sunny", "cloudy", "partly cloudy", "rainy", "windy" };
        var condition = conditions[new Random().Next(conditions.Length)];
        var temperature = new Random().Next(10, 30);
        return $"The weather in {location} is {condition} with a temperature of {temperature}°C.";
    }

    /// <summary>
    /// Get the current date and time.
    /// </summary>
    [Description("Get the current date and time.")]
    private static string GetCurrentTime()
    {
        return $"The current date and time is {DateTime.Now:f}.";
    }
}
