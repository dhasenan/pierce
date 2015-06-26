using System;
using System.Web.Configuration;
using Castle.Core.Logging;

namespace pierce
{
	public class PierceConfig
	{
		const string allowRegistrationsKey = "allowNewRegistrations";
		const string trustCertsKey = "trustAllCertificates";
		const string minUpdateKey = "minUpdateInterval";
		readonly TimeSpan defaultMinInterval = TimeSpan.FromMinutes(30);
		const string defaultUpdateKey = "defaultUpdateInterval";
		readonly TimeSpan defaultDefaultInterval = TimeSpan.FromMinutes(60);
		ILogger _logger;

		public PierceConfig(ILogger logger)
		{
			_logger = logger;
		}

		public bool AllowNewRegistrations
		{
			get
			{
				return AppSettingToBool(allowRegistrationsKey);
			}
		}

		public bool TrustAllCertificates
		{
			get { return AppSettingToBool(trustCertsKey); }
		}

		public TimeSpan MinUpdateInterval
		{
			get { return AppSettingToTimeSpan(minUpdateKey, defaultMinInterval); }
		}

		public TimeSpan DefaultUpdateInterval
		{
			get { return AppSettingToTimeSpan(defaultUpdateKey, defaultDefaultInterval); }
		}

		private TimeSpan AppSettingToTimeSpan(string key, TimeSpan defaultValue)
		{
			var value = WebConfigurationManager.AppSettings [key];
			if (value == null)
			{
				_logger.DebugFormat("no value specified for setting {0}", key);
				return defaultMinInterval;
			}
			int minutes;
			if (int.TryParse(value, out minutes))
			{
				if (minutes < 0)
				{
					minutes = 0;
				}
				return TimeSpan.FromMinutes(minutes);
			}
			_logger.ErrorFormat("failed to parse '{0}' as a number for setting {1}", value, key);
			return defaultValue;
		}

		private bool AppSettingToBool(string key)
		{
			var value = WebConfigurationManager.AppSettings [key];
			if (value == null)
			{
				_logger.DebugFormat("no value specified for setting {0}", key);
				return true;
			}
			value = value.ToLower();
			if (value == "true")
			{
				return true;
			}
			if (value == "false")
			{
				return false;
			}
			_logger.ErrorFormat("unknown configuration value '{0}' for key '{1}' (expected 'true' or 'false')", value, key);
			return true;
		}
	}
}

