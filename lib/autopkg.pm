package autopkg;
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

use strict;
use Data::Dumper;
use YAML::XS qw(Dump Load);
use File::Path qw(make_path);
use File::Copy;
use File::Basename;
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use MIME::Base64;
use POSIX qw/strftime/;
use Socket;
use DBI qw(:sql_types);
use JSON;
use Dancer2::Plugin;
use qutil;
use 5.10.0;

use constant SUCCESS => "success";
use constant FAILED => "failed";
use constant WAITING => 0;
use constant PROCESSING => 1;
use constant COMPLETED_OK => 2;
use constant COMPLETED_WITH_ERRORS => 3;

# Define globals
our $VERSION = '0.1';
my @log;

# Define variables to hold settings
our $queue_db_file;

# Define variables to hold settings
has 'repo' => (
    is => 'rw', 
    required => 1,
    default => sub { {} },
    predicate => 'has_repo',
);

has 'pkg_log_file' => (
    is => 'rw', 
    required => 1,
    default => '/var/log/autopkg/pkg.og',
    predicate => 'has_pkg_log_file',
);

has 'queue_db_file' => (
    is => 'rw', 
    required => 1,
    default => 'database.sql',
    predicate => 'has_queue_db_file',
);

plugin_keywords qw/
    get_status
    queue_rpms
    process_pkg_queue
    pkg_log_file
    repo
/;

sub BUILD {
    my $self = shift;
    if( defined( $self->app->config->{repo}) ){
        $self->repo( $self->app->config->{repo} );
    }
    if( defined( $self->app->config->{pkg_log_file}) ){
        $self->pkg_log_file( $self->app->config->{pkg_log_file} );
    }
    if( defined( $self->app->config->{queue_db_file}) ){
        $self->queue_db_file( $self->app->config->{queue_db_file} );
    }
    #say Dumper( $self );
}


sub queue_rpms {
    my $self = shift;
    my $payload = shift;
    my $action = shift;
    my $event = shift;
    my $result = SUCCESS;
    my $msg;
    my @log;

    # validate the payload
    if( $result eq SUCCESS and ref($payload) ne 'ARRAY' ){
        $msg = "The payload needs to be an array of packaging requests";
        $result = FAILED; 
    }
    if( $result eq SUCCESS ){
        for my $req ( @$payload ){
            ( $result, $msg ) = $self->validate_property( $req, "Name" ) if $result eq SUCCESS;
            ( $result, $msg ) = $self->validate_property( $req, "Release" ) if $result eq SUCCESS;
            ( $result, $msg ) = $self->validate_property( $req, "Version" ) if $result eq SUCCESS;
            ( $result, $msg ) = $self->validate_property( $req, "InstallRoot" ) if $result eq SUCCESS;
            ( $result, $msg ) = $self->validate_property( $req, "Description" ) if $result eq SUCCESS;
            ( $result, $msg ) = $self->validate_property( $req, "Author" ) if $result eq SUCCESS;
            if( $result eq SUCCESS ){
                ( $result, $msg ) = $self->validate_property( $req, "YumRepository" );
                if( $result eq FAILED ){
                    ( $result, $msg ) = $self->validate_property( $req->{Target}, "Platform" );
                    ( $result, $msg ) = $self->validate_property( $req->{Target}, "Release" ) if $result eq SUCCESS;
                }
            }
            ( $result, $msg ) = $self->validate_property( $req->{Target}, "Package" ) if $result eq SUCCESS;
            ( $result, $msg ) = $self->validate_property( $req->{Target}, "Arch" ) if $result eq SUCCESS;
            ( $result, $msg ) = $self->validate_property( $req, "OverRide", [ "yes", "no" ] ) if $result eq SUCCESS;
            if( $result eq SUCCESS and ref($req->{Files}) ne 'ARRAY' ){
                $msg = "One of the packaging requests is missing a list of files";
                $result = FAILED; 
            }
            if( $result eq SUCCESS ){
                for my $file ( @{$req->{Files}} ){
                    ( $result, $msg ) = $self->validate_property( $file, "src_url", qr/^http[s]?:\/\// ) if $result eq SUCCESS;
                }
            }
            $req->{Action} = $action;
            $req->{Event} = $event;
        }
    }
    my $job_id;
    ( $result, $job_id ) = $self->queue_job( $payload );
    say $job_id;
    $msg = "The payload was successfully parsed and queued for procesing - job_id: $job_id" if $result eq SUCCESS;

    return { result => $result, message=> $msg, log => \@log };
}

sub validate_property {
    my $self = shift;
    my $data = shift;
    my $prop = shift;
    my $compare = shift;
    my ($result, $msg ) = ( SUCCESS, "" );
    if( ref($compare) eq 'ARRAY' ){
        my $found;
        for my $cmp ( @$compare ){
            $found = 1 if( $cmp eq $data->{$prop} );
        }
        if( not $found ){
            $msg = "The '$prop' property of one of the packaging requests is not one of the valid values: [". join(',', @$compare)."]";
            $result = FAILED; 
        }
    } elsif( $compare =~ /^\(\?/ ) {
        if( $data->{$prop} !~ /$compare/ ){
            $msg = "The '$prop' property of one of the packaging requests is not matching the regular expression: $compare";
            $result = FAILED; 
        }
    } elsif( ! $data->{$prop} ){
        $msg = "One of the packaging requests is missing the $prop property";
        $result = FAILED; 
    }
    return $result, $msg;
}

sub queue_job {
    my $self = shift;
    my $data = shift;
    my $subdir = shift;
    my $dbfile = top_level_dir."/".$self->queue_db_file;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","") or die $!;
    my $sth = $dbh->prepare("INSERT INTO queue (payload,status) VALUES (?, 0)");
    $sth->bind_param(1, encode_json( $data ), SQL_VARCHAR);
    $sth->execute();
    my $job_id = $dbh->last_insert_id(undef, undef, undef, undef);
    my $rc = $dbh->disconnect  or warn $dbh->errstr;
    return SUCCESS, $job_id;
}

sub get_status {
    my $self = shift;
    my $job_id = shift;
    my $result;
    my $msg;
    my $dbfile = top_level_dir."/".$self->queue_db_file;
    say $dbfile;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","") or die $!;
    my $sth = $dbh->prepare("SELECT status, message, rpm_url FROM queue WHERE job_id = ?");
    $sth->bind_param(1, $job_id, SQL_INTEGER);
    $sth->execute();
    my $table = $sth->fetchall_arrayref;
    my $rc = $dbh->disconnect  or warn $dbh->errstr;
    if( @$table == 1 ){
            my $status = $table->[0][0];
            my $message = $table->[0][1];
            my $rpm_url = $table->[0][2];
            if( $status == WAITING ){
                $msg = "Jobid: $job_id is still waiting to be processed";
            } elsif( $status == PROCESSING ){
                $msg = "Jobid: $job_id is currently being processed";
            } elsif( $status == COMPLETED_OK ){
                $msg = "Jobid: $job_id completed successfully. The RPM is available at: $rpm_url";
            } elsif( $status == COMPLETED_WITH_ERRORS ){
                $msg = "Jobid: $job_id completed with errors. The error message was $message";
            } elsif( $status > COMPLETED_WITH_ERRORS ){
                $msg = "The status of job_id: $job_id is in an undetermined state. The message was $message";
            }
            $result = SUCCESS; 
    } elsif( @$table < 1 ){
            $msg = "Job_id: $job_id was not found in the job list";
            $result = FAILED; 
    } else {
            $msg = "Looking for job_id: $job_id returned more jobs than expected";
            $result = FAILED; 
    }
    return { result => $result, message=> $msg, log => [] };
}

sub process_pkg_queue {
    my $self = shift;
    my $overall_status;
    my $overall_message;

    # Open a log file - helpful while debugging in daemon mode
    open LOG, ">>".$self->pkg_log_file or die $!;

    # Find the payloads waiting to be processed
    my $dbfile = top_level_dir."/".$self->queue_db_file;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","") or die $!;
    my $sth = $dbh->prepare("SELECT job_id, payload FROM queue WHERE status = ?");
    $sth->bind_param(1, WAITING, SQL_INTEGER);
    $sth->execute();
    my $table = $sth->fetchall_arrayref;
    my $rc = $dbh->disconnect  or warn $dbh->errstr;
    # Finish quietly if nothing is in the queue
    return if( @$table < 1 );

    # Update the status to say we are processing
    $self->update_status( PROCESSING, "", { status => WAITING } );

    # Keep a list of repositories to be updated
    my %repos;

    # Process each of the payloads
    for my $row ( @$table ){
        my $status;
        my $message;

        my( $job_id, $payload_json ) = @$row;
        my $payload = decode_json( $payload_json ) or die $!;
        my $i;
        OUTER: for my $sub_job( @$payload ){
            $i++;
            say LOG "JOB: ". $job_id . ", SUBJOB: ", $i;
            if( $sub_job->{Target}{Package} eq "rpm" ){
                # Build RPM
                my $rpm =  "$sub_job->{Name}-$sub_job->{Version}-$sub_job->{Release}.$sub_job->{Target}{Arch}.rpm";
                say LOG "\tBuilding RPM for $rpm";
                make_path(top_level_dir."/rpmbuild/SPECS/", { mode => 0755 });
                make_path(top_level_dir."/rpmbuild/SOURCES/", { mode => 0755 });
                make_path(top_level_dir."/rpmbuild/BUILD/", { mode => 0755 });
                my $specfile = top_level_dir."/rpmbuild/SPECS/$sub_job->{Name}.spec";
                for my $file ( @{$sub_job->{Files}} ){
                    my( $owner, $group ) = ( 'root', 'root' );
                    my $perms = '0644';
                    ( $owner, $group ) = split /:/, $file->{owner} if $file->{owner};
                    my $path = $sub_job->{InstallRoot}."/".$file->{RelPath};
                    $file->{RelPath} =~ s/^\///;
                    my $src = $file->{SrcUrl};
                    $perms = $file->{Perms} if $file->{Perms};
                    my $rel_path = top_level_dir."/rpmbuild/SOURCES/".$file->{RelPath};
                    my $output = `curl -s -S -k --noproxy \\* -o '$rel_path' --create-dirs '$file->{SrcUrl}' 2>&1`;
                    $self->update_status( COMPLETED_WITH_ERRORS, $output, { job_id => $job_id } ) && next OUTER if( $output );
                }
                $sub_job->{Group} = "Applications/Internet" if ! $sub_job->{Group};
                $sub_job->{License} = "Proprietory" if ! $sub_job->{License};
                $sub_job->{ChangeLog} = "n/a" if ! $sub_job->{ChangeLog};
                open SPEC, ">$specfile" or die $!;
                print SPEC <<SPECFILE;
Name:           $sub_job->{Name}
Version:        $sub_job->{Version}
Release:        $sub_job->{Release}
BuildArch:      $sub_job->{Target}{Arch}
Summary:        $sub_job->{Description}
Group:          $sub_job->{Group}
License:        $sub_job->{License}
SPECFILE
                my $j = 0;
                for my $file ( @{$sub_job->{Files}} ){
                    print SPEC <<SPECFILE;
Source$j:        $file->{RelPath}
SPECFILE
                    $j++;
                }
                print SPEC <<SPECFILE;
Prefix:         $sub_job->{InstallRoot}
%description
$sub_job->{Description}

%install
SPECFILE
                for my $file ( @{$sub_job->{Files}} ){
                    print SPEC <<SPECFILE;
mkdir -p \$(dirname \$RPM_BUILD_ROOT/$sub_job->{InstallRoot}/$file->{RelPath} )
install -m 644 \$RPM_SOURCE_DIR/$file->{RelPath} \$RPM_BUILD_ROOT/$sub_job->{InstallRoot}/$file->{RelPath}
SPECFILE
                }
                print SPEC <<SPECFILE;

%clean
rm -rf \$RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
$sub_job->{InstallRoot}
SPECFILE
                for my $file ( @{$sub_job->{Files}} ){
                    print SPEC <<SPECFILE;
$sub_job->{InstallRoot}/$file->{RelPath}
SPECFILE
                }
                print SPEC <<SPECFILE;
%doc
SPECFILE
#%changelog
#* $sub_job->{ChangeLog}
                close SPEC;
                my $cmd = "rpmbuild --define '_topdir ".top_level_dir."/rpmbuild' -bb --quiet --clean --rmsource --rmspec $specfile";
                my $output = `$cmd 2>&1`;
                print $output;
                if( $output =~ /error/i ){
                    say LOG "\tThere was an error producing the RPM: $output";
                    $status = COMPLETED_WITH_ERRORS;
                } else {
                    my $rel_path;
                    if( $sub_job->{YumRepository} ){
                        $rel_path = join( '/', $self->repo->{rel_path}, $sub_job->{YumRepository} );
                    } else {
                        $rel_path = join( '/', $self->repo->{rel_path}, $sub_job->{Target}{Platform}, $sub_job->{Target}{Release} );
                    }
                    my $repo = join( '/', $self->repo->{dir}, $rel_path );
                    my $repo_url = join( '/', $self->repo->{served_at}, $rel_path );
                    my $rpm_url = join( '/', $repo_url, $rpm );
                    say $repo;
                    say $rpm;
                    say $repo_url;
                    $rpm_url =~ s|([^:])/+|$1/|g;
                    say $rpm_url;
                    make_path("$repo", { mode => 0755 });
                    if( move( top_level_dir."/rpmbuild/RPMS/$sub_job->{Target}{Arch}/$rpm", "$repo/$rpm") ){
                        $self->update_rpm_url( $rpm_url, $job_id );
                        $status = COMPLETED_OK;
                        $overall_status++;
                    } else {
                        $status = COMPLETED_WITH_ERRORS;
                        $message = $!;
                    }
                    # Add the destination directory to the list of repositories to be updated at the end
                    $repos{$repo} = 'blah';
                }
                $self->update_status( $status, $message, { job_id => $job_id } );
                next OUTER if $status == COMPLETED_WITH_ERRORS;
            } else {
                # Unknown Package format
                $message = "Error: Unknown packaging format: $sub_job->{Target}{Package}";
                say LOG "\t$message";
                $self->update_status( COMPLETED_WITH_ERRORS, $message, { job_id => $job_id } );
            }
        }
    }
    if( $overall_status > 0 ){
        for my $repo ( keys %repos ){
            # Create yum repo
            my $cmd = "/usr/bin/createrepo $repo";
            my $output = `$cmd 2>&1`;
            if( $output !~ /complete/ ){
                say LOG "\tThere was an error creating the repo ($repo): $output";
            }
        }

    }
    close LOG;
    
    
}

sub update_status {
    my $self = shift;
    my $status = shift;
    my $message = shift;
    my $query = shift;
    my $field = (keys %$query)[0];
    my $value = $query->{$field};
    chomp( $message );

    my $dbfile = top_level_dir."/".$self->queue_db_file;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","") or die $!;
    my $sth = $dbh->prepare("UPDATE queue SET status = ?, message = ? WHERE $field = ?");
    $sth->bind_param(1, $status,  SQL_INTEGER);
    $sth->bind_param(2, $message, SQL_VARCHAR);
    $sth->bind_param(3, $value,   SQL_INTEGER);
    $sth->execute() or die $dbh->errstr;
    my $rc = $dbh->disconnect  or warn $dbh->errstr;

}

sub update_rpm_url {
    my $self = shift;
    my $rpm_url = shift;
    my $job_id = shift;

    my $dbfile = top_level_dir."/".$self->queue_db_file;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","") or die $!;
    my $sth = $dbh->prepare("UPDATE queue SET rpm_url = ? WHERE job_id = ?");
    $sth->bind_param(1, $rpm_url,  SQL_VARCHAR);
    $sth->bind_param(2, $job_id, SQL_INTEGER);
    $sth->execute() or die $dbh->errstr;
    my $rc = $dbh->disconnect  or warn $dbh->errstr;

}


1;
