using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using JapaneseMasteryBackendDotNet.Models;
using Microsoft.IdentityModel.Tokens;

namespace JapaneseMasteryBackendDotNet.Services;

public class JwtService
{
    private readonly string _secret;
    private readonly int _expirationMs;

    public JwtService(IConfiguration config)
    {
        _secret = config["App:Jwt:Secret"] ?? "404E635266556A586E3272357538782F413F4428472B4B6250645367566B5970";
        _expirationMs = int.TryParse(config["App:Jwt:ExpirationMs"], out var exp) ? exp : 86400000;
    }

    private SymmetricSecurityKey GetSigningKey()
    {
        return new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_secret));
    }

    public string GenerateToken(User user)
    {
        return GenerateToken(user.Username, user.Role.ToString(), user.Id);
    }

    public string GenerateToken(string username, string role = "PLAYER", long userId = 0)
    {
        var tokenHandler = new JwtSecurityTokenHandler();
        var key = GetSigningKey();
        var claims = new List<Claim>
        {
            new Claim(ClaimTypes.NameIdentifier, userId > 0 ? userId.ToString() : username),
            new Claim(ClaimTypes.Name, username),
            new Claim(ClaimTypes.Role, role),
            new Claim("role", role),
            new Claim("userId", userId.ToString()),
            new Claim(JwtRegisteredClaimNames.Sub, username),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };
var tokenDescriptor = new SecurityTokenDescriptor
        {
            Subject = new ClaimsIdentity(claims),
            IssuedAt = DateTime.UtcNow,
            Expires = DateTime.UtcNow.AddMilliseconds(_expirationMs),
            SigningCredentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256Signature)
        };

        var token = tokenHandler.CreateToken(tokenDescriptor);
        return tokenHandler.WriteToken(token);
    }

    public bool ValidateToken(string token)
    {
        if (string.IsNullOrWhiteSpace(token)) return false;

        var tokenHandler = new JwtSecurityTokenHandler();
        var key = GetSigningKey();
        try
        {
            tokenHandler.ValidateToken(token, new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = key,
                ValidateIssuer = false,
                ValidateAudience = false,
                ClockSkew = TimeSpan.Zero
            }, out SecurityToken validatedToken);

            return true;
        }
        catch
        {
            return false;
        }
    }
}
