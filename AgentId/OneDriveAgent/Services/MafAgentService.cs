using System.ComponentModel;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Options;
using OneDriveAgent.Models;

namespace OneDriveAgent.Services;

/// <summary>
/// Configuration for the MAF Agent service.
/// </summary>
public class MafAgentConfig
{
    public string FoundryEndpoint { get; set; } = string.Empty;
    public string ModelDeploymentName { get; set; } = "gpt-4.1-mini";
}

/// <summary>
/// Interface for the MAF-based OneDrive Agent service.
/// </summary>
public interface IMafAgentService
{
    Task<string> ChatAsync(string message, string? userToken, CancellationToken cancellationToken = default);
}

/// <summary>
/// OneDrive Agent using Microsoft Agent Framework with function tools.
/// Uses AIFunctionFactory.Create() pattern for tool definition.
/// </summary>
public class MafAgentService : IMafAgentService
{
    private readonly MafAgentConfig _config;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<MafAgentService> _logger;
    private readonly Lazy<AIAgent> _lazyAgent;
    
    // Thread-local storage for current request's context
    private static readonly AsyncLocal<RequestContext?> _currentContext = new();

    private const string GraphApiBase = "https://graph.microsoft.com/v1.0";

    private const string SystemInstructions = """
        You are an OneDrive assistant that helps users manage and explore their files.

        You can:
        - List files in any folder in the user's OneDrive
        - Search for files by name or content  
        - Show drive storage information

        Always be helpful and provide clear, organized responses. When listing files, format them nicely.
        If an operation fails, explain what happened and suggest alternatives.

        Note: You access the user's OneDrive on their behalf using delegated permissions.
        """;

    public MafAgentService(
        IOptions<MafAgentConfig> config,
        IHttpClientFactory httpClientFactory,
        ILogger<MafAgentService> logger)
    {
        _config = config.Value;
        _httpClientFactory = httpClientFactory;
        _logger = logger;
        _lazyAgent = new Lazy<AIAgent>(CreateAgent);
    }

    public async Task<string> ChatAsync(string message, string? userToken, CancellationToken cancellationToken = default)
    {
        // Store context for tool access
        _currentContext.Value = new RequestContext(userToken, _httpClientFactory);
        
        try
        {
            _logger.LogInformation("Processing chat message: {Message}", message);
            
            var response = await _lazyAgent.Value.RunAsync(message, cancellationToken: cancellationToken);
            
            return response?.ToString() ?? "I couldn't process your request.";
        }
        finally
        {
            _currentContext.Value = null;
        }
    }

    private AIAgent CreateAgent()
    {
        _logger.LogInformation("Creating MAF Agent with endpoint: {Endpoint}, model: {Model}",
            _config.FoundryEndpoint, _config.ModelDeploymentName);

        return new AzureOpenAIClient(
            new Uri(_config.FoundryEndpoint),
            new DefaultAzureCredential())
            .GetChatClient(_config.ModelDeploymentName)
            .AsIChatClient()
            .AsBuilder()
            .UseFunctionInvocation()
            .Build()
            .AsAIAgent(
                name: "OneDriveAgent",
                instructions: SystemInstructions,
                tools: [
                    AIFunctionFactory.Create(ListFilesToolAsync),
                    AIFunctionFactory.Create(GetDriveInfoToolAsync),
                    AIFunctionFactory.Create(SearchFilesToolAsync)
                ]);
    }

    // ==========================================================================
    // Tool Functions - Static methods called by the agent via function calling
    // ==========================================================================

    /// <summary>
    /// Gets an authenticated HttpClient, or returns an error message if no token is available.
    /// </summary>
    private static (HttpClient? client, string? error) GetAuthenticatedClient()
    {
        var context = _currentContext.Value;
        if (context?.UserToken == null)
        {
            return (null, "Error: No user token available. Please authenticate first.");
        }
        
        var httpClient = context.HttpClientFactory.CreateClient();
        httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", context.UserToken);
        return (httpClient, null);
    }

    [Description("List files in the user's OneDrive. Can optionally filter by folder path.")]
    private static async Task<string> ListFilesToolAsync(
        [Description("Optional folder path to list files from. Use empty string for root, or specify a path like 'Documents'. If not provided, lists files in the root folder.")] 
        string? folderPath = null)
    {
        var (httpClient, error) = GetAuthenticatedClient();
        if (httpClient == null) return error!;

        try
        {
            var url = string.IsNullOrEmpty(folderPath) || folderPath == "/"
                ? $"{GraphApiBase}/me/drive/root/children?$top=50"
                : $"{GraphApiBase}/me/drive/root:/{folderPath}:/children?$top=50";

            var response = await httpClient.GetAsync(url);
            
            if (!response.IsSuccessStatusCode)
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                return $"Error listing files: {response.StatusCode} - {errorContent}";
            }

            var content = await response.Content.ReadAsStringAsync();
            var json = JsonDocument.Parse(content);
            
            var result = new StringBuilder();
            result.AppendLine($"Files in {folderPath ?? "root"}:");
            result.AppendLine();

            if (json.RootElement.TryGetProperty("value", out var items))
            {
                foreach (var item in items.EnumerateArray())
                {
                    var name = item.GetProperty("name").GetString();
                    var isFolder = item.TryGetProperty("folder", out _);
                    var icon = isFolder ? "[Folder]" : "[File]";
                    
                    var sizeStr = "";
                    if (!isFolder && item.TryGetProperty("size", out var size))
                    {
                        sizeStr = $" ({SizeFormatter.Format(size.GetInt64())})";
                    }
                    
                    result.AppendLine($"  {icon} {name}{sizeStr}");
                }
            }

            return result.ToString();
        }
        catch (Exception ex)
        {
            return $"Error listing files: {ex.Message}";
        }
    }

    [Description("Get information about the user's OneDrive, including total storage, used storage, and remaining storage.")]
    private static async Task<string> GetDriveInfoToolAsync()
    {
        var (httpClient, error) = GetAuthenticatedClient();
        if (httpClient == null) return error!;

        try
        {
            var response = await httpClient.GetAsync($"{GraphApiBase}/me/drive");
            
            if (!response.IsSuccessStatusCode)
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                return $"Error getting drive info: {response.StatusCode} - {errorContent}";
            }

            var content = await response.Content.ReadAsStringAsync();
            var json = JsonDocument.Parse(content);
            
            if (json.RootElement.TryGetProperty("quota", out var quota))
            {
                var total = quota.GetProperty("total").GetInt64();
                var used = quota.GetProperty("used").GetInt64();
                var remaining = quota.GetProperty("remaining").GetInt64();
                var state = quota.TryGetProperty("state", out var s) ? s.GetString() : "unknown";

                return $"""
                    OneDrive Storage Information:
                      Total: {SizeFormatter.Format(total)}
                      Used: {SizeFormatter.Format(used)} ({(double)used / total * 100:F1}%)
                      Remaining: {SizeFormatter.Format(remaining)}
                      State: {state}
                    """;
            }

            return "Unable to retrieve drive quota information.";
        }
        catch (Exception ex)
        {
            return $"Error getting drive info: {ex.Message}";
        }
    }

    [Description("Search for files in the user's OneDrive by name or content.")]
    private static async Task<string> SearchFilesToolAsync(
        [Description("The search query to find files. Can search by filename or content.")] 
        string query)
    {
        var (httpClient, error) = GetAuthenticatedClient();
        if (httpClient == null) return error!;

        try
        {
            var response = await httpClient.GetAsync($"{GraphApiBase}/me/drive/root/search(q='{Uri.EscapeDataString(query)}')?$top=20");
            
            if (!response.IsSuccessStatusCode)
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                return $"Error searching files: {response.StatusCode} - {errorContent}";
            }

            var content = await response.Content.ReadAsStringAsync();
            var json = JsonDocument.Parse(content);
            
            var result = new StringBuilder();
            result.AppendLine($"Search results for '{query}':");
            result.AppendLine();

            if (json.RootElement.TryGetProperty("value", out var items))
            {
                var count = 0;
                foreach (var item in items.EnumerateArray())
                {
                    count++;
                    var name = item.GetProperty("name").GetString();
                    var isFolder = item.TryGetProperty("folder", out _);
                    var icon = isFolder ? "[Folder]" : "[File]";
                    
                    result.AppendLine($"  {icon} {name}");
                    
                    if (item.TryGetProperty("parentReference", out var parent) && 
                        parent.TryGetProperty("path", out var path))
                    {
                        var pathStr = path.GetString()?.Replace("/drive/root:", "") ?? "";
                        if (!string.IsNullOrEmpty(pathStr))
                        {
                            result.AppendLine($"      Location: {pathStr}");
                        }
                    }
                }
                
                if (count == 0)
                {
                    return $"No files found matching '{query}'";
                }
            }

            return result.ToString();
        }
        catch (Exception ex)
        {
            return $"Error searching files: {ex.Message}";
        }
    }

    // ==========================================================================
    // Helper Types
    // ==========================================================================

    /// <summary>
    /// Context holder for async-local access in tool functions.
    /// </summary>
    private record RequestContext(
        string? UserToken, 
        IHttpClientFactory HttpClientFactory);
}
