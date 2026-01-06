using Azure;
using Azure.AI.Agents.Persistent;
using Azure.Identity;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Configuration;
using FoundryPersistentAgent;

// ============================================================================
// MAF + Foundry Persistent Agent Hybrid Pattern
// Demonstrates: IChatClient wrapping Foundry for file search with MAF orchestration
// ============================================================================

// Load configuration
var configuration = new ConfigurationBuilder()
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
    .AddJsonFile("appsettings.Development.json", optional: true, reloadOnChange: true)
    .Build();

var projectEndpoint = configuration["Foundry-Project:Endpoint"] 
    ?? throw new InvalidOperationException("Foundry-Project:Endpoint not configured");
var modelDeploymentName = configuration["Foundry-Project:ModelDeployment"] 
    ?? throw new InvalidOperationException("Foundry-Project:ModelDeployment not configured");

Console.WriteLine("=== MAF + Foundry Persistent Agent Hybrid ===\n");

// Create the Persistent Agents Client (Foundry infrastructure)
PersistentAgentsClient foundryClient = new(projectEndpoint, new DefaultAzureCredential());

// ----------------------------------------------------------------------------
// Step 1: Upload a file to Foundry
// ----------------------------------------------------------------------------
Console.WriteLine("Step 1: Uploading document to Foundry...");

var documentPath = Path.Combine(AppContext.BaseDirectory, "docs", "product_manual.md");
if (!File.Exists(documentPath))
{
    Console.WriteLine($"  Document not found at {documentPath}");
    Console.WriteLine("  Creating sample document...");
    Directory.CreateDirectory(Path.GetDirectoryName(documentPath)!);
    File.WriteAllText(documentPath, GetSampleDocument());
}

PersistentAgentFileInfo uploadedFile = foundryClient.Files.UploadFile(
    filePath: documentPath,
    purpose: PersistentAgentFilePurpose.Agents);

Console.WriteLine($"  Uploaded: {uploadedFile.Filename} (ID: {uploadedFile.Id})");

// Track file IDs for citation replacement
Dictionary<string, string> fileIds = new()
{
    { uploadedFile.Id, uploadedFile.Filename }
};

// ----------------------------------------------------------------------------
// Step 2: Create a Vector Store and add the file
// ----------------------------------------------------------------------------
Console.WriteLine("\nStep 2: Creating Vector Store...");

PersistentAgentsVectorStore vectorStore = foundryClient.VectorStores.CreateVectorStore(
    name: "ProductDocumentation");

VectorStoreFile vectorStoreFile = foundryClient.VectorStores.CreateVectorStoreFile(
    vectorStoreId: vectorStore.Id,
    fileId: uploadedFile.Id);

Console.WriteLine($"  Vector Store created: {vectorStore.Name} (ID: {vectorStore.Id})");
Console.WriteLine($"  File added to Vector Store (Status: {vectorStoreFile.Status})");

// Wait for file processing
Console.Write("  Processing");
while (vectorStoreFile.Status == VectorStoreFileStatus.InProgress)
{
    Thread.Sleep(1000);
    Console.Write(".");
    vectorStoreFile = foundryClient.VectorStores.GetVectorStoreFile(vectorStore.Id, vectorStoreFile.Id);
}
Console.WriteLine($" Done ({vectorStoreFile.Status})");

// ----------------------------------------------------------------------------
// Step 3: Create an Agent with File Search tool
// ----------------------------------------------------------------------------
Console.WriteLine("\nStep 3: Creating Agent with File Search tool...");

FileSearchToolResource fileSearchToolResource = new();
fileSearchToolResource.VectorStoreIds.Add(vectorStore.Id);

PersistentAgent agent = foundryClient.Administration.CreateAgent(
    model: modelDeploymentName,
    name: "Product Documentation Assistant",
    instructions: """
        You are a helpful product documentation assistant. 
        Use the file search tool to find information from the uploaded product manuals.
        Always cite the source document when providing information.
        If information is not in the documents, say so clearly.
        """,
    tools: [new FileSearchToolDefinition()],
    toolResources: new ToolResources { FileSearch = fileSearchToolResource });

Console.WriteLine($"  Agent created: {agent.Name} (ID: {agent.Id})");

// ----------------------------------------------------------------------------
// Step 4: Create Thread and wrap with MAF IChatClient
// ----------------------------------------------------------------------------
Console.WriteLine("\nStep 4: Creating MAF-wrapped Foundry client...");

PersistentAgentThread thread = foundryClient.Threads.CreateThread();

// Create the MAF IChatClient wrapper around Foundry
IChatClient chatClient = new FoundryPersistentChatClient(
    client: foundryClient,
    agentId: agent.Id,
    threadId: thread.Id,
    fileIds: fileIds);

Console.WriteLine($"  Thread created (ID: {thread.Id})");
Console.WriteLine($"  IChatClient wrapper ready");

// ----------------------------------------------------------------------------
// Step 5: Use MAF patterns for conversation
// ----------------------------------------------------------------------------
Console.WriteLine("\nStep 5: Running conversation via MAF IChatClient...\n");

// Conversation questions
string[] questions = [
    "What is the SmartWidget Pro and what are its key features?",
    "How do I connect the device to WiFi?",
    "What should I do if the device won't turn on?"
];

// Use MAF IChatClient interface for the conversation
foreach (var question in questions)
{
    Console.WriteLine($"User: {question}");
    
    // Build chat messages (MAF pattern)
    var messages = new List<ChatMessage>
    {
        new(ChatRole.User, question)
    };
    
    // Call through MAF IChatClient abstraction
    var response = await chatClient.GetResponseAsync(messages);
    
    var responseText = response.Messages.FirstOrDefault()?.Text ?? "No response";
    Console.WriteLine($"Assistant: {responseText}");
    
    // Show usage if available
    if (response.Usage != null)
    {
        Console.WriteLine($"  [Tokens: {response.Usage.InputTokenCount} in, {response.Usage.OutputTokenCount} out]");
    }
    
    Console.WriteLine();
}

// ----------------------------------------------------------------------------
// Step 6: Cleanup resources
// ----------------------------------------------------------------------------
Console.WriteLine("Step 6: Cleaning up resources...");

chatClient.Dispose();
Console.WriteLine("  IChatClient disposed");

foundryClient.Threads.DeleteThread(thread.Id);
Console.WriteLine("  Thread deleted");

foundryClient.Administration.DeleteAgent(agent.Id);
Console.WriteLine("  Agent deleted");

foundryClient.VectorStores.DeleteVectorStore(vectorStore.Id);
Console.WriteLine("  Vector Store deleted");

foundryClient.Files.DeleteFile(uploadedFile.Id);
Console.WriteLine("  File deleted");

Console.WriteLine("\n=== Demo Complete ===");

// ============================================================================
// Helper Method - Sample Document
// ============================================================================

static string GetSampleDocument()
{
    return """
        # SmartWidget Pro - Product Manual

        ## Overview
        The SmartWidget Pro is an advanced IoT device designed for smart home automation. 
        It features WiFi connectivity, voice control integration, and energy monitoring capabilities.

        ## Key Features
        - **WiFi Connectivity**: 2.4GHz and 5GHz dual-band support
        - **Voice Control**: Compatible with Alexa, Google Assistant, and Siri
        - **Energy Monitoring**: Real-time power consumption tracking
        - **Mobile App**: iOS and Android companion apps available
        - **Scheduling**: Set automated on/off schedules
        - **Scenes**: Create custom automation scenes

        ## Getting Started

        ### What's in the Box
        1. SmartWidget Pro device
        2. Power adapter (5V/2A)
        3. Quick Start Guide
        4. Mounting hardware

        ### Initial Setup
        1. Plug in the SmartWidget Pro using the provided power adapter
        2. Wait for the LED to blink blue (ready for setup)
        3. Download the SmartWidget app from your app store
        4. Follow the in-app instructions to connect to your WiFi network

        ## WiFi Setup

        ### Connecting to WiFi
        1. Open the SmartWidget app
        2. Tap "Add Device" → "SmartWidget Pro"
        3. Ensure your phone is connected to your 2.4GHz WiFi network
        4. Enter your WiFi password when prompted
        5. Wait for the device LED to turn solid green (connected)

        ### Troubleshooting WiFi Connection
        - **LED blinking red**: WiFi password incorrect, try again
        - **LED blinking yellow**: Weak WiFi signal, move device closer to router
        - **LED off**: No power, check the power adapter connection

        ## Troubleshooting

        ### Device Won't Turn On
        1. Verify the power adapter is securely connected
        2. Try a different power outlet
        3. Check if the outlet has power using another device
        4. If using a power strip, ensure it's switched on
        5. Contact support if the issue persists

        ### Device Unresponsive
        1. Perform a soft reset by unplugging for 10 seconds
        2. Perform a factory reset by holding the button for 15 seconds
        3. Re-run the setup process after factory reset

        ## Technical Specifications
        - Input: 100-240V AC, 50/60Hz
        - Output: 5V DC, 2A
        - WiFi: 802.11 b/g/n/ac
        - Dimensions: 80mm x 80mm x 25mm
        - Weight: 120g

        ## Support
        - Email: support@smartwidget.example.com
        - Phone: 1-800-WIDGET
        - Website: https://smartwidget.example.com/support
        """;
}
