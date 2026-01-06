using Azure.AI.Agents.Persistent;
using Microsoft.Extensions.AI;

namespace FoundryPersistentAgent;

/// <summary>
/// An IChatClient implementation that wraps Azure AI Foundry's PersistentAgentsClient.
/// This enables using MAF orchestration patterns while leveraging Foundry's server-side
/// capabilities (file storage, vector stores, built-in tools like File Search).
/// </summary>
public class FoundryPersistentChatClient : IChatClient
{
    private readonly PersistentAgentsClient _client;
    private readonly string _agentId;
    private readonly string _threadId;
    private readonly Dictionary<string, string> _fileIds;

    /// <summary>
    /// Creates a new FoundryPersistentChatClient that delegates to an existing Foundry agent and thread.
    /// </summary>
    /// <param name="client">The PersistentAgentsClient connected to your Foundry project</param>
    /// <param name="agentId">The ID of the persistent agent to use</param>
    /// <param name="threadId">The ID of the conversation thread</param>
    /// <param name="fileIds">Optional mapping of file IDs to filenames for citation formatting</param>
    public FoundryPersistentChatClient(
        PersistentAgentsClient client,
        string agentId,
        string threadId,
        Dictionary<string, string>? fileIds = null)
    {
        _client = client ?? throw new ArgumentNullException(nameof(client));
        _agentId = agentId ?? throw new ArgumentNullException(nameof(agentId));
        _threadId = threadId ?? throw new ArgumentNullException(nameof(threadId));
        _fileIds = fileIds ?? new Dictionary<string, string>();
    }

    /// <summary>
    /// Gets metadata about this chat client.
    /// </summary>
    public ChatClientMetadata Metadata => new("FoundryPersistentAgent", new Uri("https://ai.azure.com"));

    /// <summary>
    /// Sends a message to the Foundry persistent agent and returns the response.
    /// </summary>
    public async Task<ChatResponse> GetResponseAsync(
        IEnumerable<ChatMessage> chatMessages,
        ChatOptions? options = null,
        CancellationToken cancellationToken = default)
    {
        // Get the last user message to send to Foundry
        var lastUserMessage = chatMessages.LastOrDefault(m => m.Role == ChatRole.User);
        if (lastUserMessage == null)
        {
            return new ChatResponse(new ChatMessage(ChatRole.Assistant, "No user message provided."));
        }

        var userText = lastUserMessage.Text ?? string.Empty;

        // Create message in Foundry thread
        _client.Messages.CreateMessage(
            _threadId,
            MessageRole.User,
            userText);

        // Run the agent (use CreateRun with threadId and agentId)
        ThreadRun run = _client.Runs.CreateRun(
            threadId: _threadId,
            assistantId: _agentId);

        // Wait for completion (with cancellation support)
        while (run.Status == RunStatus.Queued || run.Status == RunStatus.InProgress)
        {
            await Task.Delay(500, cancellationToken);
            run = _client.Runs.GetRun(_threadId, run.Id);
        }

        // Check for failures
        if (run.Status == RunStatus.Failed)
        {
            var errorMessage = run.LastError?.Message ?? "Unknown error occurred";
            return new ChatResponse(new ChatMessage(ChatRole.Assistant, $"Agent run failed: {errorMessage}"));
        }

        // Get the assistant's response
        var messages = _client.Messages.GetMessages(
            threadId: _threadId,
            order: ListSortOrder.Descending);

        var assistantMessage = messages.FirstOrDefault(m => m.Role == MessageRole.Agent);
        
        if (assistantMessage == null)
        {
            return new ChatResponse(new ChatMessage(ChatRole.Assistant, "No response from agent."));
        }

        // Extract text content with citation handling
        var responseText = ExtractMessageContent(assistantMessage);

        var response = new ChatResponse(new ChatMessage(ChatRole.Assistant, responseText))
        {
            ResponseId = run.Id,
            CreatedAt = assistantMessage.CreatedAt,
            ModelId = run.Model
        };

        // Add usage information if available
        if (run.Usage != null)
        {
            response.Usage = new UsageDetails
            {
                InputTokenCount = run.Usage.PromptTokens,
                OutputTokenCount = run.Usage.CompletionTokens,
                TotalTokenCount = run.Usage.TotalTokens
            };
        }

        return response;
    }

    /// <summary>
    /// Streams responses from the Foundry persistent agent.
    /// Note: Currently implemented as a single response since Foundry runs are polled.
    /// </summary>
    public async IAsyncEnumerable<ChatResponseUpdate> GetStreamingResponseAsync(
        IEnumerable<ChatMessage> chatMessages,
        ChatOptions? options = null,
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        // Foundry persistent agents use a run-and-poll model, so we simulate streaming
        // by returning the complete response as a single update
        var response = await GetResponseAsync(chatMessages, options, cancellationToken);
        
        var responseText = response.Messages.FirstOrDefault()?.Text ?? string.Empty;
        
        var update = new ChatResponseUpdate
        {
            ResponseId = response.ResponseId,
            CreatedAt = response.CreatedAt,
            Role = ChatRole.Assistant,
            Contents = [new TextContent(responseText)]
        };

        yield return update;
    }

    /// <summary>
    /// Gets any services provided by this client.
    /// </summary>
    public object? GetService(Type serviceType, object? key = null)
    {
        if (serviceType == typeof(PersistentAgentsClient))
        {
            return _client;
        }
        return null;
    }

    /// <summary>
    /// Disposes the client. The underlying PersistentAgentsClient is not disposed
    /// as it may be shared.
    /// </summary>
    public void Dispose()
    {
        // PersistentAgentsClient lifecycle is managed externally
    }

    /// <summary>
    /// Extracts text content from a Foundry message, handling citations.
    /// </summary>
    private string ExtractMessageContent(PersistentThreadMessage message)
    {
        var textParts = new List<string>();

        foreach (MessageContent content in message.ContentItems)
        {
            if (content is MessageTextContent textContent)
            {
                string text = textContent.Text;

                // Replace file citations with readable names
                foreach (var annotation in textContent.Annotations)
                {
                    if (annotation is MessageTextFileCitationAnnotation citation)
                    {
                        if (_fileIds.TryGetValue(citation.FileId, out var fileName))
                            text = text.Replace(citation.Text, $" [{fileName}]");
                        else
                            text = text.Replace(citation.Text, $" [doc]");
                    }
                }

                textParts.Add(text);
            }
            else if (content is MessageImageFileContent imageContent)
            {
                textParts.Add($"[Image: {imageContent.FileId}]");
            }
        }

        return string.Join("\n", textParts);
    }
}
