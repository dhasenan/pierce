Pierce
======
Pierce is a simple RSS reader with a UI inspired by the late 90s. Think Thunderbird. Think Outlook.

Building
========
On Linux, use `mdtool build` or MonoDevelop to build Pierce. The version of xbuild that comes with
Mono 3.2.8 doesn't build Pierce correctly. You will need libmono-system-web-mvc3.0-cil installed. I
believe the rest of the build dependencies are included in the repository.

Installation
============
Dependencies
------------

 * mongodb
 * mono-xsp4
 * A web server compatible with mono (eg apache + mod_mono)
 * mono root certificates (mozroots)

In ubuntu, you should be able to run:

    sudo apt-get install mongodb mono-xsp4 libapache2-mod-mono mono-apache-server4
    yes yes | sudo mozroots --import

Then restart apache2. You may have to modify /etc/mono-server4/mono-server4-hosts.conf to fix the
lib path; see https://bugs.launchpad.net/ubuntu/+source/xsp/+bug/1293481.


Installing
----------
First, copy the entire application to some convenient location.

Then create an apache site configuration file. There is an example included in this directory; see
apache-site-example.conf.

Configure your site however you want (see the Administration section below).

Enable your new site with `a2ensite`.

Reload apache and enjoy.


Administration
==============
There are two files you might need to worry about when administering pierce.

log4net.config
--------------
This controls the logging policy. https://logging.apache.org/log4net/release/config-examples.html
will show you how to modify this.  You may wish to change the log directory, filename, threshold, or
retention, or add an SMTP appender (to get emailed about errors).

Web.config
----------
In pierce/pierce/Web.config (an XML file), there is a section called `appSettings`. This contains
the only end-user configurable application settings in the file.

Currently supported settings:

 * trustAllCertificates: whether to accept RSS feeds from sources with invalid security
   certificates. Read the notes above about mozroots before setting this.
 * allowNewRegistrations: whether to allow more people to register.
 * minRefreshInterval: Pierce will check each feed once every sixty minutes by default. Users can
   configure this on a per-feed basis. minRefreshInterval is the minimum number of minutes they can
   specify -- in a default installation, they can have a feed refresh every thirty minutes if they
   choose.

You may have to restart the application for the new data values to be read.

Lost passwords
--------------
There's no password reset mechanism right now. Don't lose your password.

Problems
========

Help, I can't add any feeds at HTTPS URLs!
------------------------------------------
You are running on Mono. Mono does not use the system X.509 certificate store. Run `mozroots` as
described above.
