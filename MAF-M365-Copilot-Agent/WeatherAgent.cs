using System.ComponentModel;
using Microsoft.Extensions.AI;

namespace MAFCopilotAgent;

/// <summary>
/// Agent with tools defined as decorated methods.
/// Tools are automatically discovered via reflection.
/// </summary>
public class WeatherAgent
{
    public const string Instructions = """
        You are a helpful AI assistant powered by Microsoft Agent Framework.
        You can help users with various tasks including checking the weather and current time.
        Be friendly and concise in your responses.
        """;

    [Description("Gets the current weather for a location.")]
    public static string GetWeather(
        [Description("The city name, e.g. 'Seattle', 'New York', 'London'")] string location) 
        => location.ToLowerInvariant() switch
    {
        "seattle" => "🌧️ Seattle: 52°F (11°C), Rainy with clouds",
        "new york" => "☀️ New York: 68°F (20°C), Sunny and clear",
        "london" => "🌫️ London: 55°F (13°C), Foggy with light drizzle",
        "tokyo" => "🌸 Tokyo: 72°F (22°C), Partly cloudy",
        "paris" => "⛅ Paris: 63°F (17°C), Partly sunny",
        "sydney" => "☀️ Sydney: 77°F (25°C), Warm and sunny",
        _ => $"🌡️ {location}: 65°F (18°C), Typical weather conditions"
    };

    [Description("Gets the current date and time.")]
    public static string GetCurrentTime() 
        => $"🕐 Current time: {DateTime.Now:dddd, MMMM d, yyyy h:mm:ss tt}";

    /// <summary>
    /// Discovers all methods with [Description] attribute and creates AIFunction tools.
    /// </summary>
    public static AIFunction[] GetTools() =>
    [
        AIFunctionFactory.Create(GetWeather),
        AIFunctionFactory.Create(GetCurrentTime)
    ];
}
