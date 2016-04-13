#!/usr/bin/env perl

################################################################################
#                                                                              #
# autopkg - package up files into OS packages                                  #
#                                                                              #
# This web service will provide an API where meta data can be sent that drive  #
# the packaging of a group of files stored on remote repositories.             #
#                                                                              #
# It is written in Perl using the Dancer2 Web Framework (a lightweight         #
# framework based on Sinatra for Ruby).  autopkg  does not provide a web       #
# browser interface, but JSON can be sent and received as XMLHttpRequest       #
# object                                                                       #
#                                                                              #
#          see https://github.com/Q-Technologies/autopkg for full details     #
#                                                                              #
#                                                                              #
# Copyright 2016 - Q-Technologies (http://www.Q-Technologies.com.au            #
#                                                                              #
#                                                                              #
# Revision History                                                             #
#                                                                              #
#    Feb 2016 - Initial release                                                #
#                                                                              #
# Issues                                                                       #
#   *                                                                          #
#                                                                              #
################################################################################

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Plack::Builder;

use autopkg::api;

builder {
    mount '/api' => autopkg::api->to_app;
};


