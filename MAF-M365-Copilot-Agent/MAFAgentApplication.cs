// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Agents.AI;
using Microsoft.Agents.Builder;
using Microsoft.Agents.Builder.App;
using Microsoft.Agents.Builder.State;
using Microsoft.Agents.Core.Models;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.DependencyInjection;

namespace M365CopilotAgent;

/// <summary>
/// An adapter class that exposes a Microsoft Agent Framework <see cref="AIAgent"/> as an M365 Agents SDK <see cref="AgentApplication"/>.
/// This enables MAF agents to be consumed from various M365 channels including Teams and M365 Copilot.
/// </summary>
public sealed class MAFAgentApplication : AgentApplication
{
    private readonly AIAgent _agent;
    private readonly string? _welcomeMessage;

    /// <summary>
    /// Initializes a new instance of the <see cref="MAFAgentApplication"/> class.
    /// </summary>
    /// <param name="agent">The Microsoft Agent Framework AIAgent to expose.</param>
    /// <param name="options">The M365 Agents SDK application options.</param>
    /// <param name="welcomeMessage">Optional welcome message for new conversations.</param>
    public MAFAgentApplication(
        AIAgent agent, 
        AgentApplicationOptions options, 
        [FromKeyedServices("MAFAgentApplicationWelcomeMessage")] string? welcomeMessage = null) 
        : base(options)
    {
        this._agent = agent;
        this._welcomeMessage = welcomeMessage;

        // Register handlers for conversation events
        this.OnConversationUpdate(ConversationUpdateEvents.MembersAdded, this.WelcomeMessageAsync);
        this.OnActivity(ActivityTypes.Message, this.MessageActivityAsync, rank: RouteRank.Last);
    }

    /// <summary>
    /// The main agent invocation method, where each user message triggers a call to the underlying <see cref="AIAgent"/>.
    /// </summary>
    private async Task MessageActivityAsync(ITurnContext turnContext, ITurnState turnState, CancellationToken cancellationToken)
    {
        // Start a streaming informative update
        await turnContext.StreamingResponse.QueueInformativeUpdateAsync("Thinking...", cancellationToken);

        // Get user message
        string userMessage = turnContext.Activity.Text ?? string.Empty;

        // Invoke the MAF Agent to process the message  
        // Using simple string overload which creates a new thread automatically
        var agentResponse = await this._agent.RunAsync(userMessage, cancellationToken: cancellationToken);

        // Process the response and send back to the user
        foreach (ChatMessage message in agentResponse.Messages)
        {
            foreach (AIContent content in message.Contents)
            {
                if (content is TextContent textContent && !string.IsNullOrEmpty(textContent.Text))
                {
                    turnContext.StreamingResponse.QueueTextChunk(textContent.Text);
                }
            }
        }

        await turnContext.StreamingResponse.EndStreamAsync(cancellationToken);
    }

    /// <summary>
    /// A method to show a welcome message when a new user joins the conversation.
    /// </summary>
    private async Task WelcomeMessageAsync(ITurnContext turnContext, ITurnState turnState, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(this._welcomeMessage))
        {
            return;
        }

        foreach (ChannelAccount member in turnContext.Activity.MembersAdded)
        {
            if (member.Id != turnContext.Activity.Recipient.Id)
            {
                await turnContext.SendActivityAsync(MessageFactory.Text(this._welcomeMessage), cancellationToken);
            }
        }
    }
}
