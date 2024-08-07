using System;
using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Isopoh.Cryptography.Argon2;
using Microsoft.EntityFrameworkCore;

namespace Pierce;

[Index(nameof(Email), IsUnique = true)]
public class User
{
  [Key]
  public long Id { get; private set; }
  public string Email { get; set; }
  public string PasswordHash { get; private set; }
  public ICollection<Subscription> Subscriptions { get; set; } = new List<Subscription>();

  public string Password
  {
    set { PasswordHash = Argon2.Hash(value); }
  }

  public bool Verify(string password)
  {
    return Argon2.Verify(PasswordHash, password);
  }
}

public static class HttpContextExtensions
{
  public static async Task<User?> PierceUser(this HttpContext ctx, PierceContext db)
  {
    foreach (var claim in ctx.User.Claims)
    {
      if (claim.Type == "id")
      {
        var id = long.Parse(claim.Value);
        return await db.Users.FindAsync(id);
      }
    }
    return null;
  }
}

[Route("auth")]
[ApiController]
[Authorize]
public class AuthController : Controller
{
  private readonly PierceContext db;
  private readonly bool allowRegistration;

  public AuthController(PierceContext db, IConfiguration config)
  {
    this.db = db;
    this.allowRegistration = "true".Equals(config["AllowRegistration"], StringComparison.InvariantCultureIgnoreCase);
  }

  private string? ValidateEmail(string email)
  {
    try
    {
      var parsed = new System.Net.Mail.MailAddress(email);
      return parsed.Address;
    }
    catch
    {
      return null;
    }
  }

  public class EmailPasswordBody
  {
    public string Email { get; set; }
    public string Password { get; set; }
  }

  public class ChangePasswordBody
  {
    public string OldPassword { get; set; }
    public string NewPassword { get; set; }
  }

  [AllowAnonymous]
  [HttpPost("login")]
  public async Task<IActionResult> Login([FromBody] EmailPasswordBody body)
  {
    var validated = ValidateEmail(body.Email);
    if (validated == null)
    {
      return StatusCode(400, "Invalid email address");
    }
    var existing = await db.Users.SingleOrDefaultAsync(user => user.Email == body.Email);
    if (existing == null)
    {
      return StatusCode(404, "Email not found");
    }
    if (!existing.Verify(body.Password))
    {
      return StatusCode(401, "Incorrect password");
    }
    await HttpContext.SignInAsync(new ClaimsPrincipal(new ClaimsIdentity(new List<Claim>{
      new Claim("id", existing.Id.ToString()),
    })));
    return Ok();
  }

  [AllowAnonymous]
  [HttpPost("register")]
  public async Task<IActionResult> Register([FromBody] EmailPasswordBody body)
  {
    if (!allowRegistration)
    {
      return StatusCode(400, "Registration not allowed");
    }
    var existing = await db.Users.SingleOrDefaultAsync(user => user.Email == body.Email);
    if (existing != null)
    {
      return StatusCode(409, "A user with this email address already exists");
    }
    var user = new User()
    {
      Email = body.Email,
      Password = body.Password,
    };
    await db.Users.AddAsync(user);
    await db.SaveChangesAsync();
    var identity = new ClaimsIdentity(new List<Claim>{
      new Claim("id", user.Id.ToString()),
    }, "id", "id", "user");
    await HttpContext.SignInAsync(new ClaimsPrincipal(identity));
    return Ok();
  }

  [HttpPost("changepassword")]
  public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordBody body)
  {
    var user = await HttpContext.PierceUser(db);
    if (!user.Verify(body.OldPassword))
    {
      return StatusCode(401, "Incorrect existing password");
    }
    user.Password = body.NewPassword;
    db.Users.Update(user);
    await db.SaveChangesAsync();
    return Ok();
  }

  [HttpPost("logout")]
  public async Task<IActionResult> Logout()
  {
    await HttpContext.SignOutAsync();
    return Ok();
  }
}
