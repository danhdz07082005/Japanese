using System.Security.Claims;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using JapaneseMasteryBackendDotNet.Data;
using JapaneseMasteryBackendDotNet.Logging;
using JapaneseMasteryBackendDotNet.Realtime;
using JapaneseMasteryBackendDotNet.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

// 1. Configure Kestrel port and body limits
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(8080);
    options.Limits.MaxRequestBodySize = 104_857_600; // 100MB
});

builder.Services.Configure<KestrelServerOptions>(options =>
{
    options.Limits.MaxRequestBodySize = 104_857_600;
});

builder.Services.Configure<FormOptions>(options =>
{
    options.MultipartBodyLengthLimit = 104_857_600;
});

// 2. Configure CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// 3. Configure Database: Sqlite by default for zero-config portability, or SqlServer if configured
var dbProvider = builder.Configuration["DatabaseProvider"] ?? "Sqlite";
var connectionString = dbProvider.Equals("SqlServer", StringComparison.OrdinalIgnoreCase)
    ? builder.Configuration.GetConnectionString("SqlServer") ?? "Server=localhost,1433;Database=JapaneseMastery;User Id=sa;Password=12345;TrustServerCertificate=True;MultipleActiveResultSets=True;"
    : builder.Configuration.GetConnectionString("Sqlite") ?? "Data Source=japanesemastery.db";

builder.Services.AddDbContext<AppDbContext>(options =>
{
    if (dbProvider.Equals("SqlServer", StringComparison.OrdinalIgnoreCase))
    {
        options.UseSqlServer(connectionString);
    }
    else
    {
        options.UseSqlite(connectionString);
    }
});

// 4. Configure JWT Authentication
var jwtSecret = builder.Configuration["App:Jwt:Secret"] ?? "404E635266556A586E3272357538782F413F4428472B4B6250645367566B5970";
var jwtKey = Encoding.UTF8.GetBytes(jwtSecret);

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.RequireHttpsMetadata = false;
    options.SaveToken = true;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(jwtKey),
        ValidateIssuer = false,
        ValidateAudience = false,
        ClockSkew = TimeSpan.Zero,
        RoleClaimType = ClaimTypes.Role,
        NameClaimType = ClaimTypes.Name
    };
});
builder.Services.AddAuthorization();

// 5. Configure HttpClients
builder.Services.AddHttpClient();
builder.Services.AddHttpClient<RomajiConverter>();

// 6. Realtime GNS301 & Mission Control Services
builder.Services.AddSingleton<MetricsTracker>();
builder.Services.AddSingleton<WsConnectionManager>();
builder.Services.AddSingleton<PyTunnelLogSink>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<PyTunnelLogSink>());
builder.Services.AddSingleton<PvPMatchEngine>();

// 7. Configure Legacy & Business Services
builder.Services.AddSingleton<JwtService>();
builder.Services.AddSingleton<JMdictService>();
builder.Services.AddSingleton<PvPService>();
builder.Services.AddHostedService<PvPMatchmakingBackgroundService>();

builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<UserService>();
builder.Services.AddScoped<VocabularyService>();
builder.Services.AddScoped<CloudinaryService>();
builder.Services.AddScoped<ShopService>();
builder.Services.AddScoped<CustomTestService>();

// 8. Configure Controllers and JSON Serialization
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        options.JsonSerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles;
        options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
    });

// 9. Configure Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "Japanese Mastery Realtime Backend API (.NET 8)",
        Version = "v1",
        Description = "ASP.NET Core REST API & High-Performance WebSocket Realtime Gateway (GNS301)"
    });
    c.CustomSchemaIds(type => type.FullName);

    c.AddSecurityDefinition("Bearer", new Microsoft.OpenApi.Models.OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = Microsoft.OpenApi.Models.SecuritySchemeType.Http,
        Scheme = "Bearer",
        BearerFormat = "JWT",
        In = Microsoft.OpenApi.Models.ParameterLocation.Header,
        Description = "Nhập mã JWT Token (lấy từ API /api/auth/login). Swagger sẽ tự động gửi kèm 'Bearer <token>'."
    });

    c.AddSecurityRequirement(new Microsoft.OpenApi.Models.OpenApiSecurityRequirement
    {
        {
            new Microsoft.OpenApi.Models.OpenApiSecurityScheme
            {
                Reference = new Microsoft.OpenApi.Models.OpenApiReference
                {
                    Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});

var app = builder.Build();

// 10. Run DB Initializer
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
    await DatabaseInitializer.InitializeAsync(context, logger);
}

// Ensure JMdict dictionary and vocabulary levels are ready (auto-downloads on fresh clone)
var jmdictService = app.Services.GetRequiredService<JMdictService>();
await jmdictService.EnsureDataReadyAsync();

// 11. Enable Swagger UI
app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Japanese Mastery API v1");
    c.RoutePrefix = "swagger";
});

app.UseCors("AllowAll");

// 12. Enable WebSockets Realtime Pipeline (RFC 6455)
var webSocketOptions = new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromSeconds(15)
};
app.UseWebSockets(webSocketOptions);
app.UseMiddleware<WsPvPMiddleware>();

app.UseRouting();

app.UseAuthentication();
app.UseAuthorization();

// 13. Discovery & Health Endpoints
app.MapGet("/api/discovery", (MetricsTracker metrics) =>
{
    return Results.Ok(new
    {
        status = "ONLINE",
        name = "Japanese Mastery Game Server",
        version = "1.0.0-gns301",
        protocol = "WebSocket/WSS + REST",
        wsEndpoint = "/ws/pvp",
        timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
        metrics = new
        {
            activeSockets = metrics.ActiveSockets,
            packetsIn = metrics.PacketsIn,
            packetsOut = metrics.PacketsOut,
            avgRttMs = Math.Round(metrics.AverageRttMs, 2)
        }
    });
});

app.MapControllers();
app.MapGet("/", () => Results.Redirect("/swagger"));

// Log startup to PyTunnel HUD
var logSink = app.Services.GetRequiredService<PyTunnelLogSink>();
logSink.Enqueue("NET-SERVER", "INFO", "Japanese Mastery .NET 8 Server online on http://0.0.0.0:8080");
logSink.Enqueue("PVP-SOCKET", "INFO", "WebSocket Gateway ready on /ws/pvp (Forwarded by Cloudflare Tunnel)");

app.Run();
