Pierce
======
Pierce is a simple RSS reader with a UI inspired by the late 90s -- Thunderbird and Outlook, mainly.

![image of pierce rss reader](https://github.com/dhasenan/pierce/raw/master/pierce.png)

Building
========
1. Install dmd and dub.
2. Run `dub build`


Installation
============

Brief instructions
------------------
Copy the pierce binary, config, and `static/` directory to your server. They need to be in the same
directory. Copy the init script to `/etc/init.d` or write your own.

Install postgresql, apache2, and certbot. Run certbot.

Create the database and database user. Preferably create the user that pierce will run as so you
don't have to have a password.

Set up a reverse proxy to `localhost:9881`.

Done!


Detailed instructions
---------------------
You need:

* the pierce binary
* the `static/` directory
* your pierce config file
* the init script, `pierce.sh`
* postgresql
* A webserver as a reverse proxy, and the webserver configuration file (optional, highly
  recommended)
* letsencrypt client (optional, highly recommended)

Copy the binary, config, and `static/` directory to your server using `scp` (WinSCP is a good
Windows scp client). Put them in their own directory.

On Ubuntu, you can install the dependencies with:

    sudo add-apt-repository ppa:certbot/certbot
    sudo apt-get update
    sudo apt-get install python-certbot-apache apache2 postgresql-9.5

Copy over the apache config file to `/etc/apache2/sites-available/pierce.conf`. Ensure that you set
the site name is correct for your site. Then enable the site and letsencrypt:

    sudo a2ensite pierce
    sudo apache2 reload
    sudo certbot --apache -d [your site's name here]

Prepare a database and user for pierce. You can access postgres with `sudo su postgres`  and then
`psql`. Inside the psql command line:

    create database piercedb;
    create user pierce with password 'password';
    grant all on database piercedb to pierce;

Make sure the username and password match the config file.

`Ctrl+D` until you're back at your normal shell.

Copy `pierce.sh` to the server and move it to the init directory:

    sudo cp pierce.sh /etc/init.d/pierce

Now run `sudo service pierce start`.

You're done!


Configuration
=============
The configuration file is a JSON object such as:

    {
      "db": "postgresql://pierceuser:password@dbservername/piercedbname",
      "allowRegistrations": true,
      "port": 9881,
      "mongo": "mongo://mongoservername:27017/pierce"
    }

`"db"` is a postgresql server URL. It defaults to `postgresql://localhost/pierce`.

`"allowRegistrations"` controls whether new people can register to use your Pierce installation. It
defaults to `true`.

`"port"` changes the port that Pierce listens to. The default is 9881.

`"mongo"` is the location of your mongodb instance, if you are migrating from an older version of
Pierce that used MongoDB.
