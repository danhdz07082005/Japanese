using CloudinaryDotNet;
using CloudinaryDotNet.Actions;

namespace JapaneseMasteryBackendDotNet.Services;

public class CloudinaryService
{
    private readonly Cloudinary _cloudinary;
    private readonly ILogger<CloudinaryService> _logger;

    public CloudinaryService(IConfiguration config, ILogger<CloudinaryService> logger)
    {
        _logger = logger;

        var cloudName = config["App:Cloudinary:CloudName"] ?? "dausrmshi";
        var apiKey = config["App:Cloudinary:ApiKey"] ?? "763543635139182";
        var apiSecret = config["App:Cloudinary:ApiSecret"] ?? "8PUSqJevPCZ25IbVjFFo-lC65FY";

        // Also check if .env file exists and has values
        try
        {
            var baseDir = Directory.GetCurrentDirectory();
            var dirInfo = new DirectoryInfo(baseDir);
            if (dirInfo.Name.Equals("JapaneseMasteryBackendDotNet", StringComparison.OrdinalIgnoreCase) ||
                dirInfo.Name.Equals("JapaneseMasteryBackend", StringComparison.OrdinalIgnoreCase))
            {
                baseDir = dirInfo.Parent?.FullName ?? baseDir;
            }

            var envPaths = new[]
            {
                Path.Combine(Directory.GetCurrentDirectory(), ".env"),
                Path.Combine(baseDir, "JapaneseMasteryBackend", ".env"),
                Path.Combine(baseDir, ".env")
            };

            foreach (var envPath in envPaths)
            {
                if (File.Exists(envPath))
                {
                    foreach (var line in File.ReadAllLines(envPath))
                    {
                        var trimmed = line.Trim();
                        if (trimmed.StartsWith('#') || !trimmed.Contains('=')) continue;
                        var parts = trimmed.Split('=', 2);
                        var key = parts[0].Trim();
                        var val = parts[1].Trim();
                        if (key == "CLOUDINARY_CLOUD_NAME") cloudName = val;
                        if (key == "CLOUDINARY_API_KEY") apiKey = val;
                        if (key == "CLOUDINARY_API_SECRET") apiSecret = val;
                    }
                    break;
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Could not load .env file for Cloudinary.");
        }

        var account = new Account(cloudName, apiKey, apiSecret);
        _cloudinary = new Cloudinary(account)
        {
            Api = { Secure = true }
        };
    }

    public async Task<(string? SecureUrl, string? PublicId)> UploadFileAsync(IFormFile file)
    {
        if (file == null || file.Length == 0) return (null, null);

        await using var stream = file.OpenReadStream();
        var ext = Path.GetExtension(file.FileName)?.ToLowerInvariant();
        bool isVideo = ext is ".mp4" or ".webm" or ".mov" or ".avi" or ".mkv" ||
                       (file.ContentType != null && file.ContentType.StartsWith("video/", StringComparison.OrdinalIgnoreCase));

        _logger.LogInformation("Uploading file {FileName} ({Length} bytes, isVideo: {IsVideo}) to Cloudinary...", file.FileName, file.Length, isVideo);

        if (isVideo)
        {
            var uploadParams = new VideoUploadParams
            {
                File = new FileDescription(file.FileName, stream),
                UseFilename = true,
                UniqueFilename = true,
                Overwrite = false
            };

            VideoUploadResult uploadResult;
            if (file.Length > 20_000_000)
            {
                uploadResult = await _cloudinary.UploadLargeAsync(uploadParams);
            }
            else
            {
                uploadResult = await _cloudinary.UploadAsync(uploadParams);
            }

            if (uploadResult.Error != null)
            {
                _logger.LogError("Cloudinary video upload failed: {Error}", uploadResult.Error.Message);
                throw new InvalidOperationException($"Cloudinary video upload failed: {uploadResult.Error.Message}");
            }

            _logger.LogInformation("Cloudinary video uploaded successfully! SecureUrl: {Url}", uploadResult.SecureUrl);
            return (uploadResult.SecureUrl?.ToString(), uploadResult.PublicId);
        }
        else
        {
            var uploadParams = new ImageUploadParams
            {
                File = new FileDescription(file.FileName, stream),
                UseFilename = true,
                UniqueFilename = true,
                Overwrite = false
            };

            ImageUploadResult uploadResult;
            if (file.Length > 20_000_000)
            {
                uploadResult = await _cloudinary.UploadLargeAsync(uploadParams);
            }
            else
            {
                uploadResult = await _cloudinary.UploadAsync(uploadParams);
            }

            if (uploadResult.Error != null)
            {
                _logger.LogError("Cloudinary image upload failed: {Error}", uploadResult.Error.Message);
                throw new InvalidOperationException($"Cloudinary image upload failed: {uploadResult.Error.Message}");
            }

            _logger.LogInformation("Cloudinary image uploaded successfully! SecureUrl: {Url}", uploadResult.SecureUrl);
            return (uploadResult.SecureUrl?.ToString(), uploadResult.PublicId);
        }
    }

    public string GenerateOptimizedUrl(string? publicId)
    {
        if (string.IsNullOrEmpty(publicId)) return string.Empty;

        return _cloudinary.Api.UrlImgUp
            .Transform(new Transformation().Quality("auto").FetchFormat("auto"))
            .BuildUrl(publicId);
    }
}
