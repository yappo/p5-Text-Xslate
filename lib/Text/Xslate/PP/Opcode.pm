package Text::Xslate::PP::Opcode;

use strict;
use warnings;

use Carp ();
use Scalar::Util ();

use Text::Xslate::PP::Const;
use Text::Xslate::Util qw(p mark_raw unmark_raw html_escape);

use constant TXframe_NAME       => Text::Xslate::PP::TXframe_NAME;
use constant TXframe_OUTPUT     => Text::Xslate::PP::TXframe_OUTPUT;
use constant TXframe_RETADDR    => Text::Xslate::PP::TXframe_RETADDR;
use constant TXframe_START_LVAR => Text::Xslate::PP::TXframe_START_LVAR;

use constant TX_VERBOSE_DEFAULT => Text::Xslate::PP::TX_VERBOSE_DEFAULT;

use constant _FOR_ITEM  => 0;
use constant _FOR_ITER  => 1;
use constant _FOR_ARRAY => 2;

no warnings 'recursion';

our @CARP_NOT = qw(Text::Xslate);


my %html_escape = (
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
    '"' => '&quot;',
    "'" => '&apos;',
);
my $html_unsafe_chars = sprintf '[%s]', join '', map { quotemeta } keys %html_escape;

our $_current_frame;


#
#
#

sub op_noop {
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_move_to_sb {
    $_[0]->{sb} = $_[0]->{sa};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_move_from_sb {
    $_[0]->{sa} = $_[0]->{sb};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_save_to_lvar {
    tx_access_lvar( $_[0], $_[0]->op_arg, $_[0]->{sa} );
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_load_lvar {
    $_[0]->{sa} = tx_access_lvar( $_[0], $_[0]->op_arg );
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_load_lvar_to_sb {
    $_[0]->{sb} = tx_access_lvar( $_[0], $_[0]->op_arg );
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

{
    package
        Text::Xslate::PP::Opcode::Guard;

    sub DESTROY { $_[0]->() }
}

sub op_localize_s {
    my($st) = @_;
    my $vars   = $st->{vars};
    my $key    = $st->op_arg;
    my $preeminent
               = exists $vars->{$key};
    my $oldval = delete $vars->{$key};
    my $newval = $st->{sa};

    my $cleanup = $preeminent
        ? sub { $vars->{$key} = $oldval; return }
        : sub { delete $vars->{$key};    return };
    push @{ $_[0]->{local_stack} ||= [] },
        bless($cleanup, 'Text::Xslate::PP::Opcode::Guard');

    $vars->{$key} = $newval;

    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_push {
    push @{ $_[0]->{ SP }->[ -1 ] }, $_[0]->{sa};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_pushmark {
    push @{ $_[0]->{ SP } }, [];
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_nil {
    $_[0]->{sa} = undef;
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_literal {
    $_[0]->{sa} = $_[0]->op_arg;
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_literal_i {
    $_[0]->{sa} = $_[0]->op_arg;
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_fetch_s {
    $_[0]->{sa} = $_[0]->{vars}->{ $_[0]->op_arg };
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_fetch_field {
    my $var = $_[0]->{sb};
    my $key = $_[0]->{sa};
    $_[0]->{sa} = tx_fetch( $_[0], $var, $key );
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_fetch_field_s {
    my $var = $_[0]->{sa};
    my $key = $_[0]->op_arg;
    $_[0]->{sa} = tx_fetch( $_[0], $var, $key );
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_print {
    my($st) = @_;
    my $sv = $st->{sa};

    if ( ref( $sv ) eq 'Text::Xslate::Type::Raw' ) {
        if(defined ${$sv}) {
            $st->{ output } .= ${$sv};
        }
        else {
            $st->warn(undef, "Use of nil to print" );
        }
    }
    elsif ( defined $sv ) {
        $sv =~ s/($html_unsafe_chars)/$html_escape{$1}/xmsgeo;
        $st->{ output } .= $sv;
    }
    else {
        $st->warn( undef, "Use of nil to print" );
    }

    goto $st->{ code }->[ ++$st->{ pc } ]->{ exec_code };
}


sub op_print_raw {
    my($st) = @_;
    if(defined $st->{sa}) {
        $st->{ output } .= $st->{sa};
    }
    else {
        $st->warn( undef, "Use of nil to print" );
    }
    goto $st->{ code }->[ ++$st->{ pc } ]->{ exec_code };
}


sub op_print_raw_s {
    $_[0]->{ output } .= $_[0]->op_arg;
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_include {
    my $st = Text::Xslate::PP::tx_load_template( $_[0]->engine, $_[0]->{sa} );

    $_[0]->{ output } .= Text::Xslate::PP::tx_execute( $st, $_[0]->{vars} );

    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_for_start {
    my($st) = @_;
    my $ar = $st->{sa};
    my $id = $st->op_arg;

    unless ( $ar and ref $ar eq 'ARRAY' ) {
        if ( defined $ar ) {
            $st->error( undef, "Iterator variables must be an ARRAY reference, not %s", tx_neat( $ar ) );
        }
        else {
            $st->warn( undef, "Use of nil to iterate" );
        }
        $ar = [];
    }

    #tx_access_lvar( $st, $id + _FOR_ITEM, undef );
    tx_access_lvar( $st, $id + _FOR_ITER, -1 );
    tx_access_lvar( $st, $id + _FOR_ARRAY, $ar );

    goto $st->{ code }->[ ++$st->{ pc } ]->{ exec_code };
}


sub op_for_iter {
    my($st) = @_;
    my $id = $st->{sa};
    my $av = tx_access_lvar( $st, $id + _FOR_ARRAY );

    if(defined $av) {
        my $i = tx_access_lvar( $st, $id + _FOR_ITER );
        $av = [ $av ] unless ref $av;
        if ( ++$i < scalar(@{ $av })  ) {
            tx_access_lvar( $st, $id + _FOR_ITEM, $av->[ $i ] );
            tx_access_lvar( $st, $id + _FOR_ITER, $i );
            goto $st->{ code }->[ ++$st->{ pc } ]->{ exec_code };
        }
        else {
            tx_access_lvar( $st, $id + _FOR_ITEM,  undef );
            tx_access_lvar( $st, $id + _FOR_ITER,  undef );
            tx_access_lvar( $st, $id + _FOR_ARRAY, undef );
        }
    }

    # finish
    $st->{ pc } = $st->op_arg;
    goto $st->{ code }->[ $st->{ pc } ]->{ exec_code };
}


sub op_add {
    $_[0]->{targ} = $_[0]->{sb} + $_[0]->{sa};
    $_[0]->{sa} = $_[0]->{targ};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_sub {
    $_[0]->{targ} = $_[0]->{sb} - $_[0]->{sa};
    $_[0]->{sa} = $_[0]->{targ};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_mul {
    $_[0]->{targ} = $_[0]->{sb} * $_[0]->{sa};
    $_[0]->{sa} = $_[0]->{targ};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_div {
    $_[0]->{targ} = $_[0]->{sb} / $_[0]->{sa};
    $_[0]->{sa} = $_[0]->{targ};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_mod {
    $_[0]->{targ} = $_[0]->{sb} % $_[0]->{sa};
    $_[0]->{sa} = $_[0]->{targ};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_concat {
    my $sv = $_[0]->op_arg;
    $sv .= $_[0]->{sb} . $_[0]->{sa};
    $_[0]->{sa} = $sv;
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_and {
    if ( $_[0]->{sa} ) {
        goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
    }
    else {
        $_[0]->{ pc } = $_[0]->op_arg;
        goto $_[0]->{ code }->[ $_[0]->{ pc } ]->{ exec_code };
    }
}


sub op_dand {
    if ( defined $_[0]->{sa} ) {
        goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
    }
    else {
        $_[0]->{ pc } = $_[0]->op_arg;
        goto $_[0]->{ code }->[ $_[0]->{ pc } ]->{ exec_code };
    }
}


sub op_or {
    if ( ! $_[0]->{sa} ) {
        goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
    }
    else {
        $_[0]->{ pc } = $_[0]->op_arg;
        goto $_[0]->{ code }->[ $_[0]->{ pc } ]->{ exec_code };
    }
}


sub op_dor {
    my $sv = $_[0]->{sa};
    if ( defined $sv ) {
        $_[0]->{ pc } = $_[0]->op_arg;
        goto $_[0]->{ code }->[ $_[0]->{ pc } ]->{ exec_code };
    }
    else {
        goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
    }

}


sub op_not {
    $_[0]->{sa} = ! $_[0]->{sa};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_plus {
    $_[0]->{targ} = + $_[0]->{sa};
    $_[0]->{sa} = $_[0]->{targ};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_minus {
    $_[0]->{targ} = - $_[0]->{sa};
    $_[0]->{sa} = $_[0]->{targ};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_max_index {
    $_[0]->{sa} = scalar(@{ $_[0]->{sa} }) - 1;
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_builtin_mark_raw {
    $_[0]->{sa} = mark_raw($_[0]->{sa});
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_builtin_unmark_raw {
    $_[0]->{sa} = unmark_raw($_[0]->{sa});
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_builtin_html_escape{
    $_[0]->{sa} = html_escape($_[0]->{sa});
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub _sv_eq {
    my($x, $y) = @_;
    if ( defined $x ) {
        return defined $y && $x eq $y;
    }
    else {
        return !defined $y;
    }
}

sub op_match {
    $_[0]->{sa} = Text::Xslate::Util::match($_[0]->{sb}, $_[0]->{sa});
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_eq {
    $_[0]->{sa} =  _sv_eq($_[0]->{sb}, $_[0]->{sa});
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_ne {
    $_[0]->{sa} = !_sv_eq($_[0]->{sb}, $_[0]->{sa});
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_lt {
    $_[0]->{sa} = $_[0]->{sb} < $_[0]->{sa};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_le {
    $_[0]->{sa} = $_[0]->{sb} <= $_[0]->{sa};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_gt {
    $_[0]->{sa} = $_[0]->{sb} > $_[0]->{sa};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_ge {
    $_[0]->{sa} = $_[0]->{sb} >= $_[0]->{sa};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_ncmp {
    $_[0]->{sa} = $_[0]->{sb} <=> $_[0]->{sa};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}
sub op_scmp {
    $_[0]->{sa} = $_[0]->{sb} cmp $_[0]->{sa};
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_symbol {
    my($st) = @_;
    my $name = $st->op_arg;

    if ( my $func = $st->symbol->{ $name } ) {
        $st->{sa} = $func;
    }
    else {
        Carp::croak("Undefined symbol $name");
        #$st->error( undef, "Undefined symbol %s", $name );
        #$st->{sa} = undef;
    }

    goto $st->{ code }->[ ++$st->{ pc } ]->{ exec_code };
}

sub tx_macro_enter {
    my($st, $macro, $retaddr) = @_;
    my $name   = $macro->name;
    my $addr   = $macro->addr;
    my $nargs  = $macro->nargs;
    my $outer  = $macro->outer;
    my $args   = pop @{ $st->{SP} };

    if(@{$args} != $nargs) {
        $st->error(undef, "Wrong number of arguments for %s (%d %s %d)",
            $name, scalar(@{$args}), scalar(@{$args}) > $nargs ? '>' : '<', $nargs);
        $st->{ sa } = undef;
        $st->{ pc }++;
        return;
    }

    my $cframe = Text::Xslate::PP::tx_push_frame( $st );

    $cframe->[ TXframe_RETADDR ] = $retaddr;
    $cframe->[ TXframe_OUTPUT ]  = $st->{ output };
    $cframe->[ TXframe_NAME ]    = $name;

    $_[0]->{ output } = '';

    my $i = 0;
    if($outer > 0) {
        # copies lexical variables from the old frame to the new one
        my $oframe = $_[0]->frame->[ $_[0]->current_frame - 1 ];
        for(; $i < $outer; $i++) {
            my $real_ix = $i + TXframe_START_LVAR;
            $cframe->[$real_ix] = $oframe->[$real_ix];
        }
    }

    for my $val (@{$args}) {
        tx_access_lvar( $_[0], $i++, $val );
    }

    $_[0]->{ pc } = $addr;
    return;
}

sub op_macro_end {
    my($st) = @_;
    my $frames   = $st->frame;
    my $oldframe = $frames->[ $st->current_frame ];
    my $cframe   = $frames->[ $st->current_frame( $st->current_frame - 1 ) ]; # pop frame

    if($st->op_arg) { # immediate macros
        $st->{targ} = $st->{ output };
    }
    else {
        $st->{targ} = mark_raw( $st->{ output } );
    }

    $st->{sa} = $st->{targ};

    $st->{ output } = $oldframe->[ TXframe_OUTPUT ];
    $st->{ pc }     = $oldframe->[ TXframe_RETADDR ];
    goto $st->{ code }->[ $st->{ pc } ]->{ exec_code };
}

sub op_funcall {
    my($st) = @_;
    my $func = $st->{sa};
    if(ref $func eq 'Text::Xslate::PP::Macro') {
        tx_macro_enter($st, $func, $st->{ pc } + 1);
        goto $st->{ code }->[ $st->{ pc } ]->{ exec_code };
    }
    else {
        $st->{sa} = tx_funcall( $st, $func );
        goto $st->{ code }->[ ++$st->{ pc } ]->{ exec_code };
    }
}

sub op_methodcall_s {
    require Text::Xslate::PP::Method;
    $_[0]->{sa} = Text::Xslate::PP::Method::tx_methodcall($_[0], $_[0]->op_arg);
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_make_array {
    my $args = pop @{ $_[0]->{SP} };
    $_[0]->{sa} = $args;
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_make_hash {
    my $args = pop @{ $_[0]->{SP} };
    $_[0]->{sa} = { @{$args} };
    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}


sub op_enter {
    push @{$_[0]->{save_local_stack} ||= []}, delete $_[0]->{local_stack};

    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_leave {
    $_[0]->{local_stack} = pop @{$_[0]->{save_local_stack}};

    goto $_[0]->{ code }->[ ++$_[0]->{ pc } ]->{ exec_code };
}

sub op_goto {
    $_[0]->{ pc } = $_[0]->op_arg;
    goto $_[0]->{ code }->[ $_[0]->{ pc } ]->{ exec_code };
}

sub op_end {
    $_[0]->{ pc } = $_[0]->code_len;

    if($_[0]->current_frame != 0) {
        Carp::croak("Oops: broken stack frame:" .  p($_[0]->frame));
    }
    return;
}

sub op_depend; *op_depend = \&op_noop;

sub op_macro_begin; *op_macro_begin = \&op_noop;
sub op_macro_nargs; *op_macro_nargs = \&op_noop;
sub op_macro_outer; *op_macro_outer = \&op_noop;

#
# INTERNAL COMMON FUNCTIONS
#

sub tx_access_lvar {
    return $_[0]->pad->[ $_[1] + TXframe_START_LVAR ] if @_ == 2;
    $_[0]->pad->[ $_[1] + TXframe_START_LVAR ] = $_[2];
}


sub tx_funcall {
    my ( $st, $proc ) = @_;
    my ( @args ) = @{ pop @{ $st->{ SP } } };
    my $ret;

    if(!defined $proc) {
        my $c = $st->{code}->[ $st->{pc} - 1 ];
        $st->error( undef, "Undefined function%s is called",
            $c->{ opname } eq 'fetch_s' ? " $c->{arg}()" : ""
        );
    }
    else {
        $ret = eval { $proc->( @args ) };
        $st->error( undef, "%s", $@) if $@;
    }

    return $ret;
}

sub tx_proccall {
    my($st, $proc) = @_;
    if(ref $proc eq 'Text::Xslate::PP::Macro') {
        local $st->{pc} = $st->{pc};

        tx_macro_enter($st, $proc, $st->{code_len});
        $st->{code}->[ $st->{pc} ]->{ exec_code }->( $st );
        return $st->{sa};
    }
    else {
        return tx_funcall($st, $proc);
    }
}

sub tx_fetch {
    my ( $st, $var, $key ) = @_;
    my $ret;

    if ( Scalar::Util::blessed($var) ) {
        $ret = eval { $var->$key() };
        $st->error(undef, "%s", $@) if $@;
    }
    elsif ( ref $var eq 'HASH' ) {
        if ( defined $key ) {
            $ret = $var->{ $key };
        }
        else {
            $st->warn( undef, "Use of nil as a field key" );
        }
    }
    elsif ( ref $var eq 'ARRAY' ) {
        if ( Scalar::Util::looks_like_number($key) ) {
            $ret = $var->[ $key ];
        }
        else {
            $st->warn( undef, "Use of %s as an array index", tx_neat( $key ) );
        }
    }
    elsif ( $var ) {
        $st->error( undef, "Cannot access %s (%s is not a container)", tx_neat($key), tx_neat($var) );
    }
    else {
        $st->warn( undef, "Use of nil to access %s", tx_neat( $key ) );
    }

    return $ret;
}

sub tx_neat {
    my($s) = @_;
    if ( defined $s ) {
        if ( ref($s) || Scalar::Util::looks_like_number($s) ) {
            return $s;
        }
        else {
            return "'$s'";
        }
    }
    else {
        return 'nil';
    }
}


1;
__END__

=head1 NAME

Text::Xslate::PP::Opcode - Text::Xslate opcode implementation in pure Perl

=head1 DESCRIPTION

This module is a pure Perl implementation of the Xslate opcodes.

The is enabled with C<< $ENV{ENV}='pp=opcode' >>.

=head1 SEE ALSO

L<Text::Xslate>

L<Text::Xslate::PP>

=head1 AUTHOR

Makamaka Hannyaharamitu E<lt>makamaka at cpan.orgE<gt>

Text::Xslate was written by Fuji, Goro (gfx).

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2010 by Makamaka Hannyaharamitu (makamaka).

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
