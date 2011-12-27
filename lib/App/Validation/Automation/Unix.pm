package App::Validation::Automation::Unix;

use Moose;
use namespace::autoclean;
use English qw( -no_match_vars );

=head1 NAME

App::Validation::Automation::Unix - Base Classs App::Validation::Automation

Stores utilities that perform Unix based validation

=head1 SYNOPSIS

App::Validation::Automation::Unix connects to remote server using SSH.The Public/Private Key pair should be generated and stored else connection establishment will fail.The location of Private key also needs to be specifed in the configuration file.Logs in and validates processes and filesystems post connection establishment.

=head1 ATTRIBUTES

unix_msg stores the message generated by Unix Class Methods,
connection stores the ssh connection object.

=cut

has 'unix_msg' => (
    is      => 'rw',
    isa     => 'Str',
    clearer => 'clear_unix_msg',
);

has 'connection' => (
    is  => 'rw',
    isa => 'Net::SSH::Perl',
);   

=head1 METHODS

=head2 connect

Connect and login to remote server. Host to connect to and user is passed as arguments.Returns true on success.

=cut

sub connect {
    my $self     = shift;
    my $hostname = shift;
    my $user     = shift;
    my ($ssh);

    #Prepare Connetion
    $ssh = Net::SSH::Perl->new(
        $hostname,
        protocol       => $self->config->{'COMMON.SSH_PROTO'},
        debug          => $self->config->{'COMMON.DEBUG_SSH'},
        identity_files => $self->config->{'COMMON.ID_RSA'},
    ) || confess "Couldn't ssh to $hostname : $OS_ERROR";
    $ssh->login($user)
        || confess "Couldn't login $user\@$hostname : $OS_ERROR";
   
    #set connection state in connection attribute
    $self->connection($ssh);

    return 1;
}

=head2 validate_process

Validates if correct no of process is running on remote server.The command fired to test process can either be a part of config or passed as argument.Returns true on success else returns false.

=cut

sub validate_process {
    my $self            = shift;
    my $process_tmpl    = shift;
    my $ssh             = $self->connection;
    my $remote_cmd_tmpl = shift || $self->config->{'COMMON.PROCESS_TMPL'};
    my ($process_name, $min, $msg, @processes, $process_count,
        $remote_cmd, $error, $status);
        
    ($process_name, $min)
            = ($process_tmpl =~ /^(.+?)\:(.+?)$/);
    $remote_cmd = sprintf("$remote_cmd_tmpl",$process_name);
    ($process_count, $error, $status) = $ssh->cmd($remote_cmd);
    chomp($process_count);
    if($error || ($status != 0)) {
        $msg .= "Remote Cmd Fired : $remote_cmd : Failed\n";
        $msg .= "Error : $error";
        $self->unix_msg($msg);
        return 0;
    }
    if( $process_count < $min ) {
        $msg .= "Remote Cmd Fired : $remote_cmd \n";
        $msg .= "Expected $min Found $process_count running";
        $self->unix_msg($msg);
        return 0;
    }

    return 1;
      
}

=head2 validate_mountpoint

Validates if a mountpoint is accessible on remote server.The command fired to test mountpoint can either be a part of config or passed as argument.Returns true on  success else returns false.

=cut

sub validate_mountpoint {
    my $self            = shift;
    my $mountpoint      = shift;
    my $ssh             = $self->connection;
    my $remote_cmd_tmpl = shift || $self->config->{'COMMON.FILESYS_TMPL'};
    my ($output, $remote_cmd, $error, $status, $msg);

    $remote_cmd = sprintf("$remote_cmd_tmpl",$mountpoint);
    ($output , $error, $status) = $ssh->cmd($remote_cmd);
    if($error || ($status != 0)) {
        $msg .= "\nRemote Cmd Fired : $remote_cmd : Failed\n";
        $msg .= "Error : $error";
        $self->unix_msg($msg);
        return 0;
    }
    
    return 1;
}

=head2 change_unix_pwd

Change password at unix level after password expiration at Website level.Uses Secret passphrase to decrypt the newly created password.Stores new encrypted password in password file

=cut

sub change_unix_pwd {
    my $self = shift;
    my ($home, $old_pwd, $new_pwd, $enc_pwd_file, $secret_pphrase, $crypt,
        $enc_new_pwd);
    $old_pwd        = $self->config->{'COMMON.OLD_PASSWORD'};
    $new_pwd        = $self->config->{'COMMON.PASSWORD'};
    $home           = $self->config->{'COMMON.DEFAULT_HOME'};
    $enc_pwd_file   = $self->config->{'COMMON.ENC_PASS_FILE'};
    $secret_pphrase = $self->secret_pphrase;
    $crypt          = Crypt::Lite->new( debug => 0 );

    #if old and new password match return in error
    if( $old_pwd eq $new_pwd ) {
        $self->unix_msg("Password change failed : old pwd = new pwd");
        return 0;
    }

    #Encrypt new password
    $enc_new_pwd = $crypt->encrypt($new_pwd, $secret_pphrase);

    open my $pwd_handle,">","$home/$enc_pwd_file"
            || confess "$home/$enc_pwd_file : $OS_ERROR";
    print {$pwd_handle} $enc_new_pwd;
    close $pwd_handle;

    return 1;

}

__PACKAGE__->meta->make_immutable;


1;
