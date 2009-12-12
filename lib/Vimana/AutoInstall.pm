package Vimana::AutoInstall;
use warnings;
use strict;

# use re 'debug';
use File::Copy::Recursive qw(fcopy rcopy dircopy fmove rmove dirmove);
use File::Spec;
use File::Path qw'mkpath rmtree';
use Archive::Any;
use File::Find;
use File::Type;
use Vimana::Logger;
use Vimana::Util;
use DateTime;
use base qw(Vimana::Accessor);
__PACKAGE__->mk_accessors( qw(package options) );

$| = 1;

=encoding utf8

=head1 NAME

Vimana::AutoInstall

=head1 DESCRIPTION

=head1 FUNCTIONS

=cut

sub inspect_text_content {
    my $self = shift;
    my $content = $self->package->content;
    return 'colors'   if $content =~ m/^let\s+(g:)?colors_name\s*=/;
    return 'syntax'   if $content =~ m/^syn[tax]* (?:match|region|keyword)/;
    return 'compiler' if $content =~ m/^let\s+current_compiler\s*=/;
    return 'indent'   if $content =~ m/^let\s+b:did_indent/;
    return undef;
}

=head2 run

=cut


sub run {
    my ( $self ) = @_;

    my $pkg = $self->package;

    if( $pkg->is_archive() ) {
        $logger->info('Archive file');
        return $self->install_from_archive;
    }
    elsif( $pkg->is_text() ) {
        $logger->info('Plain Text file');

        my $type = $self->inspect_text_content;
        if ($type) {
            $logger->info("Found script type: $type");
            return $self->install_to($type);
        }

        return $self->install_to( 'colors' )
            if $pkg->script_is('color scheme');

        return $self->install_to( 'syntax' )
            if $pkg->script_is('syntax');

        return $self->install_to( 'indent' )
            if $pkg->script_is('indent');

        return $self->install_to( 'ftplugin' )
            if $pkg->script_is('ftplugin');

        return 0;
    }

}

=head2 install_to 

=cut

sub install_to {
    my ( $self , $dir ) = @_;
    my $file = $self->package->file;
    my $target = File::Spec->join( runtime_path(), $dir );
    File::Path::mkpath [ runtime_path() ];

    $logger->info( "Install $file to $target" );
    my $ret = fcopy( $file => $target );
    !$ret ? 
        $logger->error( $! ) :
        $logger->info("Installed");
    $ret;
}

sub find_vimball_files {
    my $out = shift;
    my @vimballs;
    File::Find::find(  sub {
            return unless -f $_;
            push @vimballs , File::Spec->join($File::Find::dir , $_ ) if /\.vba$/;
        } , $out );
    return @vimballs;
}

=head2 install_from_archive 

=cut

sub install_from_archive {
    my $self = shift;
    my $options = $self->options;
    my $pkg = $self->package;

    my @files = $pkg->archive->files;

    if( $options->{verbose} ) {
        for (@files ) {
            print "FILE: $_ \n";
        }
    }

    my $out = Vimana::Util::tempdir();
    rmtree [ $out ] if -e $out;
    mkpath [ $out ];
    $logger->info("Temporary directory created: $out") if $options->{verbose};

    $logger->info("Extracting...") if $options->{verbose};
    $pkg->archive->extract( $out );  

    if( $pkg->has_vimball() ) {
        $logger->info( "I found vimball files inside the archive file , trying to install vimballs");
        use Vimana::VimballInstall;
        my @vimballs = find_vimball_files $out;
        Vimana::VimballInstall->install_vimballs( @vimballs );
    }

    # check directory structure
    {

        # XXX: check vim runtime path subdirs , mv to init script
        $logger->info("Initializing vim runtime path...") if $options->{verbose};
        Vimana::Util::init_vim_runtime();

        my @files;
        File::Find::find(  sub {
                return unless -f $_;
                push @files , File::Spec->join( $File::Find::dir , $_ ) if -f $_;
            } , $out );

        my $nodes = $self->find_base_path( \@files );

        unless ( keys %$nodes ) {
            $logger->warn("Can't found base path.");
            return 0;
        }
        
        if( $options->{verbose} ) {
            $logger->info('base path:');
            $logger->info( $_ ) for ( keys %$nodes );
        }

        $self->install_from_nodes( $nodes , runtime_path() );

        $logger->info("Updating helptags");
        $self->update_vim_doc_tags();
    }

    $logger->info("Clean up temporary directory.");
    rmtree [ $out ] if -e $out;

    return 1;
}




=head2 install_from_nodes

=cut

sub install_from_nodes {
    my ($self , $nodes , $to ) = @_;
    $logger->info("Copying files...");
    for my $node  ( grep { $nodes->{ $_ } > 1 } keys %$nodes ) {
        $logger->info("$node => $to") if $self->options->{verbose};
        my (@ret) = dircopy($node, $to );

    }
}

=head2 i_know_what_to_do

=cut

sub i_know_what_to_do {
    my $nodes = shift;
    for my $v ( values %$nodes ) {
        return 1 if $v > 1;
    }
    return 0;  # i am not sure
}


=head2 find_base_path 

=cut

sub find_base_path {
    my ( $self, $paths ) = @_;
    my $nodes = {};
    for my $p ( @$paths ) {
        if ( $p =~ m{^(.*?/)?(plugin|doc|syntax|indent|colors|autoload|after|ftplugin)/.*?\.(vim|txt)$} ) {
            $nodes->{ $1 || '' } ++;
        }
    }
    return $nodes;
}

sub update_vim_doc_tags {
    my $vim = find_vim();
    my $dir = File::Spec->join( runtime_path() , 'doc' );
    system(qq|$vim -c ':helptags $dir'  -c q |);
}


=head1 AUTHOR

You-An Lin 林佑安 ( Cornelius / c9s ) C<< <cornelius.howl at gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007 You-An Lin ( Cornelius / c9s ), all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1;
