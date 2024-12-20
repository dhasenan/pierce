using System.Threading;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.JwtBearer;

namespace Pierce;

public class Program
{
  public static void Main(string[] args)
  {
    var builder = WebApplication.CreateBuilder(args);
    builder.Services.AddAuthentication()
      .AddCookie(options =>
      {
        options.LoginPath = "/auth/login";
        options.Cookie.Name = "pierce-auth";
        options.ExpireTimeSpan = TimeSpan.FromDays(60);
      });
    builder.Services.AddAuthorization(options =>
      {
        options.AddPolicy("loggedin", policy => policy.RequireClaim("id"));
      });
    builder.Services.AddScoped<PierceContext>();
    builder.Services.AddScoped<CheckFeeds>();
    builder.Services.AddScoped<ReadFeeds>();
    builder.Services.AddScoped<FeedParser>();
    builder.Services.AddScoped<Wget>();
    builder.Services.AddScoped<AutodetectFeeds>();
    builder.Services.AddHostedService<ReaderService>();
    builder.Services.AddControllers()
      .AddJsonOptions(options => {
          options.JsonSerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
      });

    var app = builder.Build();
    app.UseFileServer();
    app.UseAuthentication();
    app.UseAuthorization();
    app.MapControllers();

    app.Run();
  }
}
