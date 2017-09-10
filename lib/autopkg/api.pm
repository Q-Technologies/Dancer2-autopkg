package autopkg::api;
################################################################################
#                                                                              #
# autopkg - OS Package maker web service                                       #
#                                                                              #
#          see https://github.com/Q-Technologies/autopkg for project info      #
#                                                                              #
# Copyright 2016 - Q-Technologies (http://www.Q-Technologies.com.au)           #
#                                                                              #
#                                                                              #
# Revision History                                                             #
#                                                                              #
#    Feb 2016 - Initial release.                                               #
#                                                                              #
################################################################################

use Dancer2;
use Dancer2::Plugin::Ajax;
use autopkg;
use qutil;
use Data::Dumper;
use File::Basename;
use POSIX qw(strftime);
use 5.10.0;

use constant SUCCESS => "success";
use constant FAILED => "failed";

set serializer => 'JSON';

our $VERSION = '0.1';

ajax '/login' => sub {
    my ( $result, $msg ) = check_login();
    { result => $result, message=> $msg };
};

ajax '/logout' => sub {
    session->destroy;
    { result => SUCCESS, message=> "Successfully logged out and session destroyed" };
};

ajax '/trigger' => sub {
    my $function = "trigger";

    # Process inputs
    my %allparams = params;
    my $payload = param "PayLoad";
    my $action = param "Action";
    my $event = param "Event";

    my $result = FAILED;
    my $msg = "";
    my $log = [];

    #debug (Dumper( \%allparams ) );

    # Check whether the user is logged in
    ( $result, $msg ) = check_login();
    return { result => $result, function => $function, message=> $msg } if( $result ne SUCCESS );

    # Send call to create the RPM
    #my $ans = { result => "success", message => "Just testing", log => [] };
    my $ans = queue_rpms( $payload, $action, $event ); 

    #debug( "Answer: " . Dumper( $ans ) );
    $result = $ans->{result};
    $msg = $ans->{message}; 
    $log = $ans->{log}; 

    debug join( "\n", @$log );

    { result => $result, function => $function, message=> $msg };


};

ajax '/getlog' => sub {
    my $function = "getlog";

    # Process inputs
    my %allparams = params;
    my $numlines = param "numlines";

    my ($result, $msg );

    # Check whether the user is logged in
    ( $result, $msg ) = check_login();
    return { result => $result, function => $function, message=> $msg } if( $result ne SUCCESS );

    # Check whether the number of lines specified is sane
    return { result => FAILED, function => $function, message=> "Please specify the number of lines to grab (max 500)" } if( $numlines !~ /^\d+$/ or $numlines > 500 );

    # get the output form the log
    my $cmd = "tail -".$numlines." /var/log/autopkg/production.log";
    #my $cmd = "tail -".$numlines." ".setting( 'pkg_log_file' );
    my @output = `$cmd`;

    # return an error if no lines were returned from the logfile
    return { result => FAILED, function => $function, message=> "Failed to get any lines from the log file" } if( @output < 1 );

    # otherwise return the log files as success
    { result => SUCCESS, function => $function, message => "last $numlines of log file output", log => \@output };
    
};

ajax '/getstatus' => sub {
    my $function = "getstatus";

    # Process inputs
    my %allparams = params;
    my $jobid = param "jobid";

    my $result = FAILED;
    my $msg = "";
    my $log = [];

    debug (Dumper( \%allparams ) );
    #debug 

    # Check whether the user is logged in
    ( $result, $msg ) = check_login();
    return { result => $result, function => $function, message=> $msg } if( $result ne SUCCESS );

    # Send call to find out the status of a previously submitted job
    my $ans = get_status( $jobid ); 

    debug( "Answer: " . Dumper( $ans ) );
    $result = $ans->{result};
    $msg = $ans->{message}; 
    $log = $ans->{log}; 

    debug join( "\n", @$log );

    { result => $result, function => $function, message=> $msg };


};

1;
