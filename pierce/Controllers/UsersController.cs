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
        public ActionResult Login(string email, string password, string register)
        {
            if (register == "true")
            {
                return Register(email, password);
            }
            password = pierce.User.HashedPassword(password);
            var result = Pierce.Users.Find(Query.EQ("Email", email));
            if (result.Size() == 1)
            {
                var user = result.First();
                if (user.PasswordHash == password)
                {
                    FormsAuthentication.SetAuthCookie(user.Id.ToString(), true);
                    return Json(user);
                }
            }
            return Json(new { Error = "Failed to log in." });
        }

        public ActionResult Register(string email, string password)
        {
            var result = Pierce.Users.Find(Query.EQ("Email", email));
            if (result.Size() >= 1)
            {
                return Json(new { Error = "An account already exists with that email address." });
            }
            var user = new User { Email = email, Password = password };
            var saved = Pierce.Users.Insert(user);
            if (!saved.Ok)
            {
                return Json(new { Error = "failed to save user: " + saved.ErrorMessage });
            }

            FormsAuthentication.SetAuthCookie(user.Id.ToString(), true);
            return Json(new { User = user });
        }

        public ActionResult Logout()
        {
            FormsAuthentication.SignOut();
            return Json(new { Success = true });
        }
    }
}

