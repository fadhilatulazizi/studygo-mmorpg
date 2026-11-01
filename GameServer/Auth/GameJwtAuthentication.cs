using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;

namespace StudyGo.GameServer.Auth;

public static class GameJwtAuthentication
{
    public static bool AddGameJwtAuthentication(this IServiceCollection services, IConfiguration configuration)
    {
        var secret = configuration["GameAuth:JwtSecret"] ?? "";
        var issuer = configuration["GameAuth:Issuer"] ?? "";
        var audience = configuration["GameAuth:Audience"] ?? "";
        if (Encoding.UTF8.GetByteCount(secret) < 32 ||
            string.IsNullOrWhiteSpace(issuer) || string.IsNullOrWhiteSpace(audience))
            return false;

        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                options.MapInboundClaims = false;
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = issuer,
                    ValidateAudience = true,
                    ValidAudience = audience,
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)),
                    ValidateLifetime = true,
                    ClockSkew = TimeSpan.FromSeconds(30),
                    ValidAlgorithms = new[] { SecurityAlgorithms.HmacSha256 }
                };
            });
        services.AddAuthorization();
        return true;
    }
}
