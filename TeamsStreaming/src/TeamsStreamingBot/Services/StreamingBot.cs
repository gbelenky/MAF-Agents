using Microsoft.Agents.AI;
using Microsoft.Agents.Builder;
using Microsoft.Agents.Builder.Compat;
using Microsoft.Agents.Core.Models;
using Microsoft.Extensions.AI;

namespace TeamsStreamingBot.Services;

/// <summary>
/// Bot that handles messages from Teams with streaming support.
/// Uses Microsoft Agent Framework for AI responses.
/// </summary>
public class StreamingBot : ActivityHandler
{
    private readonly AIAgent _agent;
    private readonly IChatClient _chatClient;
    private readonly ILogger<StreamingBot> _logger;

    private const string SystemPrompt = """
        You are a helpful AI assistant integrated with Microsoft Teams.
        You provide clear, concise, and helpful responses.
        When appropriate, you can use markdown formatting in your responses.
        Be friendly and professional.
        
        IMPORTANT: Before providing your answer, briefly explain your reasoning process.
        Format your response as:
        
        **Reasoning:** [Your thought process here]
        
        **Answer:** [Your actual response here]
        """;

    public StreamingBot(
        AIAgent agent,
        IChatClient chatClient,
        ILogger<StreamingBot> logger)
    {
        _agent = agent;
        _chatClient = chatClient;
        _logger = logger;
    }

    /// <summary>
    /// Handle incoming messages from Teams with streaming response.
    /// </summary>
    protected override async Task OnMessageActivityAsync(ITurnContext<IMessageActivity> turnContext, CancellationToken cancellationToken)
    {
        var userMessage = turnContext.Activity.Text?.Trim();
        
        if (string.IsNullOrWhiteSpace(userMessage))
        {
            await turnContext.SendActivityAsync(MessageFactory.Text("Please send a message."), cancellationToken);
            return;
        }

        _logger.LogInformation("Received message: {Message}", userMessage);

        try
        {
            // Show typing indicator while processing
            await turnContext.SendActivityAsync(new Activity { Type = ActivityTypes.Typing }, cancellationToken);

            // Start streaming response with informative updates
            await turnContext.StreamingResponse.QueueInformativeUpdateAsync("Thinking...", cancellationToken);
            
            // Build the chat messages with system prompt for reasoning
            var messages = new List<ChatMessage>
            {
                new ChatMessage(ChatRole.System, SystemPrompt),
                new ChatMessage(ChatRole.User, userMessage)
            };

            // Stream the response token by token
            await turnContext.StreamingResponse.QueueInformativeUpdateAsync("Generating response...", cancellationToken);
            
            var responseBuilder = new System.Text.StringBuilder();
            await foreach (var update in _chatClient.GetStreamingResponseAsync(messages, cancellationToken: cancellationToken))
            {
                // Get the text content from this streaming chunk
                var text = update.Text;
                if (!string.IsNullOrEmpty(text))
                {
                    responseBuilder.Append(text);
                    // Queue each chunk for streaming to Teams
                    turnContext.StreamingResponse.QueueTextChunk(text);
                }
            }

            // End the streaming response
            await turnContext.StreamingResponse.EndStreamAsync(cancellationToken);
            
            var responseText = responseBuilder.ToString();

            _logger.LogInformation("Sent response: {ResponseLength} chars", responseText.Length);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing message");
            
            // Send error message
            turnContext.StreamingResponse.QueueTextChunk($"Sorry, I encountered an error: {ex.Message}");
            await turnContext.StreamingResponse.EndStreamAsync(cancellationToken);
        }
    }

    /// <summary>
    /// Handle members being added to the conversation.
    /// </summary>
    protected override async Task OnMembersAddedAsync(IList<ChannelAccount> membersAdded, ITurnContext<IConversationUpdateActivity> turnContext, CancellationToken cancellationToken)
    {
        foreach (var member in membersAdded)
        {
            // Send welcome message to new members (but not the bot itself)
            if (member.Id != turnContext.Activity.Recipient.Id)
            {
                await turnContext.SendActivityAsync(
                    MessageFactory.Text("Hello! I'm a Teams streaming bot powered by Microsoft Agent Framework. Ask me anything!"),
                    cancellationToken);
            }
        }
    }
}
