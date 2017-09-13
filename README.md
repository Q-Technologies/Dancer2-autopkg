# autopkg - Packaging Service

This web service provides an API to create packages and put them into a package repository.  This is useful when an automated workflow is testing application code.  Once the code is tested it can be quickly packaged via this service.

The testing service sends an AJAX request to this service.  Inside the AJAX request is a list of files and where to download them from.  This service will download all the files and, using the additional metadata in the AJAX request, construct a package using the standard packaing tools (e.g. rpmbuild).

**autopkg** is written in Perl using the [Dancer2](http://perldancer.org) Web Framework (a lightweight framework based on Sinatra for Ruby).  **autopkg** does not provide a web browser interface, but JSON can be sent and received as XMLHttpRequest object.  See https://github.com/Q-Technologies/autopkg for full details.

It security model is simple:
  * an access code and key
  * any encyption is to be provided by the web server proxying the service

## Usage

The AJAX request needs to contain JSON along these lines.  All, but ChangeLog, License and Group are compulsory - an error will be returned if they are not provided.

    {
      "PayLoad" : [
         {
            "Name" : "JavaApp",
            "Version" : "6.5.0",
            "Release" : "1.0.2",
            "InstallRoot" : "/home/tomcat/blah",
            "ChangeLog" : "- initial version (1.0)",
            "Description" : "This package is used to install the WAR files onto the system",
            "Author" : "Random Build System",
            "License" : "Artistic",
            "Files" : [
                {
                    "Owner" : "tomcat:tomcat",
                    "Perms" : "0644",
                    "SrcUrl" : "http://nexus/path/to/file.war"
                },
                {
                    "SrcUrl" : "http://nexus/path/to/file2.war",
                    "Perms" : "0644",
                    "Owner" : "tomcat:tomcat"
                }
            ],
            "Target" : {
                "Package" : "rpm",
                "Arch" : "noarch"
            },
        }
    ],
        "Action" : "override",
        "Event" : "from jenkins",
    }

Once the request is received, the payload will be stored in a sqlite database - this allows the web request to be returned quickly.  Queries can be sent to find out what the status is of the payload.

A seperate process is continually polling the database to find new requests - it will then create the packages and repositories.  At the moment only RPMs are supported.

### Authentication

Authentication will be a simple pre-shared username and password:

    username: packager
    password: XXXXXXXX

This can either be sent as parameters in the URL or embedded in the JSON object. Sessions are also supported, so authentication only has to occur once an hour.

### Response

A successful post will get a 202 status code and a JSON object along these lines:

    {
       "result" : "success", 
       "message" : "All packaging information has been successfully queued", 
       "jobno" : "9872"
    }

An unsuccessful post will get a 200 status and a JSON object like this - the message will try to convey what went wrong:

    {
       "result" : "failed", 
       "message" : "An error occurred trying to queue the submitted packaging information"
    }

Other errors might occur where an unexpected condition was met - this would usually return a status of 500.


## Installation

### Prepare Environment

Install the following PERL modules (or more depending on what you have installed already):
  * Dancer2
  * Dancer2::Plugin::Ajax


### Manually

```
cd /opt/
git clone git remote add origin https://github.com/Q-Technologies/Dancer2-autopkg.git
cd Dancer2-autopkg
# Customise config_local.yml and the files in the environment directory
DANCER_ENVIRONMENT=development
DANCER_ENVDIR=/opt/Dancer2-autopkg/environments
DANCER_CONFDIR=/opt/Dancer2-autopkg
perl bin/packager.pl --pid /tmp/p.pid --start
plackup -a bin/app.pl -I lib -l :3009
```


### RPM

Install the RPM (it assumes you have a perl installation with all the required modules in a package called perlbrew), though it depends on the specfile used to build the RPM:

    rpm -ivh autopkg-1.0-1.0.noarch.rpm

Update PERL5LIB in the `/etc/sysconfig/autopkg` file with the path for additional PERL modules, if required

#### Set the locations of key directories
In `./environments/production.yml`, set the `top_level_dir` and `repo_dir`, e.g.:

    top_level_dir: "/autopkg"
    repo_dir: "/repo/apps/from_nexus"

Make sure the user autopkg is running as (autopkg, by default) has permissions to write to this directory:

    mkdir /autopkg
    chown autopkg /autopkg


## Maintenance
### Changing the password
Change the password in the `config_local.yml` file and restart the web service.  Also change the password in any client scripts submitting data.

## Missing Features

  * Changelog is currently ignored as it needs a data format specification
  * The packaging process only downloads the specified files anonymously - authentication capabilities/credentials management needs to be added
  * only RPMs are supported currently


