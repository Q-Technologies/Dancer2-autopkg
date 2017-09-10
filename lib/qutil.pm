package qutil;
################################################################################
#                                                                              #
# qutil - Some utility functions for Q-Tech tools                              #
#                                                                              #
# This library is a collection of utility functions to reduce code             #
# duplication - eventually, it will be nicely broken up into proper            #
# modules fit for CPAN.                                                        #
#                                                                              #
#          see https://github.com/Q-Technologies/perl-qutil for project info   #
#                                                                              #
# Copyright 2017 - Q-Technologies (http://www.Q-Technologies.com.au)           #
#                                                                              #
#                                                                              #
# Revision History                                                             #
#                                                                              #
#    Sep 2017 - Initial release.                                               #
#                                                                              #
################################################################################

use strict;
use Data::Dumper;
use YAML::XS qw(Dump Load);
use File::Path qw(make_path);
use File::Copy;
use File::Basename;
use Dancer2::Plugin;
use POSIX qw/strftime/;
use 5.10.0;

use constant SUCCESS => "success";
use constant FAILED => "failed";

# Define variables to hold settings
has 'debug_level' => (
    is => 'rw', 
    required => 1,
    default => 0,
    predicate => 'has_debug_level',
);
has 'top_level_dir' => (
    is => 'rw', 
    required => 1,
    default => '/var/lib/www',
    predicate => 'has_top_level_dir',
);

plugin_keywords qw/
    top_level_dir
    debug_level
    check_login
    web_log
/;

sub BUILD {
    my $self = shift;
    if( defined( $self->app->config->{debug_level}) ){
        $self->debug_level( $self->app->config->{debug_level} );
    }
    if( defined( $self->app->config->{top_level_dir}) ){
        $self->top_level_dir( $self->app->config->{top_level_dir} );
    }
    say $self->top_level_dir;
}


sub check_login {
    my $self = shift;
    my $result = FAILED;
    my $msg;
    #say Dumper( $self->dsl );
    my $userid = $self->dsl->param( "userid" );
    my $passwd = $self->dsl->param( "passwd" );
    my $user = $self->app->config->{user};
    my $pass = $self->app->config->{pass};

    say join( " - ", $userid, $passwd ) if $self->debug_level > 1;
    if( ( ! $self->dsl->session('logged_in') or $self->dsl->session('logged_in') ne 'true' )
        and     
        !( $pass eq $passwd and $user eq $userid) 
      ){
        $msg = "ERROR: you must be logged in to do something!";
    } else {
        $self->dsl->session( logged_in => 'true' );
        $result = SUCCESS;
        $msg = "Successfully logged and session started";
    }
    $self->dsl->debug( $msg ) if $self->debug_level > 0;
    return ( $result, $msg );
}

sub web_log {
    my $self = shift;
    my $web_log_format = $self->app->config->{web_log_format};
    my $web_log_path = $self->app->config->{web_log_path};
    my $h = $self->app->request->env->{'REMOTE_HOST'};
    $h = "-" if ! $h;
    my $l = "-";
    my $u = $self->app->request->env->{REMOTE_USER};
    $u = "-" if ! $u;
    my $t = strftime( "[%x:%X %z]", localtime );
    my $r = $self->app->request->env->{REQUEST_URI};
    $r = "-" if ! $r;
    my $s = "200"; # Otherwise we wouldn't be here
    my $b = "-"; # Beyond the scope of what we want to do
    my $rfr = $self->app->request->headers->{referer};
    $rfr = "-" if ! $rfr;
    my $ua = $self->app->request->headers->{'user-agent'};
    $ua = "-" if ! $ua;
    my $usg = $self->app->request->headers->{'x-requested-using'};
    $usg = "-" if ! $usg;
    my $src = $self->app->request->headers->{'x-requested-source'};
    $src = "-" if ! $src;

    for( $web_log_format ){
        s/%h/$h/;
        s/%l/$l/;
        s/%u/$u/;
        s/%t/$t/;
        s/%r/$r/;
        s/%(>)*s/$s/;
        s/%b/$b/;
        s/%\{Referer\}i/$rfr/i;
        s/%\{User-agent\}i/$ua/i;
        s/%\{X-Requested-Using\}i/$usg/i;
        s/%\{X-Requested-Source\}i/$src/i;
    }

    #return;

    if( -w $web_log_path or ( -w dirname( $web_log_path ) and not -e $web_log_path )){
        if( open my $wl, ">>$web_log_path" ){
            print $wl $web_log_format . ' "'. join( '" "', @_ ) . "\"\n";
        } else {
            $self->dsl->debug( "Could not open the web log file ($web_log_path) for writing - unexpected error" )
        }
    } else {
        $self->dsl->debug( "Could not open the web log file ($web_log_path) for writing - permission denied" )
    }

}



1;
