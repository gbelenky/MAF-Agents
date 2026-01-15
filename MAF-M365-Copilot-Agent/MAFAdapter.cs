using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;

namespace MAFCopilotAgent;

/// <summary>
/// MAF Adapter - bridges Bot Framework/Agents Playground protocol to MAF AIAgent.
/// Exposes /api/messages endpoint and invokes the IChatClient directly (no HTTP).
/// Uses proactive messaging to send replies back to serviceUrl.
/// </summary>
public class MAFAdapter
{
    private readonly ILogger<MAFAdapter> _logger;
    private readonly HttpClient _httpClient;
    private readonly IChatClient _chatClient;
    private readonly AIFunction[] _tools;
    private readonly string _systemInstructions;

    public MAFAdapter(
        ILogger<MAFAdapter> logger, 
        IHttpClientFactory httpClientFactory, 
        IChatClient chatClient,
        AIFunction[] tools,
        string systemInstructions)
    {
        _logger = logger;
        _httpClient = httpClientFactory.CreateClient();
        _chatClient = chatClient;
        _tools = tools;
        _systemInstructions = systemInstructions;
    }

    [Function("Messages")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "messages")] HttpRequestData req)
    {
        _logger.LogInformation("Received message at /api/messages");

        // Parse the Bot Framework activity
        var requestBody = await req.ReadAsStringAsync();
        var activity = JsonSerializer.Deserialize<BotActivity>(requestBody ?? "", new JsonSerializerOptions 
        { 
            PropertyNameCaseInsensitive = true 
        });

        if (activity == null)
        {
            var badResponse = req.CreateResponse(HttpStatusCode.BadRequest);
            await badResponse.WriteStringAsync("Invalid activity");
            return badResponse;
        }

        _logger.LogInformation("Activity type: {Type}, Text: {Text}, ServiceUrl: {ServiceUrl}", 
            activity.Type, activity.Text, activity.ServiceUrl);

        // Handle message activities
        if (activity.Type == "message" && !string.IsNullOrEmpty(activity.Text))
        {
            var conversationId = activity.Conversation?.Id ?? Guid.NewGuid().ToString();

            try
            {
                _logger.LogInformation("Invoking IChatClient directly for conversation {ConversationId}", conversationId);

                // Build chat messages with system instructions
                var messages = new List<ChatMessage>
                {
                    new ChatMessage(ChatRole.System, _systemInstructions),
                    new ChatMessage(ChatRole.User, activity.Text)
                };

                // Create chat options with tools
                var options = new ChatOptions
                {
                    Tools = _tools.Cast<AITool>().ToList()
                };

                // Call the IChatClient directly (no HTTP round-trip)
                var response = await _chatClient.GetResponseAsync(messages, options);
                var responseText = response.Text ?? "No response from agent";
                
                _logger.LogInformation("IChatClient response: {Response}", responseText);

                // Send reply back to serviceUrl (proactive messaging)
                await SendReplyToServiceUrl(activity, responseText);

                // Return 200 OK to acknowledge receipt
                return req.CreateResponse(HttpStatusCode.OK);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing message");
                await SendReplyToServiceUrl(activity, $"Sorry, an error occurred: {ex.Message}");
                return req.CreateResponse(HttpStatusCode.OK);
            }
        }

        // For conversationUpdate - send welcome message
        if (activity.Type == "conversationUpdate" && activity.MembersAdded != null)
        {
            // Check if bot was added (not user)
            foreach (var member in activity.MembersAdded)
            {
                if (member.Id != activity.Recipient?.Id)
                {
                    await SendReplyToServiceUrl(activity, 
                        "Hello! 👋 I'm your AI assistant powered by Microsoft Agent Framework with Durable Task Scheduler. How can I help you today?");
                    break;
                }
            }
        }

        // Return 200 OK for all activities
        return req.CreateResponse(HttpStatusCode.OK);
    }

    private async Task SendReplyToServiceUrl(BotActivity activity, string text)
    {
        if (string.IsNullOrEmpty(activity.ServiceUrl) || activity.Conversation == null)
        {
            _logger.LogWarning("Cannot send reply - missing serviceUrl or conversation");
            return;
        }

        var replyActivity = new
        {
            type = "message",
            text = text,
            from = new { id = activity.Recipient?.Id ?? "bot", name = "MAF Durable Agent" },
            conversation = new { id = activity.Conversation.Id },
            recipient = new { id = activity.From?.Id, name = activity.From?.Name },
            replyToId = activity.Id
        };

        // Build the reply URL: serviceUrl + /v3/conversations/{conversationId}/activities
        var replyUrl = $"{activity.ServiceUrl.TrimEnd('/')}/v3/conversations/{activity.Conversation.Id}/activities";
        
        _logger.LogInformation("Sending reply to: {ReplyUrl}", replyUrl);

        try
        {
            var response = await _httpClient.PostAsJsonAsync(replyUrl, replyActivity);
            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation("Reply sent successfully");
            }
            else
            {
                var error = await response.Content.ReadAsStringAsync();
                _logger.LogError("Failed to send reply: {StatusCode} - {Error}", response.StatusCode, error);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Exception sending reply to serviceUrl");
        }
    }
}

// Bot Framework activity models
public class BotActivity
{
    public string? Type { get; set; }
    public string? Id { get; set; }
    public string? Text { get; set; }
    public string? ServiceUrl { get; set; }
    public ChannelAccount? From { get; set; }
    public ChannelAccount? Recipient { get; set; }
    public ConversationAccount? Conversation { get; set; }
    public string? ReplyToId { get; set; }
    public List<ChannelAccount>? MembersAdded { get; set; }
}

public class ChannelAccount
{
    public string? Id { get; set; }
    public string? Name { get; set; }
}

public class ConversationAccount
{
    public string? Id { get; set; }
}
