// Copyright (c) Microsoft. All rights reserved.

using System.Text.Json.Serialization;

namespace OneDriveAgent.Models;

/// <summary>
/// Utility for formatting byte sizes as human-readable strings.
/// </summary>
public static class SizeFormatter
{
    private static readonly string[] Sizes = ["B", "KB", "MB", "GB", "TB"];

    /// <summary>
    /// Format bytes as human-readable string (e.g., "1.5 MB").
    /// </summary>
    public static string Format(long bytes)
    {
        double len = bytes;
        var order = 0;
        while (len >= 1024 && order < Sizes.Length - 1)
        {
            order++;
            len /= 1024;
        }
        return $"{len:0.##} {Sizes[order]}";
    }
}

/// <summary>
/// Represents a file or folder in OneDrive.
/// </summary>
public class DriveItemInfo
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("size")]
    public long? Size { get; set; }

    [JsonPropertyName("isFolder")]
    public bool IsFolder { get; set; }

    [JsonPropertyName("webUrl")]
    public string? WebUrl { get; set; }

    [JsonPropertyName("createdDateTime")]
    public DateTimeOffset? CreatedDateTime { get; set; }

    [JsonPropertyName("lastModifiedDateTime")]
    public DateTimeOffset? LastModifiedDateTime { get; set; }

    /// <summary>
    /// Gets a human-readable size string.
    /// </summary>
    public string SizeDisplay => Size.HasValue ? SizeFormatter.Format(Size.Value) : "";
}

/// <summary>
/// OneDrive storage quota information.
/// </summary>
public class DriveQuotaInfo
{
    [JsonPropertyName("total")]
    public long Total { get; set; }

    [JsonPropertyName("used")]
    public long Used { get; set; }

    [JsonPropertyName("remaining")]
    public long Remaining { get; set; }

    [JsonPropertyName("ownerName")]
    public string OwnerName { get; set; } = string.Empty;

    /// <summary>
    /// Gets usage percentage.
    /// </summary>
    public double UsagePercent => Total > 0 ? (double)Used / Total * 100 : 0;
}

/// <summary>
/// Response for listing OneDrive files.
/// </summary>
public class ListFilesResult
{
    [JsonPropertyName("location")]
    public string Location { get; set; } = string.Empty;

    [JsonPropertyName("folders")]
    public List<DriveItemInfo> Folders { get; set; } = new();

    [JsonPropertyName("files")]
    public List<DriveItemInfo> Files { get; set; } = new();

    [JsonPropertyName("totalFolders")]
    public int TotalFolders => Folders.Count;

    [JsonPropertyName("totalFiles")]
    public int TotalFiles => Files.Count;

    [JsonPropertyName("error")]
    public string? Error { get; set; }
}
