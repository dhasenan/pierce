using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using System.Web.Mvc.Ajax;
using System.Web.Security;
using MongoDB.Driver.Builders;

namespace pierce
{
	public class UsersController : BaseController
	{
		private readonly PierceConfig _config;

		public UsersController(Mongo db, PierceConfig config) : base(db)
		{
			_config = config;
		}

		public ActionResult Login(string email, string password)
		{
			if (string.IsNullOrEmpty(email))
			{
				Response.StatusCode = 401;
				return Json(new {});
			}
			password = pierce.User.HashedPassword(password);
			var result = db.Users.Find(Query.EQ("Email", email));
			if (result.Size() == 1)
			{
				var user = result.First();
				if (user.PasswordHash == password)
				{
					FormsAuthentication.SetAuthCookie(user.Id, true);
					return Json(user);
				}
			}
			Response.StatusCode = 404;
			return Json(new {});
		}

		public ActionResult Get()
		{
			var user = GetUser();
			if (user == null)
			{
				Response.StatusCode = 404;
				return Json(new {});
			}
			return Json(user);
		}

		public ActionResult Register(string email, string password)
		{
			if (!_config.AllowNewRegistrations)
			{
				return Json(new { Error = "The administrator has disabled new user registrations." });
			}
			var result = db.Users.Find(Query.EQ("Email", email));
			if (result.Size() >= 1)
			{
				return Json(new { Error = "An account already exists with that email address." });
			}
            var user = new User { Email = email, Password = password, NextMaintenance = DateTime.UtcNow };
			var saved = db.Users.Insert(user);
			if (!saved.Ok)
			{
				return Json(new { Error = "failed to save user: " + saved.ErrorMessage });
			}

			FormsAuthentication.SetAuthCookie(user.Id, true);
			log.Info("registered new user");
			return Json(user);
		}

		public ActionResult Update(string email, string currentPassword, string newPassword, int checkInterval)
		{
			var user = GetUser();
			if (user == null)
			{
				Response.StatusCode = 401;
				return Json(new {});
			}
			var hashedCurrent = pierce.User.HashedPassword(currentPassword);
			if (hashedCurrent != user.PasswordHash)
			{
				return Json(new { Error = "Current password does not match." });
			}
			if (email != user.Email)
			{
				var result = db.Users.Find(Query.EQ("Email", email));
				if (result.Size() > 0)
				{
					return Json(new { Error = "That email address is already in use." });
				}
			}
			user.Password = newPassword;
			user.Email = email;
			user.DefaultCheckInterval = TimeSpan.FromMinutes(checkInterval);
			db.Users.Save(user);
			return Json(new {});
		}

		public ActionResult Logout()
		{
			FormsAuthentication.SignOut();
			return Json(new object());
		}
	}
}

