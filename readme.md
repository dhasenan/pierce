Pierce
======
A self-hosted RSS reader for those who like simplicity and orange.

Installation
------------
* Install MongoDB.
* Install a web server (Apache, nginx, IIS, something like that).
* Extract pierce to an appropriate location.
* Ensure that you have an encryption key in the <machineKey> of your machine.config. Otherwise,
  users will be logged out every time you restart the server.
* If running on Apache:
** Install mod_mono (libapache2-mod-mono mono-apache-server4).
** Configure a virtual host in /etc/apache2/conf.d/$SITE.
** Restart Apache.

Note that MongoDB preallocates 3GB of space. If you're running on, say, an Amazon EC2 micro
instance, you need either a larger-than-default disk or a secondary disk to hold your data.
