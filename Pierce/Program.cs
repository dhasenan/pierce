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
    builder.Services.AddAuthorization(options => {});
    builder.Services.AddScoped<PierceContext>();
    builder.Services.AddControllers();

    var app = builder.Build();
    app.UseFileServer();
    app.UseAuthentication();
    app.UseAuthorization();
    app.MapControllers();
    app.Run();
  }
}
