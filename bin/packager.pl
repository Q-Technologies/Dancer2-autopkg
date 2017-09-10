#!/usr/bin/perl
#
################################################################################
#                                                                              #
# autopkg - package up files into OS packages                                  #
#                                                                              #
# This script will connect to the database and perform the packaging requests  #
# that need to be done.                                                        #
#                                                                              #
################################################################################

use strict;
use warnings;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Dancer2;
use autopkg;
use qutil;
use Cwd;
use 5.10.0;

# All paths should be relative to the root of the application
chdir "$FindBin::Bin/..";

# Globals
my $user;
my $group;
my $start;
my $stop;
my $pidfile;

# Process command line options
GetOptions ( 'user|u=s' => \$user, 
             'group|g=s' => \$group, 
             'start' => \$start, 
             'stop' => \$stop,
             'pid=s' => \$pidfile,
           );

# Check we have the required environment variables set for Dancer to work
if( ! $ENV{DANCER_CONFDIR} or ! $ENV{DANCER_ENVIRONMENT} ){
    say "Error: Please set up the ENV variables!";
    exit 1;
}

# set the variables according to the settings
my $queue_sleep = setting( 'pkg_queue_sleep' );
my $daemon_log = setting( 'pkg_dlog_file' );
#pkg_log_file( cwd()."/".pkg_log_file ) if( pkg_log_file !~ /^\//);
#top_level_dir( cwd()."/".top_level_dir ) if( top_level_dir !~ /^\//);
#repo_dir( cwd()."/".repo_dir ) if( repo_dir !~ /^\//);

# See if the script has been told to run a a different user
my $uid = $<;
$uid = getpwnam($user) if $user;
my $gid = $(;
$gid = getgrnam($group) if $group;

# We need a PID file in order to control stopping and starting
if( ! $pidfile ){
    say "Error: Please specify the PID file";
    exit 1;
}

# Start or stop the daemon process 
if( ( $start and $stop ) or ( ! $start and ! $stop )){
    say "Please specify --start or --stop!"
} elsif( $start ){
    say "Starting...";

    # Go into Daemon mode
    #daemonize();
    my $continue = 1;
    #$SIG{TERM} = sub { $continue = 0 };
    
    # Process the queue until we are told to stop
    while ($continue) {
        process_pkg_queue();
        sleep $queue_sleep;
    }

} elsif( $stop ){
    say "Stopping...";
    my $pid = get_pid( $pidfile );
    if( ! $pid ){
        say "Error: PID file did not contain a PID - was it running?";
        exit 1;
    }
    my $output = `kill $pid 2>&1`;
    if( $? != 0 ){
        say "Error: Could not stop: $output";
        exit 1;
    }
}

# subroutine to daemonize this process
sub daemonize {
    use POSIX;

    # Check whether we are already running - we trust the PID file
    my $pid = get_pid( $pidfile );
    my $exists;
    $exists = kill 0, $pid if $pid;
    say "Process [$pid] is already running and looks like this daemon - cannot continue\n" and exit 1 if ( $exists and $pid );

    POSIX::setsid or die "setsid: $!";
    $pid = fork ();
    if ($pid < 0) {
        die "fork: $!";
    } elsif ($pid) {
        exit 0;
    }
    open PID, ">$pidfile" or die "Error: Could not create PID file: $!";
    print PID $$;
    close PID;
    setuid( $uid ) if $uid;
    setgid( $gid ) if $gid;
    chdir "/";
    umask 0;
    foreach (0 .. (POSIX::sysconf (&POSIX::_SC_OPEN_MAX) || 1024))
       { POSIX::close $_ }
    open (STDIN, "</dev/null");
    open (STDOUT, ">$daemon_log");
    open (STDERR, ">&STDOUT");

 }

sub get_pid {
    my $file = shift;
    my $pid;
    if( open PID, "<$file" ){
        while( <PID> ){
            $pid .= $_;
        }
        if( $pid !~ /^\d+$/ ){
            say "Error: The pid in $file was not in the expected format";
            exit 1;
        }
    }

    return $pid;
}

